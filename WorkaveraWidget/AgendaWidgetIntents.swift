import AppIntents
import WidgetKit

enum AgendaWidgetContent: String, AppEnum {
    case all
    case tasks
    case events

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Content"
    static var caseDisplayRepresentations: [AgendaWidgetContent: DisplayRepresentation] = [
        .all: "Tasks and Events",
        .tasks: "Tasks Only",
        .events: "Events Only",
    ]

    func includes(_ item: AgendaWidgetItem) -> Bool {
        switch self {
        case .all: true
        case .tasks: item.kind == .task
        case .events: item.kind == .event
        }
    }
}

struct AgendaWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Agenda"
    static var description = IntentDescription("Choose what appears next to the calendar.")

    @Parameter(title: "Show", default: .all)
    var content: AgendaWidgetContent
}

/// Backs the widget's refresh button. WidgetKit reloads the timeline after this
/// runs, and the provider then renders the snapshot fetched here.
struct RefreshAgendaIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Agenda"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        _ = try? await AgendaWidgetFetcher.refresh()
        return .result()
    }
}
