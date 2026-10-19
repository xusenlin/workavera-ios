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
        .description("Your next six tasks and events, each marked with its date.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
