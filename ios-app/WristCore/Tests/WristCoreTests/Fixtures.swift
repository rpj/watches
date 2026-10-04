import Foundation
@testable import WristCore

enum Fixtures {
    static let watchesResponse = #"""
    {
      "watches": [
        {
          "id": "3m2uvdvq7622g",
          "brand": "Citizen",
          "model": "Eco Drive E110-K16750",
          "imageUrl": "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa",
          "thumbnailUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa",
          "postUrl": "https://bsky.app/profile/ryanswatches.com/post/3m2uvdvq7622g",
          "wearCount": 2,
          "lastWornAt": "2026-10-02T07:58:00-07:00",
          "postCount": 2
        },
        {
          "id": "3mwz3ctxxnc26",
          "brand": "Kurono",
          "model": "Malachite",
          "imageUrl": "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite",
          "thumbnailUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite",
          "postUrl": "https://bsky.app/profile/ryanswatches.com/post/3mwz3ctxxnc26",
          "wearCount": 1,
          "lastWornAt": "2026-10-03T08:05:00-07:00",
          "postCount": 1
        },
        {
          "id": "3m2uxrekinc2e",
          "brand": "Skagen",
          "model": "233LTMN Quartz",
          "imageUrl": "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone",
          "thumbnailUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone",
          "postUrl": "https://bsky.app/profile/ryanswatches.com/post/3m2uxrekinc2e",
          "wearCount": 0,
          "lastWornAt": null,
          "postCount": 1
        }
      ],
      "current": {
        "id": "22222222-2222-4222-8222-222222222222",
        "watchId": "3mwz3ctxxnc26",
        "wornAt": "2026-10-03T08:05:00-07:00",
        "source": "notification",
        "recordedAt": "2026-10-03T15:05:01.204Z"
      },
      "generatedAt": "2026-10-04T15:12:32.418Z"
    }
    """#

    /// Same payload with `"current": null`.
    static var watchesResponseWithNullCurrent: String {
        let start = watchesResponse.range(of: "\"current\": {")!.lowerBound
        let end = watchesResponse.range(of: "\"generatedAt\"")!.lowerBound
        return String(watchesResponse[..<start]) + "\"current\": null,\n  " + String(watchesResponse[end...])
    }

    static let citizen = WearWatch(
        id: "3m2uvdvq7622g", brand: "Citizen", model: "Eco Drive E110-K16750",
        imageUrl: "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa",
        thumbnailUrl: "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreicitizenaaaa",
        postUrl: "https://bsky.app/profile/ryanswatches.com/post/3m2uvdvq7622g",
        wearCount: 2, lastWornAt: "2026-10-02T07:58:00-07:00", postCount: 2)

    static let kurono = WearWatch(
        id: "3mwz3ctxxnc26", brand: "Kurono", model: "Malachite",
        imageUrl: "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite",
        thumbnailUrl: "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreikuronomalachite",
        postUrl: "https://bsky.app/profile/ryanswatches.com/post/3mwz3ctxxnc26",
        wearCount: 1, lastWornAt: "2026-10-03T08:05:00-07:00", postCount: 1)

    static let skagen = WearWatch(
        id: "3m2uxrekinc2e", brand: "Skagen", model: "233LTMN Quartz",
        imageUrl: "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone",
        thumbnailUrl: "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:ep6hd5cp5gxj6pifezbar6nc/bafkreiskagenone",
        postUrl: "https://bsky.app/profile/ryanswatches.com/post/3m2uxrekinc2e",
        wearCount: 0, lastWornAt: nil, postCount: 1)

    static let watches: [WearWatch] = [citizen, kurono, skagen]

    static let event1 = WearEvent(id: "11111111-1111-4111-8111-111111111111", watchId: "3m2uvdvq7622g",
                                  wornAt: "2026-10-01T08:00:00-07:00", source: .app)
    static let event2 = WearEvent(id: "22222222-2222-4222-8222-222222222222", watchId: "3mwz3ctxxnc26",
                                  wornAt: "2026-10-03T08:05:00-07:00", source: .notification)
    static let event3 = WearEvent(id: "33333333-3333-4333-8333-333333333333", watchId: "3m2uvdvq7622g",
                                  wornAt: "2026-10-02T07:58:00-07:00", source: .widget)
    static let events: [WearEvent] = [event1, event2, event3]
}
