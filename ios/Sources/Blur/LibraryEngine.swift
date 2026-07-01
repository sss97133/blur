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

    /// Global "Show mode" (premium): when on, hidden photos vanish everywhere so
    /// the phone can be handed over safely; off, they render blurred.
    @Published var showMode = false

    /// Asset localIdentifiers the user has marked hidden (blurred). Rendered
    /// with a heavy blur and hidden entirely in "Show mode".
    @Published private(set) var hiddenAssetIDs: Set<String> = []

    // ─── Persistence (UserDefaults; required-reason CA92.1) ──────────────────
    private let defaults = UserDefaults.standard
    private enum Key {
        static let hidden = "hiddenAssetIDs"
        static let lastScan = "lastScanDate"
    }

    private var changeObserver: LibraryObserver?
    private var started = false

    private init() {
        if let saved = defaults.stringArray(forKey: Key.hidden) {
            hiddenAssetIDs = Set(saved)
        }
        lastScanDate = defaults.object(forKey: Key.lastScan) as? Date
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
            let ids = Self.userLibraryIDs()
            let userAlbums = Self.collectGalleries(in: .album, source: .userAlbum)
            let smart = Self.smartGalleries()
            let built = (userAlbums + smart)
                .filter { $0.count > 0 }
                .sorted { lhs, rhs in
                    if lhs.source != rhs.source { return lhs.source == .userAlbum }
                    return lhs.count > rhs.count
                }
            return ScanResult(allPhotoIDs: ids, galleries: built,
                              userAlbums: userAlbums.count, smartAlbums: smart.count)
        }.value

        // Publish on the main actor (we're back on it here).
        allPhotoIDs = result.allPhotoIDs
        galleries = result.galleries

        let photos = result.galleries.reduce(0) { $0 + $1.count }
        lastScan = ScanSummary(galleries: result.galleries.count, userAlbums: result.userAlbums,
                               smartAlbums: result.smartAlbums, photos: photos)
        if result.galleries.isEmpty {
            NSLog("Blur scan: 0 galleries — library empty or PhotoKit returned nothing")
        } else {
            NSLog("Blur scan: %d galleries (%d user, %d smart), %d photos",
                  result.galleries.count, result.userAlbums, result.smartAlbums, photos)
        }
        return true
    }

    /// User-created albums. `nonisolated` so the scan runs off the main thread.
    nonisolated private static func collectGalleries(in type: PHAssetCollectionType, source: GallerySource) -> [Gallery] {
        let collections = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
        var out: [Gallery] = []
        collections.enumerateObjects { collection, _, _ in
            if let gallery = Self.gallery(from: collection, source: source) { out.append(gallery) }
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
    nonisolated private static func userLibraryIDs() -> [String] {
        let cols = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
        guard let lib = cols.firstObject else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: lib, options: options)
        var ids: [String] = []
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
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

    func isHidden(_ assetID: String) -> Bool { hiddenAssetIDs.contains(assetID) }

    func toggleHidden(_ assetID: String) {
        if hiddenAssetIDs.contains(assetID) {
            hiddenAssetIDs.remove(assetID)
        } else {
            hiddenAssetIDs.insert(assetID)
        }
        defaults.set(Array(hiddenAssetIDs), forKey: Key.hidden)
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

/// The scan's product, carried back from the background task to the main actor.
struct ScanResult {
    let allPhotoIDs: [String]
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
