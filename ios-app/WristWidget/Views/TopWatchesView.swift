import AppIntents
import SwiftUI
import WidgetKit
import WristCore
import WristKit

struct TopWatchesView: View {
    let entry: WearEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .padding(12)
            .overlay(alignment: .topTrailing) {
                if entry.state.pendingCount > 0 {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !entry.state.isLoaded && !entry.isPlaceholder {
            VStack(spacing: 6) {
                Image(systemName: "clock")
                Text("Open Wrist to connect")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(WristConstants.openURL)
        } else {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                currentBlock
            }
        }
    }

    // MARK: - Derived data

    private var current: WearWatch? {
        entry.state.watches.first { $0.id == entry.state.current?.watchId }
    }

    private var chips: [WearWatch] {
        Ranking.topWatches(entry.state.watches, limit: 3, excluding: current?.id)
    }

    private var labels: [String] {
        Ranking.shortLabels(for: chips, maxLength: 16)
    }

    // MARK: - Current watch

    @ViewBuilder
    private var currentBlock: some View {
        if let current {
            watchButton(current, caption: "WEARING")
        } else if let first = chips.first {
            watchButton(first, caption: "TAP TO LOG")
        } else {
            Text("Nothing logged yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func watchButton(_ watch: WearWatch, caption: String) -> some View {
        Button(intent: LogWearIntent(watchID: watch.id)) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetThumbnail(data: entry.thumbnails[watch.id], brand: watch.brand, size: 44)
                Spacer(minLength: 0)
                Text(caption)
                    .font(.caption2)
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(watch.brand)
                    .font(.headline)
                    .lineLimit(1)
                Text(watch.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Medium

    private var mediumBody: some View {
        GeometryReader { proxy in
            HStack(spacing: 12) {
                currentBlock
                    .frame(width: proxy.size.width * 0.45)
                chipColumn
            }
        }
    }

    @ViewBuilder
    private var chipColumn: some View {
        if chips.isEmpty {
            Text("Log a watch in Wrist first")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                ForEach(Array(zip(chips, labels)), id: \.0.id) { watch, label in
                    Button(intent: LogWearIntent(watchID: watch.id)) {
                        HStack(spacing: 8) {
                            WidgetThumbnail(data: entry.thumbnails[watch.id], brand: watch.brand, size: 22)
                            Text(label)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
