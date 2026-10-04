import Foundation
import WristCore

func makeWatch(
    id: String,
    brand: String = "Brand",
    model: String = "Model",
    wearCount: Int = 0,
    lastWornAt: String? = nil
) -> WearWatch {
    WearWatch(
        id: id,
        brand: brand,
        model: model,
        imageUrl: nil,
        thumbnailUrl: nil,
        postUrl: "https://bsky.app/profile/x/post/\(id)",
        wearCount: wearCount,
        lastWornAt: lastWornAt,
        postCount: 1
    )
}

func makeState(
    watches: [WearWatch],
    current: WearEvent? = nil,
    pendingCount: Int = 0
) -> WearStore.State {
    WearStore.State(
        watches: watches,
        current: current,
        pendingCount: pendingCount,
        lastSyncAt: nil,
        lastError: nil,
        isLoaded: true
    )
}

let testTimeZone = TimeZone(secondsFromGMT: -7 * 3600)!

let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = testTimeZone
    return calendar
}()

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var components = DateComponents()
    components.year = y
    components.month = m
    components.day = d
    components.hour = h
    components.minute = min
    components.second = 0
    components.timeZone = testTimeZone
    return testCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
}

let W1 = makeWatch(id: "w1", brand: "Citizen", model: "Eco Drive", wearCount: 5)
let W2 = makeWatch(id: "w2", brand: "Kurono", model: "Malachite", wearCount: 4)
let W3 = makeWatch(id: "w3", brand: "Skagen", model: "Quartz", wearCount: 3)
let W4 = makeWatch(id: "w4", brand: "Seiko", model: "SKX007", wearCount: 2)
let W5 = makeWatch(id: "w5", brand: "Casio", model: "F-91W", wearCount: 1)
let fiveWatches = [W1, W2, W3, W4, W5]
