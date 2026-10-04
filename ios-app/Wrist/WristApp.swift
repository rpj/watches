import SwiftUI
import WristKit

/// App entry point. One window, one model, injected through the environment.
@main
struct WristApp: App {
    @State private var model = AppModel(services: WristServices.current())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.handleForeground() }
                }
                .onOpenURL { _ in }
        }
    }
}
