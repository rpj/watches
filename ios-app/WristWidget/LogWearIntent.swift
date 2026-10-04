import AppIntents
import WidgetKit
import WristCore
import WristKit

struct LogWearIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a watch"
    static var description = IntentDescription("Record that this watch is on your wrist now.")
    static var openAppWhenRun: Bool = false
    // Raw watchID parameter; not meant for Shortcuts yet.
    static var isDiscoverable: Bool = false

    @Parameter(title: "Watch ID")
    var watchID: String

    init() {}

    init(watchID: String) {
        self.watchID = watchID
    }

    func perform() async throws -> some IntentResult {
        let services = WristServices.current()
        guard let store = services.makeStore() else { return .result() }
        await store.loadCached()
        await store.logWear(watchID: watchID, source: .widget)
        WristServices.reloadWidgets()
        return .result()
    }
}
