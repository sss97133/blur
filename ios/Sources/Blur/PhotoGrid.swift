// PhotoGrid.swift — the one grid surface (Library tab + albums + tag groups).
//
// Full-bleed square tiles like Photos, pinch-to-zoom columns, and the curation
// layer: the tri-state eye (Reveal / Blur / Hidden), a Select tool for batch
// blur/reveal, and a context menu ("right click") on every tile — all with
// haptics. Lives inside a NavigationStack the caller provides.

import SwiftUI

struct PhotoGrid: View {
    let title: String
    let assetIDs: [String]
    @EnvironmentObject private var library: LibraryEngine
    @State private var inspecting: InspectSelection?

    // Select mode
    @State private var selecting = false
    @State private var selection = Set<String>()

    // Pinch-to-zoom columns
    @State private var columns = 3
    @GestureState private var pinch: CGFloat = 1
    private let minColumns = 1
    private let maxColumns = 6
    private let spacing: CGFloat = 1.5

    /// In Hidden mode, flagged photos drop out of the feed entirely.
    private var visibleAssetIDs: [String] {
        library.viewMode == .hide ? assetIDs.filter { !library.isHidden($0) } : assetIDs
    }

    private var hasHidden: Bool { assetIDs.contains { library.isHidden($0) } }

    var body: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let grid = Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: columns)

            ScrollView {
                LazyVGrid(columns: grid, spacing: spacing) {
                    ForEach(visibleAssetIDs, id: \.self) { assetID in
                        tile(assetID, side: cell)
                    }
                }
                .scaleEffect(min(max(pinch, 0.55), 1.8), anchor: .center)
            }
            .scrollDisabled(pinch != 1)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        let next: Int
                        if value.magnification > 1.15 { next = max(minColumns, columns - 1) }
                        else if value.magnification < 0.87 { next = min(maxColumns, columns + 1) }
                        else { next = columns }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { columns = next }
                    }
            )
        }
        .navigationTitle(selecting ? "\(selection.count) selected" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation { selecting.toggle() }
                    if !selecting { selection.removeAll() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("View", selection: $library.viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Label(mode.label, systemImage: mode.icon).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: library.viewMode.icon)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                selectionBar
            } else if library.viewMode != .hide && !hasHidden {
                Text("Tap a photo for details · touch and hold for actions · Select to blur many")
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

    // ── One tile ──
    private func tile(_ assetID: String, side: CGFloat) -> some View {
        let isSelected = selection.contains(assetID)
        return Button {
            if selecting {
                if isSelected { selection.remove(assetID) } else { selection.insert(assetID) }
                Haptics.selection()
            } else {
                inspecting = InspectSelection(id: assetID)
            }
        } label: {
            AssetThumbnail(
                assetIdentifier: assetID,
                side: side,
                cornerRadius: 0,
                blurred: library.viewMode != .reveal && library.isHidden(assetID)
            )
            .overlay {
                if selecting && isSelected {
                    Rectangle().stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .font(.title3)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            let hidden = library.isHidden(assetID)
            Button {
                library.toggleHidden(assetID)
                Haptics.impact(.light)
            } label: {
                Label(hidden ? "Reveal" : "Blur", systemImage: hidden ? "eye" : "eye.slash")
            }
            Button {
                withAnimation { selecting = true }
                selection = [assetID]
                Haptics.impact()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
        }
    }

    // ── Batch action bar (Select mode) ──
    private var selectionBar: some View {
        HStack {
            Button {
                library.setHidden(selection, true)
                Haptics.success()
                endSelecting()
            } label: { Label("Blur", systemImage: "eye.slash") }
                .disabled(selection.isEmpty)
            Spacer()
            Button(selection.count == visibleAssetIDs.count ? "None" : "All") {
                selection = selection.count == visibleAssetIDs.count ? [] : Set(visibleAssetIDs)
                Haptics.selection()
            }
            .font(.subheadline)
            Spacer()
            Button {
                library.setHidden(selection, false)
                Haptics.success()
                endSelecting()
            } label: { Label("Reveal", systemImage: "eye") }
                .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func endSelecting() {
        withAnimation { selecting = false }
        selection.removeAll()
    }
}

/// Identifiable wrapper so `.sheet(item:)` can present the inspector.
private struct InspectSelection: Identifiable {
    let id: String
}
