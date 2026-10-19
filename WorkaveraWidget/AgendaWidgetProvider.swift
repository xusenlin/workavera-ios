import Foundation
import WidgetKit

struct AgendaWidgetEntry: TimelineEntry {
    enum Status {
        case ready
        case signedOut
        case unavailable
    }

    let date: Date
    let snapshot: AgendaWidgetSnapshot?
    let status: Status
    let content: AgendaWidgetContent
    let itemCount: AgendaWidgetItemCount
}

struct AgendaWidgetProvider: AppIntentTimelineProvider {
    /// A snapshot this recent was just fetched (for example by the refresh button),
    /// so the timeline reload that follows can reuse it.
    private static let freshnessInterval: TimeInterval = 60
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> AgendaWidgetEntry {
        .sample(content: .all, itemCount: .six)
    }

    func snapshot(
        for configuration: AgendaWidgetConfigurationIntent,
        in context: Context
    ) async -> AgendaWidgetEntry {
        if !context.isPreview, let cached = AgendaWidgetStore.loadSnapshot() {
            return AgendaWidgetEntry(
                date: .now,
                snapshot: cached,
                status: .ready,
                content: configuration.content,
                itemCount: configuration.itemCount
            )
        }
        return .sample(content: configuration.content, itemCount: configuration.itemCount)
    }

    func timeline(
        for configuration: AgendaWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<AgendaWidgetEntry> {
        let now = Date.now
        var snapshot = AgendaWidgetStore.loadSnapshot()
        var status = AgendaWidgetEntry.Status.ready

        if let cached = snapshot, now.timeIntervalSince(cached.updatedAt) < Self.freshnessInterval {
            // Fresh enough; skip the network.
        } else {
            do {
                snapshot = try await AgendaWidgetFetcher.refresh()
            } catch AgendaWidgetFetcher.FetchError.signedOut {
                snapshot = nil
                status = .signedOut
            } catch {
                // Keep showing the cached agenda when the server is unreachable.
                if snapshot == nil { status = .unavailable }
            }
        }

        let entry = AgendaWidgetEntry(
            date: now,
            snapshot: snapshot,
            status: status,
            content: configuration.content,
            itemCount: configuration.itemCount
        )
        let calendar = snapshot?.calendar ?? .current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(Self.refreshInterval)
        let nextRefresh = min(tomorrow, now.addingTimeInterval(Self.refreshInterval))
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

extension AgendaWidgetEntry {
    /// Gallery and placeholder content.
    static func sample(content: AgendaWidgetContent, itemCount: AgendaWidgetItemCount) -> AgendaWidgetEntry {
        let now = Date.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = AgendaWidgetSnapshot.dayFormatter(timeZone: .current)
        func day(_ offset: Int) -> String {
            formatter.string(from: calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        }
        func time(_ offset: Int, hour: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }
        let items = [
            AgendaWidgetItem(
                id: "sample-standup", kind: .event, title: String(localized: "Team standup"), detail: "",
                dayKeys: [day(0)], startAt: time(0, hour: 10), endAt: time(0, hour: 11),
                allDay: false, tint: EventColor.blue.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-review", kind: .task, title: String(localized: "Review release notes"), detail: "Workavera",
                dayKeys: [day(1)], startAt: nil, endAt: nil,
                allDay: true, tint: TaskPriority.high.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-launch", kind: .event, title: String(localized: "Product launch"), detail: "",
                dayKeys: [day(3)], startAt: time(3, hour: 0), endAt: time(4, hour: 0),
                allDay: true, tint: EventColor.green.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-design", kind: .event, title: String(localized: "Design review"), detail: String(localized: "Room 3"),
                dayKeys: [day(4)], startAt: time(4, hour: 14), endAt: time(4, hour: 15),
                allDay: false, tint: EventColor.purple.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-invoice", kind: .task, title: String(localized: "Send invoices"), detail: String(localized: "Finance"),
                dayKeys: [day(6)], startAt: nil, endAt: nil,
                allDay: true, tint: TaskPriority.medium.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-dinner", kind: .event, title: String(localized: "Team dinner"), detail: "",
                dayKeys: [day(9)], startAt: time(9, hour: 19), endAt: time(9, hour: 21),
                allDay: false, tint: EventColor.amber.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-plan", kind: .task, title: String(localized: "Plan next sprint"), detail: "Workavera",
                dayKeys: [day(11)], startAt: nil, endAt: nil,
                allDay: true, tint: TaskPriority.low.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-birthday", kind: .event, title: String(localized: "Mom's birthday"), detail: "",
                dayKeys: [day(14)], startAt: time(14, hour: 0), endAt: time(15, hour: 0),
                allDay: true, tint: EventColor.red.rawValue
            ),
        ]
        return AgendaWidgetEntry(
            date: now,
            snapshot: AgendaWidgetSnapshot(timezone: TimeZone.current.identifier, items: items, updatedAt: now),
            status: .ready,
            content: content,
            itemCount: itemCount
        )
    }
}
