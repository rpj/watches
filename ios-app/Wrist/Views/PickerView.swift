import SwiftUI
import UIKit
import WristCore
import WristKit

/// The whole app: current-watch card plus every watch, most-worn first.
struct PickerView: View {
    @Environment(AppModel.self) private var model

    private var errorText: String? {
        let state = model.state
        guard state.pendingCount > 0 || state.watches.isEmpty else { return nil }
        return state.lastError
    }

    var body: some View {
        List {
            CurrentWatchCard(
                watch: model.currentWatch,
                since: model.state.current?.wornAt,
                pendingCount: model.state.pendingCount,
                errorText: errorText
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))

            if !model.state.isLoaded {
                ContentUnavailableView("Loading your watches", systemImage: "clock")
                    .listRowSeparator(.hidden)
            } else if model.state.watches.isEmpty {
                ContentUnavailableView(
                    "No watches yet",
                    systemImage: "clock",
                    description: Text("Classify some posts on the gallery first.")
                )
                .listRowSeparator(.hidden)
            }

            ForEach(model.state.watches) { watch in
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task { await model.log(watch) }
                } label: {
                    WatchRow(watch: watch, isCurrent: watch.id == model.state.current?.watchId)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("picker.row.\(watch.id)")
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("picker.list")
        .animation(.snappy, value: model.state.watches.map(\.id))
        .refreshable { await model.refresh() }
        .navigationTitle("Wrist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("picker.settings")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let lastLogged = model.lastLogged {
                undoBar(for: lastLogged)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.lastLogged?.id)
    }

    private func undoBar(for event: NewWearEvent) -> some View {
        let name = model.state.watches.first { $0.id == event.watchId }?.displayName ?? "watch"
        return HStack {
            Text("Logged \(name)").lineLimit(1)
            Spacer()
            Button("Undo") { Task { await model.undoLast() } }
                .fontWeight(.semibold)
                .accessibilityIdentifier("picker.undo")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
    }
}

#Preview {
    let model = AppModel(services: .fixtures())
    return RootView()
        .environment(model)
        .task { await model.start() }
}
