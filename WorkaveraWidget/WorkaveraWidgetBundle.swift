import SwiftUI
import WidgetKit

@main
struct WorkaveraWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgendaWidget()
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AgendaWidgetStore.widgetKind,
            intent: AgendaWidgetConfigurationIntent.self,
            provider: AgendaWidgetProvider()
        ) { entry in
            AgendaWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Agenda")
        .description("This month's calendar with your tasks and events for the next seven days.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
