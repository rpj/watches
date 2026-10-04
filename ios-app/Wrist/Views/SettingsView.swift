import SwiftUI
import UIKit
import WristCore

/// Nudge preferences, connection reset, and version.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NudgeConfig.default
    @State private var confirm = false

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { draft.enabled },
            set: { newValue in
                draft.enabled = newValue
                apply()
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft = NudgeConfig(enabled: draft.enabled, hour: c.hour ?? draft.hour, minute: c.minute ?? draft.minute)
                apply()
            }
        )
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                Toggle("Remind me to log", isOn: enabledBinding)
                    .accessibilityIdentifier("settings.nudgeToggle")
                if draft.enabled {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("settings.nudgeTime")
                }
                if model.notificationsDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link("Notifications are off for Wrist — open Settings", destination: settingsURL)
                }
            } header: {
                Text("Morning nudge")
            } footer: {
                Text("Skipped on days you've already logged. The notification's buttons log your top three without opening the app.")
            }

            Section("Connection") {
                LabeledContent(
                    "Server",
                    value: model.services.serverURL.host() ?? model.services.serverURL.absoluteString
                )
                Button("Reset connection", role: .destructive) { confirm = true }
                    .accessibilityIdentifier("settings.reset")
                    .confirmationDialog("Forget this server and token?", isPresented: $confirm, titleVisibility: .visible) {
                        Button("Reset", role: .destructive) {
                            Task {
                                await model.resetConnection()
                                dismiss()
                            }
                        }
                    }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Wrist \(version)")
            }
        }
        .navigationTitle("Settings")
        .onAppear { draft = model.nudgeConfig }
    }

    /// Push the draft to the model, then re-sync so a denied permission flips the toggle back.
    private func apply() {
        let config = draft
        Task {
            await model.setNudge(config)
            draft = model.nudgeConfig
        }
    }
}
