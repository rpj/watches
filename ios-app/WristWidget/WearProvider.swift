import Foundation
import WidgetKit
import WristCore
import WristKit

struct WearProvider: TimelineProvider {
    typealias Entry = WearEntry

    func placeholder(in context: Context) -> WearEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WearEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WearEntry>) -> Void) {
        Task {
            let entry = await load()
            // The app and the intent reload timelines after every change; this is a safety net.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
        }
    }

    // MARK: - Loading

    private func load() async -> WearEntry {
        let services = WristServices.current()
        guard let store = services.makeStore() else { return .empty }
        let state = await store.loadCached() // disk only, no network

        let currentWatch = state.watches.first { $0.id == state.current?.watchId }
        let shown = Array(
            (currentWatch.map { [$0] } ?? [])
                + Ranking.topWatches(state.watches, limit: 3, excluding: state.current?.watchId)
        )
        let thumbnails = await fetchThumbnails(for: shown)
        return WearEntry(date: Date(), state: state, thumbnails: thumbnails, isPlaceholder: false)
    }

    // MARK: - Thumbnails

    private func fetchThumbnails(for watches: [WearWatch]) async -> [String: Data] {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 4
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        let session = URLSession(configuration: configuration)

        let targets: [(id: String, url: URL)] = watches.compactMap { watch in
            guard let string = watch.thumbnailUrl, let url = URL(string: string) else { return nil }
            return (watch.id, url)
        }

        return await withTaskGroup(of: (String, Data?).self) { group in
            for target in targets {
                group.addTask {
                    guard let (data, response) = try? await session.data(from: target.url) else {
                        return (target.id, nil)
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        return (target.id, nil)
                    }
                    return (target.id, data)
                }
            }
            var result: [String: Data] = [:]
            for await (id, data) in group {
                if let data { result[id] = data }
            }
            return result
        }
    }
}
