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
    /// Whether blasts collapse into stacks here. The stack sub-grid passes false
    /// so a stack's members show expanded.
    var stacked: Bool = true
    @EnvironmentObject private var library: LibraryEngine
    @State private var viewer: ViewerContext?
    @State private var openStack: PhotoStack?
    @State private var pivot: Pivot?
    /// Cached grid units — recomputed only when the library/settings change (see
    /// unitSignature), NOT on every render. Clustering the whole library on each
    /// pinch frame would freeze a large library.
    @State private var cachedUnits: [GridUnit]?

    // Select mode
    @State private var selecting = false
    @State private var selection = Set<String>()

    // Pinch-to-zoom column count (the pinch itself is handled inside FastPhotoGrid)
    @State private var columns = 3
    private let spacing: CGFloat = 1.5

    /// In Hidden mode, flagged photos drop out of the feed entirely.
    private var visibleAssetIDs: [String] {
        library.viewMode == .hide ? assetIDs.filter { !library.isHidden($0) } : assetIDs
    }

    /// Units to render — served from cache; computed once per real change.
    private var displayUnits: [GridUnit] { cachedUnits ?? computeUnits() }

    private func computeUnits() -> [GridUnit] {
        guard stacked && library.stacksEnabled else { return visibleAssetIDs.map { .single($0) } }
        return Stacker.units(ids: visibleAssetIDs, meta: library.assetMeta,
                             gap: library.stackGapSeconds, minCount: library.stackMinCount)
    }

    /// A cheap fingerprint of everything `computeUnits` depends on — but NOT
    /// pinch/scroll/selection, so those don't trigger a recompute.
    private var unitSignature: Int {
        var h = Hasher()
        h.combine(assetIDs.count)
        h.combine(assetIDs.first)   // catch same-count-different-content (search results)
        h.combine(assetIDs.last)
        h.combine(stacked)
        h.combine(library.viewMode)
        h.combine(library.stacksEnabled)
        h.combine(library.stackGapSeconds)
        h.combine(library.stackMinCount)
        h.combine(library.assetMeta.count)
        h.combine(library.hiddenAssetIDs.count)
        h.combine(library.ruleBlurredIDs.count)
        h.combine(library.subjectBlurredIDs.count)
        return h.finalize()
    }

    private var hasHidden: Bool { assetIDs.contains { library.isHidden($0) } }

    var body: some View {
        FastPhotoGrid(
            units: displayUnits,
            columns: $columns,
            spacing: spacing,
            reveal: library.viewMode == .reveal,
            isBlurred: { library.isHidden($0) },
            selecting: selecting,
            isSelected: { unit in !unit.assetIDs.isEmpty && unit.assetIDs.allSatisfy { selection.contains($0) } },
            onTap: { handleTap($0) },
            onBlur: { unit in
                let anyHidden = unit.assetIDs.contains { library.isHidden($0) }
                library.setHidden(unit.assetIDs, !anyHidden)
                Haptics.impact(.light)
            },
            onSelectFromMenu: { unit in
                withAnimation { selecting = true }
                selection = Set(unit.assetIDs)
                Haptics.impact()
            }
        )
        .ignoresSafeArea(edges: .bottom)
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
        .fullScreenCover(item: $viewer) { context in
            PhotoViewer(assetIDs: visibleAssetIDs, index: context.index)
        }
        .navigationDestination(item: $openStack) { stack in
            PhotoGrid(title: "\(stack.count) photos", assetIDs: stack.memberIDs, stacked: false)
        }
        .navigationDestination(item: $pivot) { pivot in
            switch pivot {
            case .subject(let label):
                PhotoGrid(title: label, assetIDs: library.assets(forSubject: label))
            case .day(let date):
                PhotoGrid(title: date.formatted(date: .abbreviated, time: .omitted),
                          assetIDs: library.assets(onDay: date))
            }
        }
        .onAppear { if cachedUnits == nil { cachedUnits = computeUnits() } }
        .onChange(of: unitSignature) { _, _ in cachedUnits = computeUnits() }
    }

    /// Tap from the fast grid: in Select mode toggle the unit's selection;
    /// otherwise open a photo in the viewer or drill into a stack.
    private func handleTap(_ unit: GridUnit) {
        if selecting {
            let all = !unit.assetIDs.isEmpty && unit.assetIDs.allSatisfy { selection.contains($0) }
            if all { unit.assetIDs.forEach { selection.remove($0) } }
            else { selection.formUnion(unit.assetIDs) }
            Haptics.selection()
            return
        }
        switch unit {
        case .single(let assetID):
            viewer = ViewerContext(index: visibleAssetIDs.firstIndex(of: assetID) ?? 0)
        case .stack(let stack):
            openStack = stack
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

/// Identifiable wrapper carrying the tapped photo's index into the viewer.
private struct ViewerContext: Identifiable {
    let id = UUID()
    let index: Int
}

/// A drill-down pivot from one photo to a related set — the find grammar.
enum Pivot: Hashable, Identifiable {
    case subject(String)
    case day(Date)
    var id: String {
        switch self {
        case .subject(let label): return "subject:\(label)"
        case .day(let date):      return "day:\(date.timeIntervalSince1970)"
        }
    }
}
