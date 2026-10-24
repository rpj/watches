import SwiftUI
import WristCore

/// Header card: what is on the wrist right now.
struct CurrentWatchCard: View {
    let watch: WearWatch?
    let since: String?
    let pendingCount: Int
    let errorText: String?
    /// The latest event is the reserved "nothing on" entry (bare wrist).
    var isNothingOn: Bool = false

    private var title: String {
        if let watch { return watch.displayName }
        return isNothingOn ? "Nothing on" : "Nothing logged yet"
    }

    private var subtitle: String {
        guard let since, let date = WearDates.parse(since) else { return "Hold a watch below to log it." }
        if Calendar.autoupdatingCurrent.isDateInToday(date) {
            return "since " + date.formatted(date: .omitted, time: .shortened)
        }
        return "since " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                WatchThumbnail(isNothingOn ? .nothing : watch, size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEARING NOW")
                        .font(.caption)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityIdentifier("picker.currentTitle")
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if pendingCount > 0 {
                Label("\(pendingCount) unsent · retrying", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .accessibilityIdentifier("picker.pendingPill")
            }
            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}
