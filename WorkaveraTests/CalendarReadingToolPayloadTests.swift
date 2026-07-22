import XCTest
@testable import Workavera

final class CalendarToolPayloadTests: XCTestCase {
    private func json(_ string: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    func testScheduleDecodesDaysEventsAndTasks() throws {
        let output = try json(#"""
        {
          "days": [
            {
              "date": "2026-07-21",
              "events": [
                {
                  "id": "evt-1",
                  "title": "Standup",
                  "allDay": false,
                  "instanceStart": "2026-07-21T09:00:00Z",
                  "instanceEnd": "2026-07-21T09:30:00Z",
                  "location": "Meeting room",
                  "color": "blue",
                  "recurrenceFrequency": "daily"
                }
              ],
              "tasks": [
                {
                  "id": "task-1",
                  "title": "Ship v1",
                  "priority": "high",
                  "dueDate": "2026-07-21",
                  "projectName": "Website",
                  "completed": false
                }
              ]
            }
          ]
        }
        """#)

        let payload = try XCTUnwrap(CalendarToolPayload(toolName: "calendar_get_schedule", output: output))

        XCTAssertEqual(payload.days.count, 1)
        let event = payload.days[0].events[0]
        XCTAssertEqual(event.title, "Standup")
        XCTAssertEqual(event.color, .blue)
        XCTAssertEqual(event.recurrence, .daily)
        XCTAssertNotNil(event.start)
        XCTAssertEqual(event.location, "Meeting room")
        let task = payload.days[0].tasks[0]
        XCTAssertEqual(task.priority, .high)
        XCTAssertFalse(task.completed)
    }

    func testEventFallsBackToStartAtWhenNoInstanceTimes() throws {
        let output = try json(#"""
        {"days":[{"date":"2026-07-21","events":[{"id":"e1","title":"Lunch","startAt":"2026-07-21 12:00:00.000Z","endAt":"2026-07-21 13:00:00.000Z"}],"tasks":[]}]}
        """#)

        let payload = try XCTUnwrap(CalendarToolPayload(toolName: "calendar_get_schedule", output: output))

        XCTAssertNotNil(payload.days[0].events[0].start)
    }

    func testBatchMutationDecodesEnvelopeWithEventTitles() throws {
        let output = try json(#"""
        {
          "ok": true, "total": 2, "succeeded": 2, "failed": 0,
          "results": [
            {"index": 0, "ok": true, "result": {"ok": true, "action": "created", "event": {"id": "e1", "title": "Dentist"}}},
            {"index": 1, "ok": true, "result": {"ok": true, "action": "created", "event": {"id": "e2", "title": "Gym"}}}
          ]
        }
        """#)

        let payload = try XCTUnwrap(CalendarToolPayload(toolName: "calendar_create_event", output: output))

        XCTAssertTrue(payload.isBatchMutation)
        XCTAssertEqual(payload.mutationSucceeded, 2)
        XCTAssertEqual(payload.mutationItems.map(\.title), ["Dentist", "Gym"])
        XCTAssertEqual(payload.mutationItems[0].action, "created")
    }

    func testSingleMutationDecodesEventMutationResult() throws {
        let output = try json(#"{"ok":true,"action":"updated","event":{"id":"e1","title":"Dentist"}}"#)

        let payload = try XCTUnwrap(CalendarToolPayload(toolName: "calendar_update_event", output: output))

        XCTAssertFalse(payload.isBatchMutation)
        XCTAssertEqual(payload.mutationItems.first?.title, "Dentist")
        XCTAssertEqual(payload.mutationItems.first?.action, "updated")
    }

    func testUnknownToolFailsToDecode() throws {
        let output = try json(#"{"days":[]}"#)
        XCTAssertNil(CalendarToolPayload(toolName: "calendar_delete_event", output: output))
        XCTAssertNil(CalendarToolPayload(toolName: "calendar_get_schedule", output: nil))
    }
}

final class ReadingToolPayloadTests: XCTestCase {
    private func json(_ string: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    func testSearchDecodesItemList() throws {
        let output = try json(#"""
        [
          {
            "id": "item-1",
            "title": "Swift Concurrency",
            "url": "https://www.example.com/articles/swift",
            "status": "unread",
            "description": "Deep dive",
            "summary": "A summary",
            "keyPoints": ["Point A", "Point B"],
            "tags": ["swift", "ios"]
          }
        ]
        """#)

        let payload = try XCTUnwrap(ReadingToolPayload(toolName: "reading_search", output: output))

        XCTAssertEqual(payload.items.count, 1)
        let item = payload.items[0]
        XCTAssertEqual(item.title, "Swift Concurrency")
        XCTAssertEqual(item.status, .unread)
        XCTAssertEqual(item.host, "example.com")
        XCTAssertEqual(item.keyPoints, ["Point A", "Point B"])
        XCTAssertEqual(item.tags, ["swift", "ios"])
    }

    func testGetDecodesSingleItem() throws {
        let output = try json(#"{"id":"item-1","title":"A","url":"https://a.com","status":"read"}"#)

        let payload = try XCTUnwrap(ReadingToolPayload(toolName: "reading_get", output: output))

        XCTAssertEqual(payload.items.first?.status, .read)
    }

    func testUpsertDecodesBatchEnvelope() throws {
        let output = try json(#"""
        {
          "ok": false, "total": 2, "succeeded": 1, "failed": 1,
          "results": [
            {"index": 0, "ok": true, "result": {"id": "i1", "title": "Saved"}},
            {"index": 1, "ok": false, "error": "invalid url"}
          ]
        }
        """#)

        let payload = try XCTUnwrap(ReadingToolPayload(toolName: "reading_upsert", output: output))

        XCTAssertTrue(payload.isBatchMutation)
        XCTAssertEqual(payload.mutationSucceeded, 1)
        XCTAssertEqual(payload.mutationItems[0].title, "Saved")
        XCTAssertEqual(payload.mutationItems[1].error, "invalid url")
    }

    func testPlainTextSummarizeErrorIsPreserved() throws {
        let output = JSONValue.string("failed to fetch the article")

        let payload = try XCTUnwrap(ReadingToolPayload(toolName: "reading_summarize", output: output))

        XCTAssertEqual(payload.plainText, "failed to fetch the article")
        XCTAssertTrue(payload.items.isEmpty)
    }

    func testStringEncodedItemDecodesLikeAnObject() throws {
        let output = JSONValue.string(#"{"id":"i1","title":"A","status":"unread"}"#)

        let payload = try XCTUnwrap(ReadingToolPayload(toolName: "reading_summarize", output: output))

        XCTAssertNil(payload.plainText)
        XCTAssertEqual(payload.items.first?.title, "A")
    }

    func testMalformedOutputFailsToDecode() throws {
        let output = try json(#"{"id":"x"}"#)
        XCTAssertNil(ReadingToolPayload(toolName: "reading_search", output: output))
        XCTAssertNil(ReadingToolPayload(toolName: "reading_search", output: nil))
    }
}
