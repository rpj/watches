import SwiftUI
import UIKit
import WristKit

/// First-run connection form: server URL plus API token.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gallery") {
                    TextField("https://ryanswatches.com", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("setup.url")
                }
                Section("Token") {
                    SecureField("WEAR_API_TOKEN", text: $token)
                        .accessibilityIdentifier("setup.token")
                    Button("Paste from clipboard") {
                        if let s = UIPasteboard.general.string {
                            token = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                Section {
                    Button {
                        connect()
                    } label: {
                        if model.isConnecting {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(model.isConnecting || token.isEmpty || url.isEmpty)
                    .accessibilityIdentifier("setup.connect")
                } footer: {
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("setup.error")
                    } else {
                        Text("The token is the server's WEAR_API_TOKEN. It is stored in the Keychain.")
                    }
                }
            }
            .navigationTitle("Connect")
            .onAppear {
                if url.isEmpty { url = model.services.serverURL.absoluteString }
            }
        }
    }

    private func connect() {
        error = nil
        guard let serverURL = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Enter a valid URL"
            return
        }
        Task {
            do {
                try await model.connect(serverURL: serverURL, token: token)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview {
    let model = AppModel(services: .fixtures())
    return SetupView().environment(model)
}
