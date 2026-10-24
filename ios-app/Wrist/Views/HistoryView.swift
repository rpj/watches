import SwiftUI
import WristCore
import WristKit

/// Recent wears grouped by day, with swipe-to-delete for mis-logged entries.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var events: [WearEvent] = []
    @State private var loading = true
    @State private var error: String?

    private struct DaySection: Identifiable {
        let id: String
        let title: String
        let events: [WearEvent]
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && events.isEmpty {
            ProgressView()
        } else if let error, events.isEmpty {
            ContentUnavailableView(error, systemImage: "wifi.exclamationmark")
        } else if events.isEmpty {
            ContentUnavailableView("No wears logged yet", systemImage: "clock")
        } else {
            list
        }
    }

    private var list: some View {
        let sections = daySections
        return List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.events) { event in
                        row(event)
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if section.id == sections.last?.id {
                        Text("Swipe left to delete a wear. Deleting the latest one makes the previous watch current again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("history.list")
    }

    // MARK: - Rows

    private func row(_ event: WearEvent) -> some View {
        let name = model.watchName(for: event.watchId)
        let time = timeText(event)
        return HStack {
            WatchThumbnail(model.watch(for: event.watchId), size: 40)
            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text(time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: sourceSymbol(event.source))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.row.\(event.id)")
        .accessibilityLabel("\(name), \(time)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await delete(event) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func timeText(_ event: WearEvent) -> String {
        guard let date = WearDates.parse(event.wornAt) else { return "Unknown time" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func sourceSymbol(_ source: WearSource) -> String {
        switch source {
        case .app: return "iphone"
        case .notification: return "bell"
        case .widget: return "square.grid.2x2"
        case .shortcut: return "wand.and.stars"
        }
    }

    // MARK: - Grouping

    private var daySections: [DaySection] {
        let calendar = Calendar.autoupdatingCurrent
        var result: [DaySection] = []
        var unknown: [WearEvent] = []
        for event in events {
            guard let date = WearDates.parse(event.wornAt) else {
                unknown.append(event)
                continue
            }
            let day = calendar.startOfDay(for: date)
            let id = String(day.timeIntervalSince1970)
            if let index = result.firstIndex(where: { $0.id == id }) {
                let existing = result[index]
                result[index] = DaySection(id: id, title: existing.title, events: existing.events + [event])
            } else {
                result.append(DaySection(id: id, title: dayTitle(day, calendar: calendar), events: [event]))
            }
        }
        if !unknown.isEmpty {
            result.append(DaySection(id: "unknown", title: "Unknown date", events: unknown))
        }
        return result
    }

    private func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Actions

    private func load() async {
        do {
            events = try await model.recentEvents()
            error = nil
        } catch {
            self.error = WearStore.message(for: error)
        }
        loading = false
    }

    private func delete(_ event: WearEvent) async {
        events.removeAll { $0.id == event.id }
        await model.deleteEvent(event.id)
        await load()
    }
}

#Preview {
    let model = AppModel(services: .fixtures())
    return NavigationStack { HistoryView() }
        .environment(model)
        .task { await model.start() }
}
