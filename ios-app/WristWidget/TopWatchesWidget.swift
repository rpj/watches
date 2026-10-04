import SwiftUI
import WidgetKit
import WristKit

struct TopWatchesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WristConstants.widgetKind, provider: WearProvider()) { entry in
            TopWatchesView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("On the wrist")
        .description("See what you're wearing and log your top watches with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    TopWatchesWidget()
} timeline: {
    WearEntry.placeholder
}

#Preview(as: .systemSmall) {
    TopWatchesWidget()
} timeline: {
    WearEntry.placeholder
}
