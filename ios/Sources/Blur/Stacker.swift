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
    var count: Int { memberIDs.count }
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
