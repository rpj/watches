import SwiftUI
import WristCore

/// One line in the picker list. Purely presentational; `HoldToLogRow` owns
/// the gesture and feeds `pressing` / `holdProgress` for the trailing ring.
struct WatchRow: View {
    let watch: WearWatch
    let isCurrent: Bool
    var pressing: Bool = false
    var holdProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            WatchThumbnail(watch, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(watch.brand).font(.headline)
                Text(watch.model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            trailingSlot
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// The wear count, replaced by a filling ring while the row is held.
    private var trailingSlot: some View {
        ZStack {
            Text("\(watch.wearCount)×")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .opacity(pressing ? 0 : 1)
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            .opacity(pressing ? 1 : 0)
        }
        .frame(minWidth: 36, alignment: .trailing)
        .animation(.easeInOut(duration: 0.12), value: pressing)
    }
}
