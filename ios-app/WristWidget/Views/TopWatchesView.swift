import AppIntents
import SwiftUI
import WidgetKit
import WristCore
import WristKit

/// Interactive widget content.
///
/// Design rule: the current-watch block is a plain view, never a button, so
/// there is always an area that opens the app. iOS can replace the app icon
/// with this widget in place, at which point the widget may be the app's only
/// presence on the Home Screen. Only the capsule chips run `LogWearIntent`.
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
            // Any tap outside a chip opens the picker.
            .widgetURL(WristConstants.openURL)
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
        } else {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
    }

    // MARK: - Derived data

    private var current: WearWatch? {
        entry.state.watches.first { $0.id == entry.state.current?.watchId }
    }

    /// Most-worn three, including the current watch: on a new day re-logging
    /// it is a real wear, and inside the debounce window the tap is a no-op.
    private var chips: [WearWatch] {
        Ranking.topWatches(entry.state.watches, limit: 3)
    }

    private var labels: [String] {
        Ranking.shortLabels(for: chips, maxLength: 16)
    }

    // MARK: - Small

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            currentCard
            Spacer(minLength: 0)
            if let current {
                chip(for: current, label: "Log again", systemImage: "arrow.counterclockwise")
            } else if let first = chips.first {
                chip(for: first, label: Ranking.shortLabel(for: first, maxLength: 14), systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Current watch (plain; tapping opens the app)

    @ViewBuilder
    private var currentCard: some View {
        if let current {
            VStack(alignment: .leading, spacing: 3) {
                WidgetThumbnail(data: entry.thumbnails[current.id], brand: current.brand, size: 36)
                Text("WEARING")
                    .font(.caption2)
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(current.brand)
                    .font(.headline)
                    .lineLimit(1)
                Text(current.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Nothing logged yet")
                    .font(.footnote.weight(.semibold))
                Text("Tap to open Wrist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Medium

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 12) {
            currentCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            chipColumn
                .frame(maxWidth: .infinity, alignment: .top)
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
                    chip(
                        for: watch,
                        label: label,
                        systemImage: watch.id == current?.id ? "checkmark" : nil,
                        showThumbnail: true
                    )
                }
            }
        }
    }

    // MARK: - Chip (the only interactive element)

    private func chip(for watch: WearWatch, label: String, systemImage: String? = nil, showThumbnail: Bool = false) -> some View {
        Button(intent: LogWearIntent(watchID: watch.id)) {
            HStack(spacing: 8) {
                if showThumbnail {
                    WidgetThumbnail(data: entry.thumbnails[watch.id], brand: watch.brand, size: 22)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if showThumbnail, let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
