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

    private var typeTags: [Gallery] { library.galleries.filter { $0.source == .smartAlbum } }
    private var albumTags: [Gallery] { library.galleries.filter { $0.source == .userAlbum } }

    var body: some View {
        NavigationStack {
            Group {
                if library.authorizationDenied {
                    ContentUnavailableView("Photos access is off", systemImage: "lock",
                        description: Text("Enable Photos for Blur in Settings to see your tags."))
                } else if library.galleries.isEmpty {
                    if library.didCompleteInitialScan {
                        ContentUnavailableView("No tags yet", systemImage: "tag",
                            description: Text("Types and albums from your library appear here."))
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
            .refreshable { await library.rescan() }
        }
    }

    private var list: some View {
        List {
            if !typeTags.isEmpty {
                Section {
                    ForEach(typeTags) { tagRow($0) }
                } header: {
                    Text("Types")
                } footer: {
                    Text("Blur a tag (swipe or touch and hold) to auto-blur everything with it — new photos included. Flip the eye to Hidden to drop them from the feed entirely.")
                }
            }
            if !albumTags.isEmpty {
                Section("Albums") { ForEach(albumTags) { tagRow($0) } }
            }
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
