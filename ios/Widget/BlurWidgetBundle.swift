// BlurWidgetBundle.swift — the widget extension.
//
// Hosts the Live Activity that shows Vision-indexing progress in the Dynamic
// Island and on the lock screen while Blur reads your library in the background.

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct BlurWidgetBundle: WidgetBundle {
    var body: some Widget {
        IndexingLiveActivity()
    }
}

struct IndexingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IndexingAttributes.self) { context in
            // Lock screen / banner
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading your photos").font(.subheadline).bold()
                    ProgressView(value: fraction(context.state))
                }
                Text("\(context.state.done)/\(context.state.total)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Blur", systemImage: "sparkles").font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.done)/\(context.state.total)")
                        .font(.caption).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: fraction(context.state))
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text("\(percent(context.state))%").font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }

    private func fraction(_ s: IndexingAttributes.ContentState) -> Double {
        s.total > 0 ? min(1, Double(s.done) / Double(s.total)) : 0
    }
    private func percent(_ s: IndexingAttributes.ContentState) -> Int {
        Int(fraction(s) * 100)
    }
}
