import Foundation
import WidgetKit
import WristCore

struct WearEntry: TimelineEntry {
    let date: Date
    let state: WearStore.State
    /// watchID -> image bytes
    let thumbnails: [String: Data]
    let isPlaceholder: Bool
}

// MARK: - Static entries

extension WearEntry {
    static let placeholder = WearEntry(
        date: Date(),
        state: WearStore.State(
            watches: sampleWatches,
            current: nil,
            pendingCount: 0,
            lastSyncAt: nil,
            lastError: nil,
            isLoaded: true
        ),
        thumbnails: [:],
        isPlaceholder: true
    )

    /// Not configured / nothing cached yet.
    static let empty = WearEntry(date: Date(), state: .empty, thumbnails: [:], isPlaceholder: false)

    private static let sampleWatches: [WearWatch] = [
        WearWatch(id: "sample-1", brand: "Citizen", model: "Eco Drive E110-K16750", imageUrl: nil, thumbnailUrl: nil,
                  postUrl: "", wearCount: 2, lastWornAt: nil, postCount: 2),
        WearWatch(id: "sample-2", brand: "Kurono", model: "Malachite", imageUrl: nil, thumbnailUrl: nil,
                  postUrl: "", wearCount: 1, lastWornAt: nil, postCount: 1),
        WearWatch(id: "sample-3", brand: "Skagen", model: "233LTMN Quartz", imageUrl: nil, thumbnailUrl: nil,
                  postUrl: "", wearCount: 0, lastWornAt: nil, postCount: 1),
    ]
}
