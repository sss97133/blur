// PhotoGrid.swift — a grid of photos, reused by the Library tab and by albums.
//
// The single grid surface in Blur (nuke rule: no parallel display systems). It
// renders a full-bleed grid of the given assets — edge-to-edge, square tiles,
// hairline gaps — exactly like the Photos app. Tap opens the tag inspector;
// touch-and-hold hides a photo; a pinch changes the column count (zoom), and the
// global Show mode removes hidden photos so the phone can be handed over safely.
//
// Designed to live INSIDE a NavigationStack the caller provides (the Library
// tab wraps it; the Albums tab pushes it) — it never creates its own.

import SwiftUI

struct PhotoGrid: View {
    let title: String
    let assetIDs: [String]
    @EnvironmentObject private var library: LibraryEngine
    @State private var inspecting: InspectSelection?

    // ── Pinch-to-zoom column count, like Photos ──
    // Photos lets you pinch the grid denser or sparser. We step the column count
    // and show a live scale during the pinch so the tiles track your fingers,
    // then snap to the new density on release.
    @State private var columns = 3
    @GestureState private var pinch: CGFloat = 1
    private let minColumns = 1
    private let maxColumns = 6
    private let spacing: CGFloat = 1.5

    /// In Show mode, hidden photos are removed entirely.
    private var visibleAssetIDs: [String] {
        library.showMode ? assetIDs.filter { !library.isHidden($0) } : assetIDs
    }

    /// Drives the one-time, self-dismissing hint.
    private var hasHidden: Bool {
        assetIDs.contains { library.isHidden($0) }
    }

    var body: some View {
        GeometryReader { geo in
            let tile = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let grid = Array(repeating: GridItem(.fixed(tile), spacing: spacing), count: columns)

            ScrollView {
                LazyVGrid(columns: grid, spacing: spacing) {
                    ForEach(visibleAssetIDs, id: \.self) { assetID in
                        Button {
                            inspecting = InspectSelection(id: assetID)
                        } label: {
                            AssetThumbnail(
                                assetIdentifier: assetID,
                                side: tile,
                                cornerRadius: 0,
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
                // Live pinch feedback: scale the whole grid toward the current
                // magnification, clamped so it never runs away, then snap.
                .scaleEffect(min(max(pinch, 0.55), 1.8), anchor: .center)
            }
            .scrollDisabled(pinch != 1)   // don't fight the pinch with a scroll
            // simultaneousGesture: a plain .gesture loses to the ScrollView's own
            // pan recognizer, so the pinch never fired on device. This lets both
            // recognize, so the two-finger pinch is seen.
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        let next: Int
                        if value.magnification > 1.15 {        // spread → zoom in → fewer, bigger
                            next = max(minColumns, columns - 1)
                        } else if value.magnification < 0.87 { // pinch → zoom out → more, smaller
                            next = min(maxColumns, columns + 1)
                        } else {
                            next = columns
                        }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            columns = next
                        }
                    }
            )
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
