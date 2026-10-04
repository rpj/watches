import Foundation

public enum WearSource: String, Codable, Sendable, CaseIterable, Equatable {
    case app, notification, widget, shortcut
}

public struct WearEvent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let watchId: String
    public let wornAt: String
    public let source: WearSource
    /// Server-set; nil for events created locally and not yet sent.
    public let recordedAt: String?

    public init(id: String, watchId: String, wornAt: String, source: WearSource, recordedAt: String? = nil) {
        self.id = id
        self.watchId = watchId
        self.wornAt = wornAt
        self.source = source
        self.recordedAt = recordedAt
    }
}

/// Request body for POST /api/wear/events: exactly the four fields.
public struct NewWearEvent: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let watchId: String
    public let wornAt: String
    public let source: WearSource

    public init(id: String, watchId: String, wornAt: String, source: WearSource) {
        self.id = id
        self.watchId = watchId
        self.wornAt = wornAt
        self.source = source
    }
}

public struct WearWatch: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let brand: String
    public let model: String
    public let imageUrl: String?
    public let thumbnailUrl: String?
    public let postUrl: String
    public let wearCount: Int
    public let lastWornAt: String?
    public let postCount: Int

    public var displayName: String { "\(brand) \(model)" }

    public init(
        id: String,
        brand: String,
        model: String,
        imageUrl: String?,
        thumbnailUrl: String?,
        postUrl: String,
        wearCount: Int,
        lastWornAt: String?,
        postCount: Int
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.postUrl = postUrl
        self.wearCount = wearCount
        self.lastWornAt = lastWornAt
        self.postCount = postCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, brand, model, imageUrl, thumbnailUrl, postUrl, wearCount, lastWornAt, postCount
    }
}

public struct WatchesResponse: Codable, Sendable, Equatable {
    public let watches: [WearWatch]
    public let current: WearEvent?
    public let generatedAt: String

    public init(watches: [WearWatch], current: WearEvent?, generatedAt: String) {
        self.watches = watches
        self.current = current
        self.generatedAt = generatedAt
    }
}

public struct EventsResponse: Codable, Sendable, Equatable {
    public let events: [WearEvent]

    public init(events: [WearEvent]) {
        self.events = events
    }
}

public struct RecordResponse: Codable, Sendable, Equatable {
    public let event: WearEvent
    public let created: Bool

    public init(event: WearEvent, created: Bool) {
        self.event = event
        self.created = created
    }
}

public struct APIErrorBody: Codable, Sendable, Equatable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}

public enum WearDates {
    /// Accepts ISO 8601 with offset or Z, with or without fractional seconds. nil if unparseable.
    public static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// ISO 8601 with numeric offset for the given zone, no fractional seconds (UTC renders as "Z").
    public static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

public enum WristJSON {
    public static let decoder: JSONDecoder = JSONDecoder()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
