import Foundation
import SwiftUI

enum EventColor: String, Codable, CaseIterable, Identifiable {
    case blue
    case green
    case amber
    case red
    case purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(hex: "#3b82f6")
        case .green: Color(hex: "#22c55e")
        case .amber: Color(hex: "#f59e0b")
        case .red: Color(hex: "#ef4444")
        case .purple: Color(hex: "#8b5cf6")
        }
    }
}

enum EventRecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Does not repeat"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    var intervalUnit: String {
        switch self {
        case .none: "time"
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
    }
}

enum EventReminder: Int, Codable, CaseIterable, Identifiable {
    case none = -1
    case atStart = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60
    case oneDay = 1440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: "No reminder"
        case .atStart: "At start time"
        case .fiveMinutes: "5 minutes before"
        case .tenMinutes: "10 minutes before"
        case .thirtyMinutes: "30 minutes before"
        case .oneHour: "1 hour before"
        case .oneDay: "1 day before"
        }
    }
}

struct AppEvent: Identifiable, Equatable, Decodable {
    let id: String
    let ownerID: String
    var title: String
    var description: String
    var startAt: Date
    var endAt: Date
    var allDay: Bool
    var timezone: String
    var location: String
    var color: EventColor
    var recurrenceFrequency: EventRecurrenceFrequency
    var recurrenceInterval: Int
    var reminder: EventReminder

    private enum CodingKeys: String, CodingKey {
        case id, title, description, timezone, location, color
        case ownerID = "owner"
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case recurrenceFrequency = "recurrence_frequency"
        case recurrenceInterval = "recurrence_interval"
        case reminder = "reminder_minutes_before"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        startAt = try CalendarDate.decode(.startAt, from: container)
        endAt = try CalendarDate.decode(.endAt, from: container)
        allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? TimeZone.current.identifier
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        color = try container.decodeIfPresent(EventColor.self, forKey: .color) ?? .blue
        recurrenceFrequency = try container.decodeIfPresent(
            EventRecurrenceFrequency.self,
            forKey: .recurrenceFrequency
        ) ?? .none
        recurrenceInterval = max(
            1,
            try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval) ?? 1
        )
        let reminderMinutes = try container.decodeIfPresent(Int.self, forKey: .reminder) ?? -1
        reminder = EventReminder(rawValue: reminderMinutes) ?? .none
    }

    func occurrences(overlapping day: Date, calendar: Calendar) -> [AppEventOccurrence] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let duration = endAt.timeIntervalSince(startAt)
        guard duration > 0 else { return [] }

        var eventCalendar = Calendar(identifier: .gregorian)
        eventCalendar.timeZone = TimeZone(identifier: timezone) ?? calendar.timeZone
        var result: [AppEventOccurrence] = []

        for index in 0..<100_000 {
            let occurrence = recurrenceDate(at: index, calendar: eventCalendar)
            if occurrence.marker >= dayEnd { break }
            guard let occurrenceStart = occurrence.date else {
                if recurrenceFrequency == .none { break }
                continue
            }
            if occurrenceStart >= dayEnd { break }
            let occurrenceEnd = occurrenceStart.addingTimeInterval(duration)
            if occurrenceEnd > dayStart {
                result.append(
                    AppEventOccurrence(event: self, startAt: occurrenceStart, endAt: occurrenceEnd)
                )
            }
            if recurrenceFrequency == .none { break }
        }
        return result
    }

    private func recurrenceDate(at index: Int, calendar: Calendar) -> (date: Date?, marker: Date) {
        let interval = max(1, recurrenceInterval)
        switch recurrenceFrequency {
        case .none:
            return (index == 0 ? startAt : nil, index == 0 ? startAt : .distantFuture)
        case .daily:
            let date = calendar.date(byAdding: .day, value: interval * index, to: startAt) ?? .distantFuture
            return (date, date)
        case .weekly:
            let date = calendar.date(byAdding: .day, value: interval * index * 7, to: startAt) ?? .distantFuture
            return (date, date)
        case .monthly:
            return monthOccurrence(offset: interval * index, calendar: calendar)
        case .yearly:
            return monthOccurrence(offset: interval * index * 12, calendar: calendar)
        }
    }

    private func monthOccurrence(offset: Int, calendar: Calendar) -> (date: Date?, marker: Date) {
        let base = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: startAt)
        guard let baseYear = base.year, let baseMonth = base.month, let baseDay = base.day else {
            return (nil, .distantFuture)
        }
        let monthIndex = baseYear * 12 + baseMonth - 1 + offset
        let year = monthIndex / 12
        let month = monthIndex % 12 + 1
        var markerComponents = DateComponents()
        markerComponents.calendar = calendar
        markerComponents.timeZone = calendar.timeZone
        markerComponents.year = year
        markerComponents.month = month
        markerComponents.day = 1
        guard let marker = calendar.date(from: markerComponents),
              let validDays = calendar.range(of: .day, in: .month, for: marker),
              validDays.contains(baseDay) else {
            return (nil, calendar.date(from: markerComponents) ?? .distantFuture)
        }

        var components = markerComponents
        components.day = baseDay
        components.hour = base.hour
        components.minute = base.minute
        components.second = base.second
        return (calendar.date(from: components), marker)
    }
}

struct AppEventOccurrence: Identifiable, Equatable {
    let event: AppEvent
    let startAt: Date
    let endAt: Date

    var id: String { "\(event.id):\(startAt.timeIntervalSince1970)" }
}

struct CalendarTaskDeadline: Identifiable, Equatable, Decodable {
    struct Expansion: Decodable {
        struct Project: Decodable { let name: String }
        struct State: Decodable { let category: BoardStateCategory }

        let project: Project?
        let state: State?
    }

    let id: String
    let projectID: String
    let title: String
    let description: String
    let dueDate: String
    let projectName: String
    let priority: TaskPriority
    let completed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, project, title, description, priority, expand
        case dueDate = "due_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let expansion = try container.decodeIfPresent(Expansion.self, forKey: .expand)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .project)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        dueDate = String((try container.decode(String.self, forKey: .dueDate)).prefix(10))
        projectName = expansion?.project?.name ?? "Board"
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        completed = expansion?.state?.category == .completed
    }
}

struct CalendarSnapshot {
    let events: [AppEvent]
    let tasks: [CalendarTaskDeadline]
    let timezone: String
}

struct CalendarEventInput: Equatable {
    let title: String
    let description: String
    let startAt: Date
    let endAt: Date
    let allDay: Bool
    let timezone: String
    let location: String
    let color: EventColor
    let recurrenceFrequency: EventRecurrenceFrequency
    let recurrenceInterval: Int
    let reminder: EventReminder
}

enum CalendarRealtimeAction: String, Decodable {
    case create
    case update
    case delete
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

struct CalendarRealtimeSignal: Decodable {
    struct Record: Decodable { let id: String }
    let action: CalendarRealtimeAction
    let record: Record
}

enum CalendarDate {
    static func parse(_ value: String) -> Date? {
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISO = ISO8601DateFormatter()
        standardISO.formatOptions = [.withInternetDateTime]
        let pocketBase = DateFormatter()
        pocketBase.locale = Locale(identifier: "en_US_POSIX")
        pocketBase.calendar = Calendar(identifier: .gregorian)
        pocketBase.timeZone = TimeZone(secondsFromGMT: 0)
        pocketBase.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        return fractionalISO.date(from: value)
            ?? standardISO.date(from: value)
            ?? pocketBase.date(from: value)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func dayKey(for date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    fileprivate static func decode<Key: CodingKey>(
        _ key: Key,
        from container: KeyedDecodingContainer<Key>
    ) throws -> Date {
        let value = try container.decode(String.self, forKey: key)
        guard let date = parse(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid Calendar date: \(value)"
            )
        }
        return date
    }
}
