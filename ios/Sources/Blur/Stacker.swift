// Stacker.swift — collapse "blasts" of photos into stacks.
//
// A blast is a burst (Apple's own burstIdentifier) or a rapid run of shots
// within a few seconds. Stacking them turns a wall of 30 near-identical frames
// into one tile with a count — the customizable metrics (gap, min-count) live on
// LibraryEngine. Pure function, no side effects.

import Foundation

/// A collapsed run of near-simultaneous photos.
struct PhotoStack: Identifiable, Hashable {
    let id: String            // representative (cover) asset id — the run's first
    let memberIDs: [String]
    /// A human label when this stack is a TIME bucket (e.g. "March 2024") rather
    /// than a burst — drives the tile caption and the drill-in title. nil = burst.
    var label: String? = nil
    var count: Int { memberIDs.count }
}

/// How far the grid collapses time. All = every photo (bursts still stack);
/// Months / Years = one drill-in tile per calendar bucket (the year-mosaic —
/// so you jump to when instead of scrolling 500 screens).
enum TimeScale: String, CaseIterable, Hashable {
    case all, month, year
    var label: String {
        switch self {
        case .all:   return "All"
        case .month: return "Months"
        case .year:  return "Years"
        }
    }
}

/// One thing the grid renders: a lone photo, or a collapsed stack.
enum GridUnit: Identifiable, Hashable {
    case single(String)
    case stack(PhotoStack)

    var id: String {
        switch self {
        case .single(let assetID): return assetID
        case .stack(let stack):    return "stack:\(stack.id)"
        }
    }

    /// Every asset id this unit stands for (one, or the whole stack).
    var assetIDs: [String] {
        switch self {
        case .single(let assetID): return [assetID]
        case .stack(let stack):    return stack.memberIDs
        }
    }

    var isStack: Bool {
        if case .stack = self { return true } else { return false }
    }
}

enum Stacker {
    /// Cluster a newest-first id list into units. Adjacent ids collapse when they
    /// share a burst id OR fall within `gap` seconds; a run must reach `minCount`
    /// to become a stack (otherwise its photos stay singles).
    static func units(ids: [String], meta: [String: AssetMeta],
                      gap: TimeInterval, minCount: Int) -> [GridUnit] {
        guard !ids.isEmpty else { return [] }
        var units: [GridUnit] = []
        var run: [String] = []

        func flush() {
            if run.count >= minCount {
                units.append(.stack(PhotoStack(id: run[0], memberIDs: run)))
            } else {
                units.append(contentsOf: run.map { GridUnit.single($0) })
            }
            run = []
        }

        for id in ids {
            guard let last = run.last else { run = [id]; continue }
            if belongTogether(last, id, meta: meta, gap: gap) {
                run.append(id)
            } else {
                flush()
                run = [id]
            }
        }
        flush()
        return units
    }

    /// Collapse a newest-first id list into one drill-in tile per calendar bucket
    /// (month or year). The list is already newest-first, so buckets emerge in
    /// order. Undated photos fall into a trailing "Undated" bucket rather than
    /// silently disappearing.
    static func timeBuckets(ids: [String], meta: [String: AssetMeta], scale: TimeScale) -> [GridUnit] {
        guard scale != .all else { return ids.map { .single($0) } }
        let cal = Calendar.current
        var order: [Date] = []
        var byKey: [Date: [String]] = [:]
        var undated: [String] = []
        for id in ids {
            guard let d = meta[id]?.date else { undated.append(id); continue }
            let comps = scale == .year ? cal.dateComponents([.year], from: d)
                                       : cal.dateComponents([.year, .month], from: d)
            let key = cal.date(from: comps) ?? d
            if byKey[key] == nil { byKey[key] = []; order.append(key) }
            byKey[key]?.append(id)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = scale == .year ? "yyyy" : "MMMM yyyy"
        var units: [GridUnit] = order.compactMap { key in
            guard let members = byKey[key], let cover = members.first else { return nil }
            return .stack(PhotoStack(id: cover, memberIDs: members, label: fmt.string(from: key)))
        }
        if let cover = undated.first {
            units.append(.stack(PhotoStack(id: cover, memberIDs: undated, label: "Undated")))
        }
        return units
    }

    private static func belongTogether(_ a: String, _ b: String,
                                       meta: [String: AssetMeta], gap: TimeInterval) -> Bool {
        let ma = meta[a], mb = meta[b]
        if let ba = ma?.burstID, let bb = mb?.burstID, ba == bb { return true }
        if let da = ma?.date, let db = mb?.date {
            return abs(da.timeIntervalSince(db)) <= gap
        }
        return false
    }
}
