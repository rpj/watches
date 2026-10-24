import SwiftUI
import UIKit
import WristCore

enum HoldToLog {
    /// How long the finger must stay down before a wear is logged.
    static let duration: TimeInterval = 0.65
    /// Finger drift allowed before the hold is cancelled (lets the list scroll).
    static let maximumDistance: CGFloat = 24
}

/// A picker row that logs on press-and-hold instead of tap, so a stray touch
/// while scrolling never records a wear. While the finger is down a bronze
/// ring fills in the trailing slot; releasing early cancels with no effect.
struct HoldToLogRow: View {
    let watch: WearWatch
    let isCurrent: Bool
    let onLog: () -> Void

    @State private var pressing = false
    @State private var progress: CGFloat = 0

    var body: some View {
        WatchRow(watch: watch, isCurrent: isCurrent, pressing: pressing, holdProgress: progress)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: HoldToLog.duration, maximumDistance: HoldToLog.maximumDistance) {
                complete()
            } onPressingChanged: { isPressing in
                pressing = isPressing
                if isPressing {
                    progress = 0
                    withAnimation(.linear(duration: HoldToLog.duration)) {
                        progress = 1
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        progress = 0
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Hold to log")
            .accessibilityAction(named: "Log") {
                complete()
            }
    }

    private func complete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        pressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            progress = 0
        }
        onLog()
    }
}
