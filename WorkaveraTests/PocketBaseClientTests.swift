import XCTest
@testable import Workavera

final class PocketBaseClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testHTTPErrorPreservesStatusAndFieldDetails() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/collections/users/auth-with-password")
            let body = Data(#"{"message":"Invalid request.","data":{"identity":{"message":"Unknown account."}}}"#.utf8)
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                body
            )
        }

        let client = try makeClient()
        do {
            _ = try await client.authWithPassword(identity: "person@example.com", password: "secret")
            XCTFail("Expected the request to fail")
        } catch let APIError.http(statusCode, message, fieldMessages) {
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(message, "Invalid request.")
            XCTAssertEqual(fieldMessages["identity"], "Unknown account.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreferencesRequestUsesEncodedFilterAndBearerToken() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(
                components.queryItems?.first(where: { $0.name == "filter" })?.value,
                "owner = \"user-1\""
            )
            let body = Data(#"{"items":[{"id":"pref-1","owner":"user-1","theme":"dark","memory_enabled":true,"memory_auto_capture":false}]}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let preferences = try await makeClient().getPreferences(
            ownerID: "user-1",
            token: "token-value"
        )

        XCTAssertEqual(preferences.theme, .dark)
        XCTAssertTrue(preferences.memoryEnabled)
    }

    func testNotificationsDecodePocketBaseFieldsAndPagination() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            XCTAssertEqual(request.url?.path, "/api/collections/notifications/records")
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "page" })?.value, "2")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "sort" })?.value, "-pinned,-created")
            XCTAssertEqual(
                components.queryItems?.first(where: { $0.name == "filter" })?.value,
                "status = \"active\""
            )
            let body = Data(#"{"page":2,"perPage":20,"totalPages":3,"totalItems":41,"items":[{"id":"notice-1","recipient":"user-1","type":"task_due","title":"Task due","body":"Ship the build","data":{},"read_at":"","status":"active","pinned":true,"created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 08:01:00.000Z"}]}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let page = try await makeClient().getNotifications(
            page: 2,
            pageSize: 20,
            token: "token-value"
        )

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.totalItems, 41)
        XCTAssertEqual(page.items.first?.type, .taskDue)
        XCTAssertEqual(page.items.first?.pinned, true)
        XCTAssertEqual(page.items.first?.isRead, false)
    }

    func testDashboardSummaryUsesWebFiltersAndCombinesUpcomingCounts() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )
            XCTAssertEqual(query["page"], "1")
            XCTAssertEqual(query["perPage"], "1")
            XCTAssertEqual(query["fields"], "id")

            let totalItems: Int
            switch request.url?.path {
            case "/api/collections/board_projects/records":
                XCTAssertEqual(query["filter"], "archived = false")
                totalItems = 2
            case "/api/collections/calendar_events/records":
                XCTAssertTrue(query["filter"]?.contains("start_at >=") == true)
                XCTAssertTrue(query["filter"]?.contains("start_at <") == true)
                totalItems = 3
            case "/api/collections/reading_items/records":
                XCTAssertEqual(query["filter"], "status = \"unread\"")
                totalItems = 4
            case "/api/collections/board_tasks/records":
                XCTAssertTrue(query["filter"]?.hasPrefix("state.category != \"completed\"") == true)
                if query["filter"]?.contains("due_date >=") == true {
                    XCTAssertTrue(query["filter"]?.contains("due_date <") == true)
                    totalItems = 5
                } else {
                    totalItems = 7
                }
            default:
                XCTFail("Unexpected dashboard request: \(request.url?.absoluteString ?? "nil")")
                totalItems = 0
            }

            let body = Data("{\"totalItems\":\(totalItems),\"items\":[]}".utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let now = Date(timeIntervalSince1970: 1_784_527_200)
        let summary = try await makeClient().getDashboardSummary(
            now: now,
            token: "token-value"
        )

        XCTAssertEqual(summary.activeProjects, 2)
        XCTAssertEqual(summary.openTasks, 7)
        XCTAssertEqual(summary.nextSevenDays, 8)
        XCTAssertEqual(summary.unreadReading, 4)
        XCTAssertEqual(summary.loadedAt, now)
    }

    func testMarkNotificationReadUsesAuthenticatedBackendEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/notifications/notice-1/read")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"ok":true}"#.utf8)
            )
        }

        try await makeClient().markNotificationRead(id: "notice-1", token: "token-value")
    }

    func testAcceptModelShareUsesNotificationResponseEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/llm/shares/share-1/respond")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let body = try Self.bodyData(from: request)
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: body) as? [String: String],
                ["decision": "accept"]
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"accepted","model":{"id":"model-1"}}"#.utf8)
            )
        }

        let status = try await makeClient().respondToModelShare(
            notificationID: "share-1",
            decision: .accept,
            token: "token-value"
        )

        XCTAssertEqual(status, .accepted)
    }

    func testArchiveNotificationUpdatesStatusAndClearsPin() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/collections/notifications/records/notice-1")
            let body = try Self.bodyData(from: request)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(fields["status"] as? String, "archived")
            XCTAssertEqual(fields["pinned"] as? Bool, false)
            let response = Data(#"{"id":"notice-1","recipient":"user-1","type":"task_due","title":"Task due","body":"Ship the build","data":{},"read_at":"","status":"archived","pinned":false,"created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 08:01:00.000Z"}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let archived = try await makeClient().archiveNotification(id: "notice-1", token: "token-value")

        XCTAssertEqual(archived.status, .archived)
        XCTAssertFalse(archived.pinned)
    }

    func testDeleteNotificationAcceptsEmptySuccessResponse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/collections/notifications/records/notice-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        try await makeClient().deleteNotification(id: "notice-1", token: "token-value")
    }

    func testBoardPageUsesFourProjectsPerPageAndAssemblesRelatedRecords() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )

            let body: Data
            switch request.url?.path {
            case "/api/collections/board_project_preferences/records":
                XCTAssertEqual(query["page"], "2")
                XCTAssertEqual(query["perPage"], "4")
                XCTAssertEqual(query["sort"], "sort_order,id")
                XCTAssertEqual(query["expand"], "project,project.owner")
                XCTAssertEqual(query["filter"], "user = \"user-1\" && project.archived = false")
                body = Data(#"{"page":2,"totalPages":3,"totalItems":9,"items":[{"id":"pref-1","project":"project-1","sort_order":1024,"expand":{"project":{"id":"project-1","name":"Mobile","description":"iOS board","owner":"owner-1","archived":false,"expand":{"owner":{"id":"owner-1","name":"Owner","email":"owner@example.com"}}}}}]}"#.utf8)

            case "/api/collections/board_project_states/records":
                XCTAssertEqual(query["filter"], "project = \"project-1\"")
                XCTAssertEqual(query["sort"], "sort_order")
                body = Data(##"{"items":[{"id":"state-1","project":"project-1","name":"Doing","color":"#3b82f6","category":"active","sort_order":2048}]}"##.utf8)

            case "/api/collections/board_tasks/records":
                XCTAssertEqual(query["filter"], "project = \"project-1\"")
                XCTAssertEqual(query["sort"], "rank")
                body = Data(#"{"items":[{"id":"task-1","project":"project-1","state":"state-1","title":"Connect Board","description":"Use PocketBase records","priority":"high","labels":["label-1"],"assignees":["member-1"],"documents":["document-1","document-2"],"due_date":"2026-07-30 08:00:00.000Z","rank":1024}]}"#.utf8)

            case "/api/collections/board_project_labels/records":
                XCTAssertEqual(query["filter"], "project = \"project-1\"")
                XCTAssertEqual(query["sort"], "name")
                body = Data(##"{"items":[{"id":"label-1","project":"project-1","name":"API","color":"#ef4444"}]}"##.utf8)

            case "/api/collections/board_project_members/records":
                XCTAssertEqual(query["filter"], "project = \"project-1\"")
                XCTAssertEqual(query["sort"], "created")
                XCTAssertEqual(query["expand"], "user")
                body = Data(#"{"items":[{"id":"membership-1","project":"project-1","user":"member-1","expand":{"user":{"id":"member-1","name":"Developer","email":"developer@example.com"}}}]}"#.utf8)

            default:
                XCTFail("Unexpected Board request: \(request.url?.absoluteString ?? "nil")")
                body = Data(#"{"items":[]}"#.utf8)
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let page = try await makeClient().getBoardPage(
            userID: "user-1",
            page: 2,
            pageSize: 4,
            token: "token-value"
        )

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.totalItems, 9)
        let project = try XCTUnwrap(page.projects.first)
        XCTAssertEqual(project.name, "Mobile")
        XCTAssertEqual(project.members.map(\.name), ["Owner", "Developer"])
        XCTAssertEqual(project.labels.map(\.name), ["API"])
        let state = try XCTUnwrap(project.states.first)
        XCTAssertEqual(state.category, .active)
        let task = try XCTUnwrap(state.tasks.first)
        XCTAssertEqual(task.title, "Connect Board")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.labels.map(\.id), ["label-1"])
        XCTAssertEqual(task.assignees.map(\.name), ["Developer"])
        XCTAssertEqual(task.documentCount, 2)
        XCTAssertNotNil(task.dueDate)
    }

    func testMoveBoardTaskUpdatesStateAndRank() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/collections/board_tasks/records/task-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let fields = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
            )
            XCTAssertEqual(fields["state"] as? String, "state-2")
            XCTAssertEqual(fields["rank"] as? Double, 3072)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"task-1","state":"state-2","rank":3072}"#.utf8)
            )
        }

        let moved = try await makeClient().moveBoardTask(
            id: "task-1",
            stateID: "state-2",
            rank: 3072,
            token: "token-value"
        )

        XCTAssertEqual(moved.id, "task-1")
        XCTAssertEqual(moved.state, "state-2")
        XCTAssertEqual(moved.rank, 3072)
    }

    func testUpdateBoardTaskPriorityUsesAuthenticatedPatch() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/collections/board_tasks/records/task-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let fields = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: String]
            )
            XCTAssertEqual(fields, ["priority": "urgent"])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"task-1","priority":"urgent"}"#.utf8)
            )
        }

        let updated = try await makeClient().updateBoardTaskPriority(
            id: "task-1",
            priority: .urgent,
            token: "token-value"
        )

        XCTAssertEqual(updated.id, "task-1")
        XCTAssertEqual(updated.priority, .urgent)
    }

    func testUpdateBoardTaskDueDateUsesPocketBaseDateField() async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dueDate = try XCTUnwrap(formatter.date(from: "2026-07-21T09:30:00.000Z"))

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/collections/board_tasks/records/task-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let fields = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: String]
            )
            XCTAssertEqual(fields, ["due_date": "2026-07-21T09:30:00.000Z"])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"task-1","due_date":"2026-07-21 09:30:00.000Z"}"#.utf8)
            )
        }

        let updated = try await makeClient().updateBoardTaskDueDate(
            id: "task-1",
            dueDate: dueDate,
            token: "token-value"
        )

        XCTAssertEqual(updated.id, "task-1")
        XCTAssertEqual(updated.dueDate, "2026-07-21 09:30:00.000Z")
    }

    func testClearBoardTaskDueDateSendsEmptyDateField() async throws {
        MockURLProtocol.handler = { request in
            let fields = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: String]
            )
            XCTAssertEqual(fields, ["due_date": ""])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"task-1","due_date":""}"#.utf8)
            )
        }

        let updated = try await makeClient().updateBoardTaskDueDate(
            id: "task-1",
            dueDate: nil,
            token: "token-value"
        )

        XCTAssertEqual(updated.dueDate, "")
    }

    func testNotificationRealtimeHandshakeSubscribesAndDecodesCreateEvent() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/realtime")
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(fields["clientId"] as? String, "client-1")
                XCTAssertEqual(fields["subscriptions"] as? [String], ["notifications/*"])
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            let body = Data(#"""
            id:client-1
            event:PB_CONNECT
            data:{"clientId":"client-1"}

            id:client-1
            event:notifications/*
            data:{"action":"create","record":{"id":"notice-live","recipient":"user-1","type":"model_share","title":"Live model share","body":"Review it","data":{"senderName":"Alice","modelName":"GPT","shareStatus":"pending"},"read_at":"","status":"active","pinned":false,"created":"2026-07-20 09:00:00.000Z","updated":"2026-07-20 09:00:00.000Z"}}

            """#.utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                body
            )
        }

        let stream = try makeClient().notificationRealtimeEvents(token: "token-value")
        var iterator = stream.makeAsyncIterator()
        let event = try await iterator.next()

        XCTAssertEqual(event?.action, .create)
        XCTAssertEqual(event?.record.id, "notice-live")
        XCTAssertEqual(event?.record.data.shareStatus, .pending)
    }

    private func makeClient() throws -> PocketBaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return try PocketBaseClient(
            baseURLString: "https://example.com",
            allowInsecureHTTP: false,
            session: URLSession(configuration: configuration)
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
