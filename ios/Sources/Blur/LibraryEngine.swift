// LibraryEngine.swift — the on-device organizer.
//
// FORKED from the Nuke capture app's SyncEngine, with the upload path and GPS
// gate REMOVED — Blur never sends a photo anywhere. What remains is the
// PhotoKit scanning half, repurposed: instead of uploading assets, we read
// Apple's own organization (user albums + smart albums) and present it as
// galleries. The "hidden" set (the blur/curate flags) is persisted locally.
//
// This is the free tier in full. The paid upgrade layers passive clustering
// (Vision feature-prints) on top of this same scan — it does not replace it.

import Foundation
import Photos
import PhotosUI
import UIKit

@MainActor
final class LibraryEngine: ObservableObject {

    /// One shared instance — the BGAppRefreshTask handler and the SwiftUI
    /// views drive the same state.
    static let shared = LibraryEngine()

    // ─── Published state (SwiftUI renders this) ──────────────────────────────
    @Published private(set) var galleries: [Gallery] = []
    @Published private(set) var isScanning = false
    @Published private(set) var authorizationDenied = false
    @Published private(set) var lastScanDate: Date?

    /// False until the first scan of this app session completes — lets the UI
    /// show a loading state instead of an empty state during first launch.
    @Published private(set) var didCompleteInitialScan = false

    /// The last scan's tally — the scan's pulse, surfaced in Settings and the
    /// console so a stuck or empty scan is never silent (production-engineering
    /// law #6: a fire-and-forget path needs the thing that notices it failing).
    @Published private(set) var lastScan: ScanSummary?

    /// True when the user granted access to only a SUBSET of their library
    /// (iOS limited-access mode). The UI surfaces Apple's own "select more
    /// photos" picker in this case — we never work around the limit, we use it.
    @Published private(set) var accessIsLimited = false

    /// The whole library ("Recents"), newest first — powers the Library tab, so
    /// Blur opens to your photos exactly like the Photos app.
    @Published private(set) var allPhotoIDs: [String] = []

    /// Per-asset date + burst id, captured during the scan — lets the grid
    /// cluster "blasts" into stacks without re-fetching PhotoKit.
    @Published private(set) var assetMeta: [String: AssetMeta] = [:]

    // ── Stacks (collapse blasts) — customizable metrics ──
    @Published var stacksEnabled: Bool = UserDefaults.standard.object(forKey: "stacksEnabled") as? Bool ?? true {
        didSet { defaults.set(stacksEnabled, forKey: "stacksEnabled") }
    }
    /// Photos within this many seconds of each other (and same day) count as one blast.
    @Published var stackGapSeconds: Double = UserDefaults.standard.object(forKey: "stackGap") as? Double ?? 10 {
        didSet { defaults.set(stackGapSeconds, forKey: "stackGap") }
    }
    /// A run must reach this size to collapse into a stack.
    @Published var stackMinCount: Int = UserDefaults.standard.object(forKey: "stackMin") as? Int ?? 4 {
        didSet { defaults.set(stackMinCount, forKey: "stackMin") }
    }

    /// The three-state view lens (the eye, top-right): Reveal shows everything
    /// crisp (curation), Blur softens flagged photos, Hidden drops them from the
    /// feed entirely (the safe hand-over).
    @Published var viewMode: ViewMode = .blur

    /// Asset localIdentifiers the user has marked hidden (blurred) by hand.
    /// Rendered with a heavy blur and hidden entirely in "Show mode".
    @Published private(set) var hiddenAssetIDs: Set<String> = []

    /// Photo "tags"/categories chosen to auto-blur — gallery ids (Apple albums +
    /// smart albums like Screenshots/Favorites/Bursts). Every photo carrying the
    /// tag blurs, and new matching photos blur automatically on the next scan.
    /// This is the cold, tag-driven half of the blur engine (no ML).
    @Published private(set) var blurredCategoryIDs: Set<String> = []

    /// Asset ids blurred BY an active category rule, derived from
    /// blurredCategoryIDs × the current galleries. Stored as a set so isHidden
    /// stays O(1) per tile.
    @Published private(set) var ruleBlurredIDs: Set<String> = []

    // ── Vision index (Layer 2 — computed by us, cached on device) ──
    /// assetID → {subjects, OCR text} Vision read for it. Persisted to a JSON
    /// file (too big for UserDefaults on a real library).
    @Published private(set) var visionIndex: [String: PhotoVision] = [:]
    @Published private(set) var indexing = false
    @Published private(set) var indexedCount = 0
    /// How hard Vision works — Off (only when you ask), Gentle (paced, backs off
    /// when hot), Fast. Default Gentle so the phone stays cool and smooth.
    @Published var indexIntensity: IndexIntensity =
        IndexIntensity(rawValue: UserDefaults.standard.string(forKey: "indexIntensity") ?? "") ?? .gentle {
        didSet { defaults.set(indexIntensity.rawValue, forKey: "indexIntensity") }
    }
    /// Subject labels chosen to auto-blur ("Vehicle" → blur every car). This is
    /// "blur anything automotive," on-device.
    @Published private(set) var blurredSubjects: Set<String> = []
    @Published private(set) var subjectBlurredIDs: Set<String> = []

    // ── Libraries (curated collections — the reclaimed word) ──
    /// User-composed libraries (Family, Work…): a named set of people + subjects.
    /// Derived from the tags, never touching the chronological archive itself.
    @Published private(set) var libraries: [CuratedLibrary] = []
    /// Which libraries are currently blurred (stackable — blur several at once).
    @Published private(set) var blurredLibraryIDs: Set<UUID> = []
    @Published private(set) var libraryBlurredIDs: Set<String> = []

    // ── People (on-device face clustering) ──
    /// One entry per clustered person (representative vector + cover).
    @Published private(set) var personReps: [Person] = []
    /// Distance below which two faces are the same person. Device-tunable — this
    /// is the one knob that needs real-face calibration.
    @Published var faceThreshold: Double = UserDefaults.standard.object(forKey: "faceThreshold") as? Double ?? 18 {
        didSet { defaults.set(faceThreshold, forKey: "faceThreshold") }
    }

    // ─── Persistence (UserDefaults; required-reason CA92.1) ──────────────────
    private let defaults = UserDefaults.standard
    private enum Key {
        static let hidden = "hiddenAssetIDs"
        static let lastScan = "lastScanDate"
        static let blurredCategories = "blurredCategoryIDs"
        static let blurredSubjects = "blurredSubjects"
        static let blurredLibraries = "blurredLibraryIDs"
    }

    private var changeObserver: LibraryObserver?
    private var started = false

    private init() {
        if let saved = defaults.stringArray(forKey: Key.hidden) {
            hiddenAssetIDs = Set(saved)
        }
        if let cats = defaults.stringArray(forKey: Key.blurredCategories) {
            blurredCategoryIDs = Set(cats)
        }
        if let subs = defaults.stringArray(forKey: Key.blurredSubjects) {
            blurredSubjects = Set(subs)
        }
        // visionIndex is potentially huge (79k) — decoding it on the main thread
        // here blocks launch, so it loads off-main in start() instead.
        personReps = Self.loadPeople()
        libraries = Self.loadLibraries()
        if let libs = defaults.stringArray(forKey: Key.blurredLibraries) {
            blurredLibraryIDs = Set(libs.compactMap { UUID(uuidString: $0) })
        }
        lastScanDate = defaults.object(forKey: Key.lastScan) as? Date
        recomputeSubjectBlurred()
    }

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    /// Request read access, register the change observer, run the first scan.
    /// Safe to call repeatedly (foreground transitions) — only the scan re-runs.
    func start() async {
        if started { await rescan(); return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            authorizationDenied = true
            return
        }
        authorizationDenied = false
        accessIsLimited = (status == .limited)
        started = true

        let observer = LibraryObserver { [weak self] in
            Task { @MainActor in await self?.rescan() }
        }
        PHPhotoLibrary.shared().register(observer)
        changeObserver = observer

        // Instant open: show the last-known photo list immediately, then refresh
        // with a fresh scan in the background. Beats waiting on a 79k-photo
        // enumeration every launch.
        if allPhotoIDs.isEmpty {
            let cached = Self.loadPhotoIDs()
            if !cached.isEmpty {
                allPhotoIDs = cached
                didCompleteInitialScan = true
            }
        }

        // Load the heavy Vision index off the main thread, then apply the blur
        // decisions — so launch isn't blocked decoding 79k entries.
        if visionIndex.isEmpty {
            let loaded = await Task.detached(priority: .utility) { Self.loadVisionIndex() }.value
            if !loaded.isEmpty {
                visionIndex = loaded
                indexedCount = loaded.count
                recomputeSubjectBlurred()
                recomputeLibraryBlurred()
            }
        }

        await rescan()
    }

    // ─── The scan ──────────────────────────────────────────────────────────--

    /// Rebuild the gallery list from Apple's on-device organization. Returns
    /// true on a clean pass (the BG task reports this via setTaskCompleted).
    @discardableResult
    func rescan() async -> Bool {
        guard !isScanning, !authorizationDenied else { return false }
        isScanning = true
        // Authorization can change between passes (Settings, or the limited
        // picker) — keep the flag honest.
        accessIsLimited = (PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited)
        defer {
            isScanning = false
            didCompleteInitialScan = true
            lastScanDate = Date()
            defaults.set(lastScanDate, forKey: Key.lastScan)
        }

        // CRITICAL: PhotoKit enumeration over a real (tens-of-thousands) library
        // is heavy. Do it OFF the main thread — a synchronous scan on the main
        // actor blocks long enough that iOS's watchdog kills the app on launch.
        let result = await Task.detached(priority: .userInitiated) { () -> ScanResult in
            let lib = Self.userLibrary()
            let userAlbums = Self.collectGalleries(in: .album, source: .userAlbum)
            let smart = Self.smartGalleries()
            let built = (userAlbums + smart)
                .filter { $0.count > 0 }
                .sorted { lhs, rhs in
                    if lhs.source != rhs.source { return lhs.source == .userAlbum }
                    return lhs.count > rhs.count
                }
            return ScanResult(allPhotoIDs: lib.ids, assetMeta: lib.meta, galleries: built,
                              userAlbums: userAlbums.count, smartAlbums: smart.count)
        }.value

        // Publish on the main actor (we're back on it here). Only reassign when
        // something actually CHANGED — otherwise a pull-to-refresh over an
        // unchanged large library would force SwiftUI to re-diff tens of
        // thousands of tiles and rebuild the whole grid on the main thread
        // (the freeze). Equality checks are O(n) but far cheaper than that.
        if allPhotoIDs != result.allPhotoIDs {
            allPhotoIDs = result.allPhotoIDs
            Self.savePhotoIDs(result.allPhotoIDs)   // for instant open next time
        }
        if assetMeta.count != result.assetMeta.count { assetMeta = result.assetMeta }
        if galleries != result.galleries {
            galleries = result.galleries
            recomputeRuleBlurred()   // new photos in a tagged category blur automatically
        }
        recomputeLibraryBlurred()

        let photos = result.galleries.reduce(0) { $0 + $1.count }
        lastScan = ScanSummary(galleries: result.galleries.count, userAlbums: result.userAlbums,
                               smartAlbums: result.smartAlbums, photos: photos)
        if result.galleries.isEmpty {
            NSLog("Blur scan: 0 galleries — library empty or PhotoKit returned nothing")
        } else {
            NSLog("Blur scan: %d galleries (%d user, %d smart), %d photos",
                  result.galleries.count, result.userAlbums, result.smartAlbums, photos)
        }

        // Keep Vision working through the library continuously — auto-resume the
        // index whenever there's unread work (unless Off), at low priority so the
        // UI always wins. indexLibrary() guards double-runs and skips the done.
        if indexIntensity != .off && !indexing && unindexedCount > 0 {
            Task(priority: .utility) { await indexLibrary() }
        }
        return true
    }

    /// User albums, split into "yours" vs iCloud-shared (someone else's
    /// oversharing). `nonisolated` so the scan runs off the main thread.
    nonisolated private static func collectGalleries(in type: PHAssetCollectionType, source: GallerySource) -> [Gallery] {
        let collections = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
        var out: [Gallery] = []
        collections.enumerateObjects { collection, _, _ in
            let src: GallerySource = collection.assetCollectionSubtype == .albumCloudShared
                ? .sharedAlbum : source
            if let gallery = Self.gallery(from: collection, source: src) { out.append(gallery) }
        }
        return out
    }

    /// A curated set of Apple's smart albums — the free "seed" layer.
    nonisolated private static func smartGalleries() -> [Gallery] {
        // Note: the whole library ("Recents") is NOT here — it's the Library tab
        // (allPhotoIDs). These are the curated smart albums shown under Albums.
        let subtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumSelfPortraits,
            .smartAlbumScreenshots,
            .smartAlbumPanoramas,
            .smartAlbumBursts,
            .smartAlbumRecentlyAdded,
        ]
        var out: [Gallery] = []
        for subtype in subtypes {
            let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            collections.enumerateObjects { collection, _, _ in
                if let gallery = Self.gallery(from: collection, source: .smartAlbum) { out.append(gallery) }
            }
        }
        return out
    }

    /// The whole photo library ("Recents") as asset ids, newest first — the
    /// Library tab. Guarantees the app is never empty for someone with photos
    /// but no albums; mirrors how Photos itself opens.
    nonisolated private static func userLibrary() -> (ids: [String], meta: [String: AssetMeta]) {
        let cols = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
        guard let lib = cols.firstObject else { return ([], [:]) }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: lib, options: options)
        var ids: [String] = []
        var meta: [String: AssetMeta] = [:]
        ids.reserveCapacity(assets.count)
        meta.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
            // Cheap properties — captured here so the grid can cluster "blasts"
            // (bursts + rapid runs) into stacks without re-fetching.
            meta[asset.localIdentifier] = AssetMeta(date: asset.creationDate,
                                                    burstID: asset.burstIdentifier)
        }
        return (ids, meta)
    }

    /// Materialize one collection into a Gallery (image assets only, newest first).
    nonisolated private static func gallery(from collection: PHAssetCollection, source: GallerySource) -> Gallery? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(in: collection, options: options)
        guard assets.count > 0 else { return nil }

        var ids: [String] = []
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }

        return Gallery(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Untitled",
            source: source,
            assetIDs: ids,
            coverAssetID: ids.first
        )
    }

    // ─── Hidden (blur/curate) state ──────────────────────────────────────────

    /// A photo is blurred if hidden by hand, OR it carries an auto-blur tag
    /// (category / subject), OR it belongs to a blurred library.
    func isHidden(_ assetID: String) -> Bool {
        hiddenAssetIDs.contains(assetID)
            || ruleBlurredIDs.contains(assetID)
            || subjectBlurredIDs.contains(assetID)
            || libraryBlurredIDs.contains(assetID)
    }

    func toggleHidden(_ assetID: String) {
        if hiddenAssetIDs.contains(assetID) {
            hiddenAssetIDs.remove(assetID)
        } else {
            hiddenAssetIDs.insert(assetID)
        }
        defaults.set(Array(hiddenAssetIDs), forKey: Key.hidden)
    }

    /// Batch curation — the Select tool and grab-the-blast blur/reveal many at once.
    func setHidden(_ ids: some Sequence<String>, _ hidden: Bool) {
        if hidden { hiddenAssetIDs.formUnion(ids) } else { hiddenAssetIDs.subtract(ids) }
        defaults.set(Array(hiddenAssetIDs), forKey: Key.hidden)
    }

    // ─── Tag-driven blur (the cold engine) ───────────────────────────────────

    /// Is this category (gallery id) set to auto-blur?
    func isCategoryBlurred(_ galleryID: String) -> Bool {
        blurredCategoryIDs.contains(galleryID)
    }

    /// Toggle auto-blur for a whole category. Every photo in it blurs now, and
    /// new members blur on the next scan.
    func setCategoryBlur(_ galleryID: String, _ on: Bool) {
        if on { blurredCategoryIDs.insert(galleryID) } else { blurredCategoryIDs.remove(galleryID) }
        defaults.set(Array(blurredCategoryIDs), forKey: Key.blurredCategories)
        recomputeRuleBlurred()
    }

    /// Rebuild the rule-blurred asset set from the active category tags × the
    /// current galleries. Cheap set-union; runs on scan and on every toggle.
    private func recomputeRuleBlurred() {
        var ids = Set<String>()
        for gallery in galleries where blurredCategoryIDs.contains(gallery.id) {
            ids.formUnion(gallery.assetIDs)
        }
        ruleBlurredIDs = ids
    }

    // ─── Vision subjects (Layer 2) ───────────────────────────────────────────

    /// Run Vision over the whole library, caching subject labels per photo.
    /// Skips already-indexed photos, so it's resumable and only pays once.
    func indexLibrary() async {
        guard !indexing else { return }
        indexing = true
        var work = visionIndex
        var reps = personReps
        var nextPersonID = (reps.map { $0.id }.max() ?? 0) + 1
        var processed = 0
        // Priority order: Favorites first (explicitly important), then the rest
        // newest-first. The work[id]==nil guard dedups the overlap.
        let favorites = galleries.first { $0.source == .smartAlbum && $0.title.lowercased().contains("favorite") }?.assetIDs ?? []
        let order = favorites + allPhotoIDs
        for id in order where work[id] == nil {
            if Task.isCancelled || indexIntensity == .off { break }
            let vt = await VisionTagger.tags(for: id)

            // Throttle: a breath between photos, longer when the phone is warm,
            // so indexing stays a cool trickle instead of pinning the chip.
            var pause = indexIntensity.pauseMs
            switch ProcessInfo.processInfo.thermalState {
            case .serious: pause += 600
            case .critical: pause += 2000
            default: break
            }
            if pause > 0 { try? await Task.sleep(nanoseconds: pause * 1_000_000) }

            // Cluster this photo's faces into people (greedy nearest-rep).
            var people = Set<Int>()
            for vec in vt.facePrints {
                if let match = reps.min(by: { faceDistance(vec, $0.vector) < faceDistance(vec, $1.vector) }),
                   faceDistance(vec, match.vector) <= Float(faceThreshold) {
                    people.insert(match.id)
                } else {
                    reps.append(Person(id: nextPersonID, cover: id, vector: vec))
                    people.insert(nextPersonID)
                    nextPersonID += 1
                }
            }

            work[id] = PhotoVision(subjects: Array(vt.subjects.prefix(5).map { $0.label }),
                                   text: vt.text, people: Array(people))
            processed += 1
            if processed % 200 == 0 {                // batch UI updates + checkpoints
                visionIndex = work
                personReps = reps
                indexedCount = work.count
                recomputeSubjectBlurred()
                recomputeLibraryBlurred()
                // Encode + write off the main thread — the dict is large.
                let snapIdx = work, snapPeople = reps
                Task.detached(priority: .background) {
                    Self.saveVisionIndex(snapIdx)
                    Self.savePeople(snapPeople)
                }
            }
        }
        visionIndex = work
        personReps = reps
        indexedCount = work.count
        recomputeSubjectBlurred()
        recomputeLibraryBlurred()
        let finalIdx = work, finalPeople = reps
        Task.detached(priority: .background) {
            Self.saveVisionIndex(finalIdx)
            Self.savePeople(finalPeople)
        }
        indexing = false
    }

    /// People facets — each clustered person + how many photos they're in, most
    /// photographed first. Singletons (a face seen once) are dropped as noise.
    var personFacets: [(person: Person, count: Int)] {
        var counts: [Int: Int] = [:]
        for vision in visionIndex.values { for pid in vision.people { counts[pid, default: 0] += 1 } }
        return personReps
            .compactMap { rep in (counts[rep.id] ?? 0) >= 2 ? (rep, counts[rep.id]!) : nil }
            .sorted { $0.1 > $1.1 }
    }

    /// The photos a person appears in, newest first.
    func assets(forPerson id: Int) -> [String] {
        allPhotoIDs.filter { visionIndex[$0]?.people.contains(id) ?? false }
    }

    func personName(_ id: Int) -> String? { personReps.first { $0.id == id }?.name }

    /// Name a person — so they can be used in Libraries (Family = these people).
    func renamePerson(_ id: Int, to name: String) {
        guard let i = personReps.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        personReps[i].name = trimmed.isEmpty ? nil : trimmed
        Self.savePeople(personReps)
    }

    /// How many photos still need a Vision pass.
    var unindexedCount: Int { max(0, allPhotoIDs.count - visionIndex.count) }

    /// Subject facets — label + how many photos carry it, most common first.
    var subjectFacets: [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for vision in visionIndex.values {
            for label in Set(vision.subjects) { counts[label, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(50).map { ($0.key, $0.value) }
    }

    /// The photos Vision tagged with a subject, newest first.
    func assets(forSubject label: String) -> [String] {
        allPhotoIDs.filter { (visionIndex[$0]?.subjects ?? []).contains(label) }
    }

    // ─── Find (the whole point: locate a photo at breakneck speed) ───────────

    /// Search across Vision subjects + tag/album titles. Multiple words AND
    /// together (intersection) — "beach trailer" finds photos of both. Results
    /// come back in library order (newest first).
    func search(_ query: String) -> [String] {
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return allPhotoIDs }

        var perTerm: [Set<String>] = []
        for term in terms {
            var matches = Set<String>()
            for (assetID, vision) in visionIndex {
                // Match a depicted subject OR text ON the photo (the actionable
                // evidence — a number, a name, a sign, a receipt).
                if vision.subjects.contains(where: { $0.lowercased().contains(term) })
                    || vision.text.contains(where: { $0.lowercased().contains(term) }) {
                    matches.insert(assetID)
                }
            }
            for gallery in galleries where gallery.title.lowercased().contains(term) {
                matches.formUnion(gallery.assetIDs)
            }
            perTerm.append(matches)
        }
        guard var acc = perTerm.first else { return [] }
        for set in perTerm.dropFirst() { acc.formIntersection(set) }
        return allPhotoIDs.filter { acc.contains($0) }
    }

    /// Pivot: every photo from the same calendar day (drill from one photo).
    func assets(onDay date: Date) -> [String] {
        let cal = Calendar.current
        return allPhotoIDs.filter {
            (assetMeta[$0]?.date).map { cal.isDate($0, inSameDayAs: date) } ?? false
        }
    }

    /// The subjects Vision found for one photo — the pivots offered on it.
    func subjects(for assetID: String) -> [String] { visionIndex[assetID]?.subjects ?? [] }

    /// A subject's "closest associates" — the subjects that most often appear in
    /// the same photos. ("Vehicle" → Wheel, Road, Trailer.) Drives the drill-down.
    func associates(for label: String, limit: Int = 10) -> [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for vision in visionIndex.values where vision.subjects.contains(label) {
            for other in Set(vision.subjects) where other != label {
                counts[other, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// How many photos carry this subject.
    func count(forSubject label: String) -> Int {
        visionIndex.values.reduce(0) { $0 + ($1.subjects.contains(label) ? 1 : 0) }
    }

    // ─── Libraries (curated collections) ─────────────────────────────────────

    /// The photos in a library — union of its people's and subjects' photos.
    func assets(inLibrary library: CuratedLibrary) -> [String] {
        let people = Set(library.personIDs), subjects = Set(library.subjects)
        return allPhotoIDs.filter { id in
            guard let v = visionIndex[id] else { return false }
            return !Set(v.people).isDisjoint(with: people)
                || !Set(v.subjects).isDisjoint(with: subjects)
        }
    }

    @discardableResult
    func createLibrary(name: String) -> UUID {
        let lib = CuratedLibrary(id: UUID(), name: name, personIDs: [], subjects: [])
        libraries.append(lib)
        saveLibraries()
        return lib.id
    }

    func renameLibrary(_ id: UUID, to name: String) {
        guard let i = libraries.firstIndex(where: { $0.id == id }) else { return }
        libraries[i].name = name
        saveLibraries()
    }

    func deleteLibrary(_ id: UUID) {
        libraries.removeAll { $0.id == id }
        blurredLibraryIDs.remove(id)
        saveLibraries()
        recomputeLibraryBlurred()
    }

    func setMember(_ id: UUID, person: Int, _ include: Bool) {
        guard let i = libraries.firstIndex(where: { $0.id == id }) else { return }
        if include { if !libraries[i].personIDs.contains(person) { libraries[i].personIDs.append(person) } }
        else { libraries[i].personIDs.removeAll { $0 == person } }
        saveLibraries(); recomputeLibraryBlurred()
    }

    func setMember(_ id: UUID, subject: String, _ include: Bool) {
        guard let i = libraries.firstIndex(where: { $0.id == id }) else { return }
        if include { if !libraries[i].subjects.contains(subject) { libraries[i].subjects.append(subject) } }
        else { libraries[i].subjects.removeAll { $0 == subject } }
        saveLibraries(); recomputeLibraryBlurred()
    }

    func isLibraryBlurred(_ id: UUID) -> Bool { blurredLibraryIDs.contains(id) }

    func setLibraryBlur(_ id: UUID, _ on: Bool) {
        if on { blurredLibraryIDs.insert(id) } else { blurredLibraryIDs.remove(id) }
        defaults.set(blurredLibraryIDs.map(\.uuidString), forKey: Key.blurredLibraries)
        recomputeLibraryBlurred()
    }

    private func recomputeLibraryBlurred() {
        var ids = Set<String>()
        for lib in libraries where blurredLibraryIDs.contains(lib.id) {
            ids.formUnion(assets(inLibrary: lib))
        }
        libraryBlurredIDs = ids
    }

    private func saveLibraries() { Self.saveLibraries(libraries) }

    func isSubjectBlurred(_ label: String) -> Bool { blurredSubjects.contains(label) }

    /// "Blur anything automotive" — flip a subject; every photo Vision tagged
    /// with it blurs, and new photos blur as they're indexed.
    func setSubjectBlur(_ label: String, _ on: Bool) {
        if on { blurredSubjects.insert(label) } else { blurredSubjects.remove(label) }
        defaults.set(Array(blurredSubjects), forKey: Key.blurredSubjects)
        recomputeSubjectBlurred()
    }

    private func recomputeSubjectBlurred() {
        guard !blurredSubjects.isEmpty else { subjectBlurredIDs = []; return }
        var ids = Set<String>()
        for (assetID, vision) in visionIndex where !Set(vision.subjects).isDisjoint(with: blurredSubjects) {
            ids.insert(assetID)
        }
        subjectBlurredIDs = ids
    }

    // ── Subject-index persistence (JSON file in Application Support) ──
    nonisolated private static var indexURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("subject-index.json")
    }
    nonisolated static func loadVisionIndex() -> [String: PhotoVision] {
        guard let data = try? Data(contentsOf: indexURL),
              let dict = try? JSONDecoder().decode([String: PhotoVision].self, from: data)
        else { return [:] }
        return dict
    }
    nonisolated static func saveVisionIndex(_ index: [String: PhotoVision]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    nonisolated private static var peopleURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("people.json")
    }
    nonisolated static func loadPeople() -> [Person] {
        guard let data = try? Data(contentsOf: peopleURL),
              let people = try? JSONDecoder().decode([Person].self, from: data) else { return [] }
        return people
    }
    nonisolated static func savePeople(_ people: [Person]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(people) {
            try? data.write(to: peopleURL, options: .atomic)
        }
    }

    nonisolated private static var photoIDsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photo-ids.json")
    }
    nonisolated static func loadPhotoIDs() -> [String] {
        guard let data = try? Data(contentsOf: photoIDsURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
    nonisolated static func savePhotoIDs(_ ids: [String]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ids) {
            try? data.write(to: photoIDsURL, options: .atomic)
        }
    }

    nonisolated private static var librariesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("libraries.json")
    }
    nonisolated static func loadLibraries() -> [CuratedLibrary] {
        guard let data = try? Data(contentsOf: librariesURL),
              let libs = try? JSONDecoder().decode([CuratedLibrary].self, from: data) else { return [] }
        return libs
    }
    nonisolated static func saveLibraries(_ libs: [CuratedLibrary]) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(libs) {
            try? data.write(to: librariesURL, options: .atomic)
        }
    }

    // ─── Limited-library access (SDK-max, not worked around) ─────────────────

    /// Present Apple's own "select more photos" sheet. The change observer
    /// already fires a rescan when the selection changes, so newly-granted
    /// photos appear without any extra plumbing.
    func presentLimitedPicker() {
        guard let presenter = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    }

    /// Top-most view controller in the active foreground scene — the standard
    /// way to present a UIKit-hosted picker from SwiftUI.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// How aggressively the Vision index runs.
enum IndexIntensity: String, CaseIterable {
    case off, gentle, fast

    var label: String {
        switch self {
        case .off: return "Off"
        case .gentle: return "Gentle"
        case .fast: return "Fast"
        }
    }
    /// Breath between photos, in ms — the throttle.
    var pauseMs: UInt64 {
        switch self {
        case .off: return 0
        case .gentle: return 120
        case .fast: return 15
        }
    }
}

/// The eye's three states. Reveal = edit/curate (see everything); Blur = flagged
/// photos softened; Hidden = flagged photos removed from the feed.
enum ViewMode: String, CaseIterable {
    case reveal, blur, hide

    var label: String {
        switch self {
        case .reveal: return "Reveal"
        case .blur:   return "Blurred"
        case .hide:   return "Hidden"
        }
    }
    var icon: String {
        switch self {
        case .reveal: return "eye"
        case .blur:   return "eye.slash"
        case .hide:   return "eye.slash.circle.fill"
        }
    }
}

/// Cheap per-asset facts captured at scan time, for stacking.
struct AssetMeta {
    let date: Date?
    let burstID: String?
}

/// A curated library — a named collection composed from tags (people + subjects).
/// Derived, switchable, blur-able; never touches the chronological archive.
struct CuratedLibrary: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var personIDs: [Int]
    var subjects: [String]
}

/// The scan's product, carried back from the background task to the main actor.
struct ScanResult {
    let allPhotoIDs: [String]
    let assetMeta: [String: AssetMeta]
    let galleries: [Gallery]
    let userAlbums: Int
    let smartAlbums: Int
}

/// One scan's tally — the pulse surfaced in Settings and the console.
struct ScanSummary {
    let galleries: Int
    let userAlbums: Int
    let smartAlbums: Int
    let photos: Int
}

/// Tiny NSObject shim — PHPhotoLibraryChangeObserver calls arrive on a
/// background queue; forward a poke and let the engine hop to the main actor.
private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}
