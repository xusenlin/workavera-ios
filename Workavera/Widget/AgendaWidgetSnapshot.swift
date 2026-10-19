import Foundation

/// A flattened, widget-ready view of Calendar events and Board task deadlines.
///
/// Repeating events are expanded into occurrences ahead of time so the widget
/// only has to filter by day when it renders. The snapshot covers today plus
/// `lookaheadDays`, which is plenty for the handful of upcoming items shown.
struct AgendaWidgetSnapshot: Codable, Equatable {
    static let lookaheadDays = 60

    let timezone: String
    let items: [AgendaWidgetItem]
    let updatedAt: Date

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar
    }

    func dayKey(for date: Date) -> String {
        Self.dayFormatter(timeZone: calendar.timeZone).string(from: date)
    }

    static func dayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

struct AgendaWidgetItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case event
        case task
    }

    let id: String
    let kind: Kind
    let title: String
    /// Project name for tasks, location for events.
    let detail: String
    /// Every `yyyy-MM-dd` day (in the snapshot time zone) the item covers.
    let dayKeys: [String]
    let startAt: Date?
    let endAt: Date?
    let allDay: Bool
    /// `EventColor` raw value for events, `TaskPriority` raw value for tasks.
    let tint: String

    var firstDayKey: String { dayKeys.first ?? "" }
}

extension AgendaWidgetSnapshot {
    init(
        events: [AppEvent],
        tasks: [CalendarTaskDeadline],
        timezone: String,
        now: Date = .now
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let formatter = Self.dayFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: now)
        let windowEnd = calendar.date(byAdding: .day, value: Self.lookaheadDays, to: today) ?? today
        let todayKey = formatter.string(from: today)
        let windowEndKey = formatter.string(from: windowEnd)

        var occurrences: [String: AppEventOccurrence] = [:]
        var occurrenceDays: [String: [String]] = [:]
        var day = today
        while day < windowEnd {
            let key = formatter.string(from: day)
            for event in events {
                for occurrence in event.occurrences(overlapping: day, calendar: calendar) {
                    occurrences[occurrence.id] = occurrence
                    occurrenceDays[occurrence.id, default: []].append(key)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let eventItems = occurrences.values.map { occurrence in
            AgendaWidgetItem(
                id: occurrence.id,
                kind: .event,
                title: occurrence.event.title,
                detail: occurrence.event.location,
                dayKeys: occurrenceDays[occurrence.id] ?? [],
                startAt: occurrence.startAt,
                endAt: occurrence.endAt,
                allDay: occurrence.event.allDay,
                tint: occurrence.event.color.rawValue
            )
        }
        let taskItems = tasks
            .filter { !$0.completed && $0.dueDate >= todayKey && $0.dueDate < windowEndKey }
            .map { task in
                AgendaWidgetItem(
                    id: task.id,
                    kind: .task,
                    title: task.title,
                    detail: task.projectName,
                    dayKeys: [task.dueDate],
                    startAt: nil,
                    endAt: nil,
                    allDay: true,
                    tint: task.priority.rawValue
                )
            }

        self.timezone = calendar.timeZone.identifier
        self.items = (eventItems + taskItems).sorted(by: Self.precedes)
        self.updatedAt = now
    }

    /// Orders items by day, then all-day entries, then start time.
    private static func precedes(_ lhs: AgendaWidgetItem, _ rhs: AgendaWidgetItem) -> Bool {
        if lhs.firstDayKey != rhs.firstDayKey { return lhs.firstDayKey < rhs.firstDayKey }
        if lhs.allDay != rhs.allDay { return lhs.allDay }
        let lhsStart = lhs.startAt ?? .distantPast
        let rhsStart = rhs.startAt ?? .distantPast
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    /// Same agenda content, ignoring when it was fetched.
    func hasSameItems(as other: AgendaWidgetSnapshot?) -> Bool {
        guard let other else { return false }
        return timezone == other.timezone && items == other.items
    }
}
