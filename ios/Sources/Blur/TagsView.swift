// TagsView.swift — the Tags tab: the library tallied and organized by tag.
//
// This is where you SEE your tags and where the blur system lives at scale. Each
// row is a tag (an Apple smart album / type, or one of your albums) with its
// count; tap to open that group, swipe or long-press ("right click") to blur the
// whole tag — new matching photos auto-blur on the next scan.
//
// v1 is Layer 1: the factual tags Apple already computes (Screenshots, Selfies,
// Bursts, Favorites, your albums). Layer 2 — Vision subjects ("Vehicle", faces)
// — becomes another section here once the library-wide index lands.

import SwiftUI

struct TagsView: View {
    @EnvironmentObject private var library: LibraryEngine

    // Tags is the DERIVED surface — what Vision/PhotoKit read, not your manual
    // albums (those live in the Albums tab). Only Apple's type smart-albums show
    // here as facets; user albums are intentionally excluded.
    private var typeTags: [Gallery] { library.galleries.filter { $0.source == .smartAlbum } }

    var body: some View {
        NavigationStack {
            Group {
                if library.authorizationDenied {
                    ContentUnavailableView("Photos access is off", systemImage: "lock",
                        description: Text("Enable Photos for Blur in Settings to see your tags."))
                } else if library.galleries.isEmpty && library.allPhotoIDs.isEmpty {
                    if library.didCompleteInitialScan {
                        ContentUnavailableView("No tags yet", systemImage: "tag",
                            description: Text("People, subjects, and types Blur reads from your library appear here."))
                    } else {
                        ProgressView().controlSize(.large)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Tags")
            .navigationDestination(for: Gallery.self) { gallery in
                PhotoGrid(title: gallery.title, assetIDs: gallery.assetIDs)
            }
            .navigationDestination(for: SubjectRef.self) { ref in
                SubjectDetailView(label: ref.label)
            }
            .navigationDestination(for: PersonRef.self) { ref in
                PhotoGrid(title: "Person", assetIDs: library.assets(forPerson: ref.id))
            }
        }
    }

    private var list: some View {
        List {
            // Derived intelligence first — who and what — then Apple's types.
            peopleSection
            subjectsSection
            if !typeTags.isEmpty {
                Section {
                    ForEach(typeTags) { tagRow($0) }
                } header: {
                    Text("Types")
                } footer: {
                    Text("Blur a tag (swipe or touch and hold) to auto-blur everything with it — new photos included. Flip the eye to Hidden to drop them from the feed entirely.")
                }
            }
        }
    }

    // ── People (on-device face clustering) ──
    @ViewBuilder
    private var peopleSection: some View {
        if !library.personFacets.isEmpty {
            Section("People") {
                ForEach(library.personFacets, id: \.person.id) { facet in
                    NavigationLink(value: PersonRef(id: facet.person.id)) {
                        HStack(spacing: 12) {
                            AssetThumbnail(assetIdentifier: facet.person.cover, side: 36, cornerRadius: 18)
                            Text("Person")
                            Spacer(minLength: 8)
                            Text("\(facet.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // ── Subjects (Vision, Layer 2) ──
    @ViewBuilder
    private var subjectsSection: some View {
        Section {
            if library.indexing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing on device… \(library.indexedCount)/\(library.allPhotoIDs.count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(library.subjectFacets, id: \.label) { facet in
                subjectRow(facet.label, count: facet.count)
            }
            if !library.indexing && library.unindexedCount > 0 {
                Button {
                    Task(priority: .utility) { await library.indexLibrary() }
                } label: {
                    Label(library.visionIndex.isEmpty
                          ? "Read \(library.allPhotoIDs.count) photos"
                          : "Read \(library.unindexedCount) more",
                          systemImage: "sparkles")
                }
            }
        } header: {
            Text("Subjects · Vision")
        } footer: {
            Text("Vision reads each photo on device — what's in it AND the text on it (signs, numbers, receipts). Search finds both. Blur a subject to blur every photo of it.")
        }
    }

    private func subjectRow(_ label: String, count: Int) -> some View {
        let blurred = library.isSubjectBlurred(label)
        return NavigationLink(value: SubjectRef(label: label)) {
            HStack(spacing: 10) {
                Label(label, systemImage: "sparkle")
                Spacer(minLength: 8)
                if blurred {
                    Image(systemName: "eye.slash.fill").font(.caption).foregroundStyle(.indigo)
                }
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contextMenu {
            Button { library.setSubjectBlur(label, !blurred) } label: {
                Label(blurred ? "Unblur these" : "Blur these",
                      systemImage: blurred ? "eye" : "eye.slash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button { library.setSubjectBlur(label, !blurred) } label: {
                Label(blurred ? "Unblur" : "Blur", systemImage: blurred ? "eye" : "eye.slash")
            }
            .tint(.indigo)
        }
    }

    private func tagRow(_ gallery: Gallery) -> some View {
        let blurred = library.isCategoryBlurred(gallery.id)
        return NavigationLink(value: gallery) {
            HStack(spacing: 10) {
                Label(gallery.title, systemImage: Self.icon(for: gallery))
                Spacer(minLength: 8)
                if blurred {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                Text("\(gallery.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contextMenu {
            Button { library.setCategoryBlur(gallery.id, !blurred) } label: {
                Label(blurred ? "Unblur these" : "Blur these",
                      systemImage: blurred ? "eye" : "eye.slash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button { library.setCategoryBlur(gallery.id, !blurred) } label: {
                Label(blurred ? "Unblur" : "Blur", systemImage: blurred ? "eye" : "eye.slash")
            }
            .tint(.indigo)
        }
    }

    /// A natural SF Symbol for a tag row.
    static func icon(for gallery: Gallery) -> String {
        switch gallery.title.lowercased() {
        case let t where t.contains("screenshot"): return "camera.viewfinder"
        case let t where t.contains("favorite"): return "heart"
        case let t where t.contains("selfie") || t.contains("portrait"): return "person.crop.square"
        case let t where t.contains("burst"): return "square.stack.3d.down.right"
        case let t where t.contains("panorama"): return "pano"
        case let t where t.contains("recently"): return "clock"
        default: return gallery.source == .userAlbum ? "rectangle.stack" : "tag"
        }
    }
}

/// Navigation value for a Vision subject group.
struct SubjectRef: Hashable {
    let label: String
}

/// Navigation value for a clustered person.
struct PersonRef: Hashable {
    let id: Int
}
