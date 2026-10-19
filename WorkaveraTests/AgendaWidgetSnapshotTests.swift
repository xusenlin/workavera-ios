import XCTest
@testable import Workavera

final class AgendaWidgetSnapshotTests: XCTestCase {
    private let timezone = "Asia/Shanghai"

    private func decode<T: Decodable>(_ type: T.Type, _ string: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(string.utf8))
    }

    /// 2026-10-19 10:00 in Shanghai.
    private var now: Date {
        CalendarDate.parse("2026-10-19T02:00:00Z")!
    }

    func testExpandsRepeatingAndOneOffEventsIntoLocalDays() throws {
        let events = try decode([AppEvent].self, #"""
        [
          {
            "id": "monthly", "title": "Subscription", "start_at": "2026-10-06 16:00:00.000Z",
            "end_at": "2026-10-07 16:00:00.000Z", "all_day": true, "color": "green",
            "recurrence_frequency": "monthly", "recurrence_interval": 1
          },
          {
            "id": "once", "title": "Glucose test", "start_at": "2026-10-20 16:00:00.000Z",
            "end_at": "2026-10-21 16:00:00.000Z", "all_day": true, "color": "amber",
            "recurrence_frequency": "none"
          }
        ]
        """#).map { event -> AppEvent in
            var event = event
            event.timezone = timezone
            return event
        }

        let snapshot = AgendaWidgetSnapshot(events: events, tasks: [], timezone: timezone, now: now)

        XCTAssertEqual(
            snapshot.items.map(\.firstDayKey),
            ["2026-10-07", "2026-10-21", "2026-11-07"]
        )
        let once = try XCTUnwrap(snapshot.items.first { $0.title == "Glucose test" })
        XCTAssertEqual(once.dayKeys, ["2026-10-21"])
        XCTAssertEqual(once.kind, .event)
        XCTAssertEqual(once.tint, "amber")
        XCTAssertTrue(once.allDay)
    }

    func testKeepsTasksDueWithinTheMonthAndLookahead() throws {
        let tasks = try decode([CalendarTaskDeadline].self, #"""
        [
          {"id": "lastMonth", "project": "p1", "title": "Old", "due_date": "2026-08-15 00:00:00.000Z",
           "expand": {"state": {"category": "active"}}},
          {"id": "earlier", "project": "p1", "title": "Late", "due_date": "2026-10-10 00:00:00.000Z",
           "priority": "high", "expand": {"project": {"name": "Ops"}, "state": {"category": "active"}}},
          {"id": "soon", "project": "p1", "title": "Soon", "due_date": "2026-10-22 00:00:00.000Z",
           "expand": {"project": {"name": "Ops"}, "state": {"category": "pending"}}},
          {"id": "far", "project": "p1", "title": "Far", "due_date": "2027-03-01 00:00:00.000Z",
           "expand": {"state": {"category": "pending"}}}
        ]
        """#)

        let snapshot = AgendaWidgetSnapshot(events: [], tasks: tasks, timezone: timezone, now: now)

        XCTAssertEqual(snapshot.items.map(\.id), ["earlier", "soon"])
        XCTAssertEqual(snapshot.items.first?.detail, "Ops")
        XCTAssertEqual(snapshot.items.first?.tint, "high")
    }

    func testSameItemsIgnoresFetchTime() {
        let first = AgendaWidgetSnapshot(timezone: timezone, items: [], updatedAt: now)
        let second = AgendaWidgetSnapshot(timezone: timezone, items: [], updatedAt: now.addingTimeInterval(60))
        XCTAssertTrue(first.hasSameItems(as: second))
        XCTAssertFalse(first.hasSameItems(as: nil))
    }
}
