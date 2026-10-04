import Foundation
import WristCore

/// JSON files in a shared directory (the App Group container) so the app and
/// the widget see the same snapshot and the same pending queue.
public final class FileWearPersistence: WearPersistence, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    private var pendingURL: URL { directory.appendingPathComponent("pending.json") }

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Persistence rooted in the App Group container, or in the app's own
    /// Application Support directory when the group is unavailable.
    public static func shared(appGroupID: String = WristConstants.appGroupID) -> FileWearPersistence {
        let fm = FileManager.default
        let root = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return FileWearPersistence(directory: root.appendingPathComponent("wear", isDirectory: true))
    }

    public func loadSnapshot() throws -> WearSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try decoder.decode(WearSnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: WearSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
    }

    public func loadPending() throws -> [PendingWearEvent] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: pendingURL) else { return [] }
        return try decoder.decode([PendingWearEvent].self, from: data)
    }

    public func savePending(_ events: [PendingWearEvent]) throws {
        lock.lock(); defer { lock.unlock() }
        try encoder.encode(events).write(to: pendingURL, options: .atomic)
    }

    /// Remove both files (used by "Reset connection").
    public func wipe() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: snapshotURL)
        try? FileManager.default.removeItem(at: pendingURL)
    }
}
