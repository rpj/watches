import SwiftUI
import WristCore

/// One tappable line in the picker list.
struct WatchRow: View {
    let watch: WearWatch
    let isCurrent: Bool

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
            Text("\(watch.wearCount)×")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
