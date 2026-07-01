// IndexingActivity.swift — shared Live Activity attributes (app + widget target).
//
// Drives the Dynamic Island / lock-screen progress while Vision reads the
// library. Compiled into BOTH the app and the widget extension.

import ActivityKit

struct IndexingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var done: Int
        var total: Int
    }
}
