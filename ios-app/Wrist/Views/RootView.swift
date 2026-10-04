import SwiftUI

/// Switches between loading, first-run setup, and the picker.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .needsSetup:
            SetupView()
        case .ready:
            NavigationStack { PickerView() }
        }
    }
}
