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
}

struct AgendaWidgetProvider: AppIntentTimelineProvider {
    /// A snapshot this recent was just fetched (for example by the refresh button),
    /// so the timeline reload that follows can reuse it.
    private static let freshnessInterval: TimeInterval = 60
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> AgendaWidgetEntry {
        .sample(content: .all)
    }

    func snapshot(
        for configuration: AgendaWidgetConfigurationIntent,
        in context: Context
    ) async -> AgendaWidgetEntry {
        if !context.isPreview, let cached = AgendaWidgetStore.loadSnapshot() {
            return AgendaWidgetEntry(date: .now, snapshot: cached, status: .ready, content: configuration.content)
        }
        return .sample(content: configuration.content)
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
            content: configuration.content
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
    static func sample(content: AgendaWidgetContent) -> AgendaWidgetEntry {
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
                id: "sample-standup", kind: .event, title: "Team standup", detail: "",
                dayKeys: [day(0)], startAt: time(0, hour: 10), endAt: time(0, hour: 11),
                allDay: false, tint: EventColor.blue.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-review", kind: .task, title: "Review release notes", detail: "Workavera",
                dayKeys: [day(1)], startAt: nil, endAt: nil,
                allDay: true, tint: TaskPriority.high.rawValue
            ),
            AgendaWidgetItem(
                id: "sample-launch", kind: .event, title: "Product launch", detail: "",
                dayKeys: [day(3)], startAt: time(3, hour: 0), endAt: time(4, hour: 0),
                allDay: true, tint: EventColor.green.rawValue
            ),
        ]
        return AgendaWidgetEntry(
            date: now,
            snapshot: AgendaWidgetSnapshot(timezone: TimeZone.current.identifier, items: items, updatedAt: now),
            status: .ready,
            content: content
        )
    }
}
