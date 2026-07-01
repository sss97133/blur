// PhotoGrid.swift — a grid of photos, reused by the Library tab and by albums.
//
// The single grid surface in Blur (nuke rule: no parallel display systems). It
// renders a full-bleed grid of the given assets, tap opens the tag inspector
// (Photos-like), touch-and-hold hides a photo, and the global Show mode removes
// hidden photos so the phone can be handed over safely.
//
// Designed to live INSIDE a NavigationStack the caller provides (the Library
// tab wraps it; the Albums tab pushes it) — it never creates its own.

import SwiftUI

struct PhotoGrid: View {
    let title: String
    let assetIDs: [String]
    @EnvironmentObject private var library: LibraryEngine
    @State private var inspecting: InspectSelection?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    /// In Show mode, hidden photos are removed entirely.
    private var visibleAssetIDs: [String] {
        library.showMode ? assetIDs.filter { !library.isHidden($0) } : assetIDs
    }

    /// Drives the one-time, self-dismissing hint.
    private var hasHidden: Bool {
        assetIDs.contains { library.isHidden($0) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(visibleAssetIDs, id: \.self) { assetID in
                    Button {
                        inspecting = InspectSelection(id: assetID)
                    } label: {
                        AssetThumbnail(
                            assetIdentifier: assetID,
                            side: 110,
                            cornerRadius: 2,
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
            .padding(2)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $library.showMode) {
                    Label("Show mode", systemImage: library.showMode ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !library.showMode && !hasHidden {
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
