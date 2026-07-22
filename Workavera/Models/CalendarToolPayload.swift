import Foundation

/// Parsed view of a `calendar_*` assistant tool call output:
/// - `calendar_get_schedule`: `{"days":[{date, tasks, events}]}` where events
///   are expanded occurrences (`instanceStart`/`instanceEnd` preferred)
/// - `calendar_create_event` / `calendar_update_event`: batch envelope whose
///   per-item result is an `EventMutationResult`, or a single result
/// `calendar_delete_event` is approval-gated and stays on the generic card.
struct CalendarToolPayload: Equatable, Sendable {
    struct Event: Equatable, Sendable, Identifiable {
        let id: String
        var title: String
        var allDay = false
        var start: Date?
        var end: Date?
        var location: String?
        var color: EventColor?
        var recurrence: EventRecurrenceFrequency?
    }

    struct ScheduleTask: Equatable, Sendable, Identifiable {
        let id: String
        var title: String
        var priority: TaskPriority?
        var dueDate: String?
        var projectName: String?
        var completed = false
    }

    struct Day: Equatable, Sendable, Identifiable {
        let date: String
        var events: [Event] = []
        var tasks: [ScheduleTask] = []

        var id: String { date }
    }

    struct MutationItem: Equatable, Sendable, Identifiable {
        let index: Int
        var ok: Bool
        var title: String?
        var action: String?
        var error: String?

        var id: Int { index }
    }

    var days: [Day] = []
    var mutationTotal = 0
    var mutationSucceeded = 0
    var mutationItems: [MutationItem] = []
    var isBatchMutation = false

    init?(toolName: String, output: JSONValue?) {
        guard let value = output?.decodingEmbeddedJSON else { return nil }
        switch toolName {
        case "calendar_get_schedule":
            guard let dayValues = value.objectValue?["days"]?.arrayValue else { return nil }
            days = dayValues.compactMap(Self.day)
        case "calendar_create_event", "calendar_update_event":
            guard let object = value.objectValue else { return nil }
            if let results = object["results"]?.arrayValue {
                isBatchMutation = true
                mutationTotal = object["total"]?.intValue ?? results.count
                mutationSucceeded = object["succeeded"]?.intValue ?? 0
                mutationItems = results.map(Self.mutationItem)
            } else {
                let item = Self.mutationItem(from: value)
                mutationItems = [item]
                mutationTotal = 1
                mutationSucceeded = item.ok ? 1 : 0
            }
        default:
            return nil
        }
    }

    private static func day(from value: JSONValue) -> Day? {
        guard let object = value.objectValue,
              let date = object["date"]?.stringValue else { return nil }
        return Day(
            date: date,
            events: (object["events"]?.arrayValue ?? []).compactMap(event),
            tasks: (object["tasks"]?.arrayValue ?? []).compactMap(task)
        )
    }

    private static func event(from value: JSONValue) -> Event? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let title = object["title"]?.stringValue else { return nil }
        // Occurrences carry RFC3339 instance times; fall back to the event's
        // own PocketBase datetimes.
        let start = object["instanceStart"]?.stringValue.flatMap(CalendarDate.parse)
            ?? object["startAt"]?.stringValue.flatMap(CalendarDate.parse)
        let end = object["instanceEnd"]?.stringValue.flatMap(CalendarDate.parse)
            ?? object["endAt"]?.stringValue.flatMap(CalendarDate.parse)
        return Event(
            id: id,
            title: title,
            allDay: object["allDay"]?.boolValue ?? false,
            start: start,
            end: end,
            location: nonEmpty(object["location"]?.stringValue),
            color: object["color"]?.stringValue.flatMap(EventColor.init(rawValue:)),
            recurrence: object["recurrenceFrequency"]?.stringValue
                .flatMap(EventRecurrenceFrequency.init(rawValue:))
        )
    }

    private static func task(from value: JSONValue) -> ScheduleTask? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let title = object["title"]?.stringValue else { return nil }
        return ScheduleTask(
            id: id,
            title: title,
            priority: object["priority"]?.stringValue.flatMap(TaskPriority.init(rawValue:)),
            dueDate: nonEmpty(object["dueDate"]?.stringValue),
            projectName: nonEmpty(object["projectName"]?.stringValue),
            completed: object["completed"]?.boolValue ?? false
        )
    }

    private static func mutationItem(from value: JSONValue) -> MutationItem {
        let object = value.objectValue
        // Batch per-item: {index, ok, result: EventMutationResult, error}
        // Single: EventMutationResult {ok, action, event}
        let result = object?["result"]?.objectValue ?? object
        return MutationItem(
            index: object?["index"]?.intValue ?? 0,
            ok: object?["ok"]?.boolValue ?? true,
            title: result?["event"]?.objectValue?["title"]?.stringValue,
            action: result?["action"]?.stringValue,
            error: nonEmpty(object?["error"]?.stringValue)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
