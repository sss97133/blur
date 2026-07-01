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

    // Pinch-to-zoom columns
    @State private var columns = 3
    @GestureState private var pinch: CGFloat = 1
    private let minColumns = 1
    private let maxColumns = 10
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
        GeometryReader { geo in
            let cell = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let grid = Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: columns)

            ScrollView {
                LazyVGrid(columns: grid, spacing: spacing) {
                    ForEach(displayUnits) { unit in
                        unitView(unit, side: cell)
                    }
                }
                .scaleEffect(min(max(pinch, 0.55), 1.8), anchor: .center)
            }
            .scrollDisabled(pinch != 1)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        // Map the whole pinch to a column count so ONE gesture
                        // spans the full range (spread → fewer/bigger; pinch →
                        // more/smaller), like Photos — not ±1 per gesture.
                        let target = Int((Double(columns) / value.magnification).rounded())
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            columns = min(max(target, minColumns), maxColumns)
                        }
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

    // ── One grid unit (single photo or a stack) ──
    @ViewBuilder
    private func unitView(_ unit: GridUnit, side: CGFloat) -> some View {
        switch unit {
        case .single(let assetID): tile(assetID, side: side)
        case .stack(let stack):    stackTile(stack, side: side)
        }
    }

    // ── A collapsed stack (blast) ──
    private func stackTile(_ stack: PhotoStack, side: CGFloat) -> some View {
        let allSelected = selecting && stack.memberIDs.allSatisfy { selection.contains($0) }
        let anyHidden = stack.memberIDs.contains { library.isHidden($0) }
        return Button {
            if selecting {
                if allSelected { stack.memberIDs.forEach { selection.remove($0) } }
                else { selection.formUnion(stack.memberIDs) }
                Haptics.selection()
            } else {
                openStack = stack
            }
        } label: {
            AssetThumbnail(
                assetIdentifier: stack.id,
                side: side,
                cornerRadius: 0,
                blurred: library.viewMode != .reveal && anyHidden
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("\(stack.count)")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(5)
            }
            .overlay {
                if allSelected { Rectangle().stroke(Color.accentColor, lineWidth: 3) }
            }
            .overlay(alignment: .bottomTrailing) {
                if selecting {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, allSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .font(.title3)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                library.setHidden(stack.memberIDs, !anyHidden)
                Haptics.impact(.light)
            } label: {
                Label(anyHidden ? "Reveal blast" : "Blur blast",
                      systemImage: anyHidden ? "eye" : "eye.slash")
            }
            Button {
                withAnimation { selecting = true }
                selection = Set(stack.memberIDs)
                Haptics.impact()
            } label: {
                Label("Select blast (\(stack.count))", systemImage: "square.stack.3d.up")
            }
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
                viewer = ViewerContext(index: visibleAssetIDs.firstIndex(of: assetID) ?? 0)
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
            // Pivots — drill to related photos (the "right click" find grammar).
            let subjects = library.subjects(for: assetID)
            if library.assetMeta[assetID]?.date != nil || !subjects.isEmpty {
                Divider()
                if let date = library.assetMeta[assetID]?.date {
                    Button { pivot = .day(date) } label: {
                        Label("More from this day", systemImage: "calendar")
                    }
                }
                ForEach(subjects, id: \.self) { subject in
                    Button { pivot = .subject(subject) } label: {
                        Label("More: \(subject)", systemImage: "sparkle")
                    }
                }
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
