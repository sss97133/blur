// GalleryFocusView.swift — one gallery, the curate + show surface.
//
// This is where "Blur" earns its name. Two modes:
//
//   • Curate (default): tap a photo to open its details (the tag inspector);
//     touch and hold to hide it (it blurs). Hiding marks the ones you wouldn't
//     want to flash past when showing someone.
//   • Show: a single toggle. Hidden photos disappear entirely, so you can hand
//     someone your phone and flip through this exact group with confidence —
//     no frantic scrolling, no accidental reveal.
//
// All state is local (LibraryEngine.hiddenAssetIDs). Nothing leaves the device.

import SwiftUI

struct GalleryFocusView: View {
    let gallery: Gallery
    @EnvironmentObject private var library: LibraryEngine
    @State private var showMode = false
    @State private var inspecting: InspectSelection?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    /// In Show mode, hidden photos are removed from the grid entirely.
    private var visibleAssetIDs: [String] {
        showMode ? gallery.assetIDs.filter { !library.isHidden($0) } : gallery.assetIDs
    }

    /// Whether anything in this gallery is already hidden — drives the
    /// one-time, self-dismissing hint below.
    private var hasHidden: Bool {
        gallery.assetIDs.contains { library.isHidden($0) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(visibleAssetIDs, id: \.self) { assetID in
                    Button {
                        inspecting = InspectSelection(id: assetID)
                    } label: {
                        AssetThumbnail(
                            assetIdentifier: assetID,
                            side: 110,
                            cornerRadius: 4,
                            blurred: library.isHidden(assetID)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            library.toggleHidden(assetID)
                        } label: {
                            Label(library.isHidden(assetID) ? "Show" : "Hide",
                                  systemImage: library.isHidden(assetID) ? "eye" : "eye.slash")
                        }
                    }
                    .accessibilityLabel(library.isHidden(assetID) ? "Photo, hidden" : "Photo")
                    .accessibilityHint("Opens details. Touch and hold to hide.")
                }
            }
            .padding(4)
        }
        .navigationTitle(gallery.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showMode) {
                    Label("Show mode", systemImage: showMode ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // One-time, self-dismissing: gone the moment the gesture is used.
            if !showMode && !hasHidden {
                Text("Tap a photo for its details · touch and hold to hide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .sheet(item: $inspecting) { selection in
            PhotoInspectorView(assetID: selection.id)
        }
    }
}

/// Identifiable wrapper so `.sheet(item:)` can present the inspector for a
/// specific photo.
private struct InspectSelection: Identifiable {
    let id: String
}
