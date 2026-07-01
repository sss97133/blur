// Haptics.swift — thin wrapper over UIFeedbackGenerator.
//
// Curation should feel physical: a tick when you select, a thump when you grab a
// blast, a success bump when a batch action lands. One tiny surface so the call
// sites stay clean.

import UIKit

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
