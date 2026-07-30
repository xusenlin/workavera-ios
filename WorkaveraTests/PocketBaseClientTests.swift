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

    func testContactsCombineUsersWithFavoriteRecordsAndAvatarURLs() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let body: Data
            switch request.url?.path {
            case "/api/collections/users/records":
                body = Data(#"{"page":1,"totalPages":1,"items":[{"id":"user-2","collectionId":"_pb_users_auth_","name":"Ada","email":"ada@example.com","avatar":"ada.png","phone":"","title":"Designer","bio":"Calm interfaces","status":"online"}]}"#.utf8)
            case "/api/collections/contact_favorites/records":
                let components = try XCTUnwrap(
                    URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                )
                XCTAssertEqual(
                    components.queryItems?.first(where: { $0.name == "filter" })?.value,
                    "owner = \"user-1\""
                )
                body = Data(#"{"page":1,"totalPages":1,"items":[{"id":"favorite-1","owner":"user-1","contact":"user-2"}]}"#.utf8)
            default:
                XCTFail("Unexpected contacts request: \(request.url?.absoluteString ?? "nil")")
                body = Data(#"{"items":[]}"#.utf8)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let snapshot = try await makeClient().getContacts(ownerID: "user-1", token: "token-value")

        XCTAssertEqual(snapshot.contacts.map(\.id), ["user-2"])
        XCTAssertEqual(snapshot.contacts.first?.status, .online)
        XCTAssertEqual(snapshot.contacts.first?.isFavorite, true)
        XCTAssertEqual(snapshot.contacts.first?.avatarURL?.path, "/api/files/_pb_users_auth_/user-2/ada.png")
        XCTAssertEqual(snapshot.favoriteRecordIDs["user-2"], "favorite-1")
    }

    func testContactFavoriteCreateAndDeleteUseRelationCollection() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            XCTAssertEqual(request.url?.path.hasPrefix("/api/collections/contact_favorites/records"), true)
            if request.httpMethod == "POST" {
                let body = try Self.bodyData(from: request)
                XCTAssertEqual(
                    try JSONSerialization.jsonObject(with: body) as? [String: String],
                    ["owner": "user-1", "contact": "user-2"]
                )
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"id":"favorite-1","owner":"user-1","contact":"user-2"}"#.utf8)
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/collections/contact_favorites/records/favorite-1")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let client = try makeClient()

        let favorite = try await client.createContactFavorite(
            ownerID: "user-1",
            contactID: "user-2",
            token: "token-value"
        )
        try await client.deleteContactFavorite(id: favorite.id, token: "token-value")

        XCTAssertEqual(favorite.id, "favorite-1")
    }

    func testReadingPageUsesBackendFiltersPaginationAndUnreadCount() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/collections/reading_items/records")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )
            let body: Data
            if query["perPage"] == "1" {
                XCTAssertEqual(query["filter"], "status = \"unread\"")
                body = Data(#"{"page":1,"totalPages":1,"totalItems":3,"items":[]}"#.utf8)
            } else {
                XCTAssertEqual(query["page"], "2")
                XCTAssertEqual(query["perPage"], "6")
                XCTAssertEqual(query["sort"], "-pinned,-updated")
                XCTAssertTrue(query["filter"]?.contains("status != \"archived\"") == true)
                XCTAssertTrue(query["filter"]?.contains("pinned = true") == true)
                XCTAssertTrue(query["filter"]?.contains("title ~ \"Swift\"") == true)
                body = Data(#"{"page":2,"totalPages":4,"totalItems":19,"items":[{"id":"reading-1","owner":"user-1","project":"","url":"https://example.com/swift","title":"Swift Concurrency","description":"Actors","tags":["swift"],"status":"unread","pinned":true,"summary":"Summary","key_points":["Use actors"],"summary_language":"English","created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 09:00:00.000Z"}]}"#.utf8)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let page = try await makeClient().getReadingPage(
            filter: .pinned,
            page: 2,
            pageSize: 6,
            query: "Swift",
            token: "token-value"
        )

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 4)
        XCTAssertEqual(page.totalItems, 19)
        XCTAssertEqual(page.unreadCount, 3)
        XCTAssertEqual(page.items.first?.host, "example.com")
        XCTAssertEqual(page.items.first?.pinned, true)
    }

    func testCreateReadingItemSendsOwnerAndRealCollectionFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/collections/reading_items/records")
            let body = try Self.bodyData(from: request)
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(payload["owner"] as? String, "user-1")
            XCTAssertEqual(payload["url"] as? String, "https://example.com/article")
            XCTAssertEqual(payload["title"] as? String, "Article")
            XCTAssertEqual(payload["status"] as? String, "unread")
            XCTAssertEqual(payload["tags"] as? [String], ["ios", "swift"])
            let response = Data(#"{"id":"reading-1","owner":"user-1","project":"","url":"https://example.com/article","title":"Article","description":"Description","tags":["ios","swift"],"status":"unread","pinned":false,"created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 08:00:00.000Z"}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let item = try await makeClient().createReadingItem(
            ownerID: "user-1",
            input: ReadingItemInput(
                url: "https://example.com/article",
                title: "Article",
                description: "Description",
                tags: ["ios", "swift"]
            ),
            token: "token-value"
        )

        XCTAssertEqual(item.id, "reading-1")
        XCTAssertEqual(item.status, .unread)
    }

    func testReadingPinUsesProtectedBackendEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/reading/items/reading-1/pin")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let body = try Self.bodyData(from: request)
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: body) as? [String: Bool],
                ["pinned": true]
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"ok":true}"#.utf8)
            )
        }

        try await makeClient().setReadingPinned(
            id: "reading-1",
            pinned: true,
            token: "token-value"
        )
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
                "status = \"active\" && (title ~ \"Build \\\"26\\\"\" || body ~ \"Build \\\"26\\\"\")"
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
            query: "  Build \"26\"  ",
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
                XCTAssertTrue(query["filter"]?.contains("archived = false") == true)
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

    func testDocsFolderPageMatchesWebFiltersSearchAndPagination() async throws {
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
            case "/api/docs-pinned":
                XCTAssertEqual(query["query"], "roadmap")
                body = Data(#"[{"id":"doc-1","title":"Roadmap","kind":"markdown","ownerId":"user-1","folderId":"folder-1","status":"draft","revision":3,"updated":"2026-07-20 08:00:00.000Z"}]"#.utf8)

            case "/api/collections/doc_folders/records":
                XCTAssertEqual(query["page"], "1")
                XCTAssertEqual(query["perPage"], "200")
                XCTAssertNil(query["filter"])
                XCTAssertEqual(query["sort"], "name")
                body = Data(#"{"page":1,"totalPages":1,"items":[{"id":"folder-1","name":"Planning"}]}"#.utf8)

            case "/api/collections/board_project_preferences/records":
                XCTAssertEqual(query["filter"], "user = \"user-1\" && project.archived = false")
                XCTAssertEqual(query["sort"], "sort_order,id")
                XCTAssertEqual(query["expand"], "project")
                body = Data(#"{"page":1,"totalPages":1,"items":[{"id":"pref-1","project":"project-1","sort_order":1024,"expand":{"project":{"id":"project-1","name":"Mobile","owner":"owner-1","archived":false}}}]}"#.utf8)

            case "/api/collections/docs/records":
                XCTAssertEqual(query["page"], "2")
                XCTAssertEqual(query["perPage"], "15")
                XCTAssertEqual(query["sort"], "-updated")
                XCTAssertEqual(
                    query["filter"],
                    "status = \"draft\" && (title ~ \"roadmap\" || content ~ \"roadmap\") && project = \"\" && folder = \"folder-1\""
                )
                XCTAssertTrue(query["fields"]?.contains("last_edited_by") == true)
                body = Data(#"{"page":2,"perPage":15,"totalPages":3,"totalItems":31,"items":[{"id":"doc-1","title":"Roadmap","kind":"markdown","owner":"user-1","project":"","folder":"folder-1","status":"draft","revision":3,"last_edited_by":"user-1","created":"2026-07-19 08:00:00.000Z","updated":"2026-07-20 08:00:00.000Z"}]}"#.utf8)

            default:
                XCTFail("Unexpected Docs request: \(request.url?.absoluteString ?? "nil")")
                body = Data(#"{"items":[]}"#.utf8)
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let page = try await makeClient().getDocsPage(
            userID: "user-1",
            view: .folder("folder-1"),
            page: 2,
            pageSize: 15,
            query: "roadmap",
            token: "token-value"
        )

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.totalItems, 31)
        XCTAssertEqual(page.folders, [DocumentFolder(id: "folder-1", name: "Planning")])
        XCTAssertEqual(page.projects, [DocumentProject(id: "project-1", name: "Mobile")])
        let document = try XCTUnwrap(page.documents.first)
        XCTAssertEqual(document.title, "Roadmap")
        XCTAssertEqual(document.folderID, "folder-1")
        XCTAssertTrue(document.pinned)
    }

    func testDocsReadOnlyDetailVersionsAndPinUseBackendRoutes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let body: Data
            switch request.url?.path {
            case "/api/collections/docs/records/doc-1":
                XCTAssertEqual(request.httpMethod, "GET")
                body = Data(#"{"id":"doc-1","title":"Architecture","kind":"html","content":"<h1>System</h1>","owner":"user-1","project":"project-1","folder":"","status":"draft","revision":4,"last_edited_by":"user-2","created":"2026-07-18 08:00:00.000Z","updated":"2026-07-20 08:00:00.000Z"}"#.utf8)

            case "/api/docs/doc-1/versions":
                XCTAssertEqual(request.httpMethod, "GET")
                body = Data(#"[{"id":"version-4","revision":4,"title":"Architecture","createdBy":"user-2","source":"update","created":"2026-07-20 08:00:00.000Z"}]"#.utf8)

            case "/api/docs/doc-1/versions/4":
                XCTAssertEqual(request.httpMethod, "GET")
                body = Data(#"{"id":"version-4","revision":4,"title":"Architecture","content":"<h1>System</h1>","createdBy":"user-2","source":"update","created":"2026-07-20 08:00:00.000Z"}"#.utf8)

            case "/api/docs/doc-1/pin":
                XCTAssertEqual(request.httpMethod, "POST")
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Bool]
                )
                XCTAssertEqual(fields, ["pinned": true])
                body = Data(#"{"pinned":true}"#.utf8)

            default:
                XCTFail("Unexpected Docs request: \(request.url?.absoluteString ?? "nil")")
                body = Data(#"{}"#.utf8)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let client = try makeClient()
        let document = try await client.getDocument(id: "doc-1", pinned: false, token: "token-value")
        XCTAssertEqual(document.kind, .html)
        XCTAssertEqual(document.content, "<h1>System</h1>")
        XCTAssertEqual(document.projectID, "project-1")

        let versions = try await client.getDocumentVersions(id: "doc-1", token: "token-value")
        XCTAssertEqual(versions.first?.revision, 4)
        XCTAssertNil(versions.first?.content)

        let version = try await client.getDocumentVersion(
            id: "doc-1",
            revision: 4,
            token: "token-value"
        )
        XCTAssertEqual(version.content, "<h1>System</h1>")

        try await client.setDocumentPinned(id: "doc-1", pinned: true, token: "token-value")
    }

    func testAPIKeysListCreateAndRevokeUseAuthenticatedBackendRoutes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let body: Data
            switch request.url?.path {
            case "/api/collections/api_keys/records":
                XCTAssertEqual(request.httpMethod, "GET")
                let components = try XCTUnwrap(
                    URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                )
                let query = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
                )
                XCTAssertEqual(query["page"], "1")
                XCTAssertEqual(query["perPage"], "200")
                XCTAssertEqual(query["sort"], "-created")
                XCTAssertNil(query["filter"])
                body = Data(#"{"page":1,"totalPages":1,"items":[{"id":"key-1","name":"Claude Code","prefix":"sk-wa-1234","allow_destructive":true,"expires":"2026-08-20 08:00:00.000Z","last_used":"2026-07-20 08:00:00.000Z","created":"2026-07-19 08:00:00.000Z"}]}"#.utf8)

            case "/api/apikeys":
                XCTAssertEqual(request.httpMethod, "POST")
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request))
                        as? [String: Any]
                )
                XCTAssertEqual(fields["name"] as? String, "Cursor on laptop")
                XCTAssertEqual(fields["allowDestructive"] as? Bool, false)
                let expires = try XCTUnwrap(fields["expires"] as? String)
                let expirationFormatter = ISO8601DateFormatter()
                expirationFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                XCTAssertNotNil(expirationFormatter.date(from: expires))
                body = Data(#"{"id":"key-2","key":"sk-wa-secret","prefix":"sk-wa-secr","name":"Cursor on laptop","allowDestructive":false}"#.utf8)

            case "/api/collections/api_keys/records/key-1":
                XCTAssertEqual(request.httpMethod, "DELETE")
                body = Data()

            default:
                XCTFail("Unexpected API key request: \(request.url?.absoluteString ?? "nil")")
                body = Data(#"{}"#.utf8)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let client = try makeClient()
        let keys = try await client.getAPIKeys(token: "token-value")
        let key = try XCTUnwrap(keys.first)
        XCTAssertEqual(key.name, "Claude Code")
        XCTAssertEqual(key.prefix, "sk-wa-1234")
        XCTAssertTrue(key.allowsDestructiveActions)
        XCTAssertNotNil(key.expiresAt)
        XCTAssertNotNil(key.lastUsedAt)

        let created = try await client.createAPIKey(
            name: "Cursor on laptop",
            expiration: .thirtyDays,
            allowsDestructiveActions: false,
            token: "token-value"
        )
        XCTAssertEqual(created.key, "sk-wa-secret")
        XCTAssertFalse(created.allowsDestructiveActions)

        try await client.revokeAPIKey(id: "key-1", token: "token-value")
    }

    func testAPIKeyExpirationSupportsNeverAndFixedDurations() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = try XCTUnwrap(formatter.date(from: "2026-07-20T08:00:00.000Z"))

        XCTAssertEqual(APIKeyExpiration.never.requestValue(now: now), "")
        XCTAssertEqual(
            APIKeyExpiration.sevenDays.requestValue(now: now),
            "2026-07-27T08:00:00.000Z"
        )
        XCTAssertEqual(
            APIKeyExpiration.oneYear.requestValue(now: now),
            "2027-07-20T08:00:00.000Z"
        )
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
                body = Data(#"{"page":2,"totalPages":3,"totalItems":9,"items":[{"id":"pref-1","project":"project-1","sort_order":1024,"expand":{"project":{"id":"project-1","name":"Mobile","description":"iOS board","owner":"owner-1","archived":false,"expand":{"owner":{"id":"owner-1","collectionId":"users","name":"Owner","email":"owner@example.com","avatar":"owner.png"}}}}}]}"#.utf8)

            case "/api/collections/board_project_states/records":
                XCTAssertEqual(query["filter"], "project = \"project-1\"")
                XCTAssertEqual(query["sort"], "sort_order")
                body = Data(##"{"items":[{"id":"state-1","project":"project-1","name":"Doing","color":"#3b82f6","category":"active","sort_order":2048}]}"##.utf8)

            case "/api/collections/board_tasks/records":
                XCTAssertEqual(query["filter"], "(project = \"project-1\") && archived = false")
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
                body = Data(#"{"items":[{"id":"membership-1","project":"project-1","user":"member-1","expand":{"user":{"id":"member-1","collectionId":"users","name":"Developer","email":"developer@example.com","avatar":"developer.svg"}}}]}"#.utf8)

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
        XCTAssertEqual(
            project.members.map(\.avatarURL?.absoluteString),
            [
                "https://example.com/api/files/users/owner-1/owner.png",
                "https://example.com/api/files/users/member-1/developer.svg",
            ]
        )
        XCTAssertEqual(project.labels.map(\.name), ["API"])
        let state = try XCTUnwrap(project.states.first)
        XCTAssertEqual(state.category, .active)
        let task = try XCTUnwrap(state.tasks.first)
        XCTAssertEqual(task.title, "Connect Board")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.labels.map(\.id), ["label-1"])
        XCTAssertEqual(task.assignees.map(\.name), ["Developer"])
        XCTAssertEqual(
            task.assignees.first?.avatarURL?.absoluteString,
            "https://example.com/api/files/users/member-1/developer.svg"
        )
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

    func testArchiveBoardTaskUsesAuthenticatedPatch() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/collections/board_tasks/records/task-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let fields = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Bool]
            )
            XCTAssertEqual(fields, ["archived": true])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"task-1","archived":true}"#.utf8)
            )
        }

        let archived = try await makeClient().archiveBoardTask(
            id: "task-1",
            token: "token-value"
        )

        XCTAssertEqual(archived.id, "task-1")
        XCTAssertTrue(archived.archived)
    }

    func testLLMModelManagementAndSharingUseProtectedRoutes() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let response: Data

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/llm/models"):
                response = Data(#"[{"id":"model-1","name":"Primary GPT","modelId":"gpt-4o","baseUrl":"https://api.openai.com/v1","protocol":"openai","maxOutputTokens":16384,"maxContextTokens":256000,"isDefault":true,"sharedFrom":"","sharedFromName":"","hasApiKey":true,"created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 08:00:00.000Z"}]"#.utf8)

            case ("POST", "/api/llm/models"):
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(fields["name"] as? String, "Claude")
                XCTAssertEqual(fields["modelId"] as? String, "claude-sonnet-4")
                XCTAssertEqual(fields["baseUrl"] as? String, "https://api.anthropic.com")
                XCTAssertEqual(fields["protocol"] as? String, "anthropic")
                XCTAssertEqual(fields["maxOutputTokens"] as? Int, 32_768)
                XCTAssertEqual(fields["maxContextTokens"] as? Int, 200_000)
                XCTAssertEqual(fields["apiKey"] as? String, "secret-value")
                response = Data(#"{"id":"model-2","name":"Claude","modelId":"claude-sonnet-4","baseUrl":"https://api.anthropic.com","protocol":"anthropic","maxOutputTokens":32768,"maxContextTokens":200000,"isDefault":false,"sharedFrom":"","sharedFromName":"","hasApiKey":true,"created":"2026-07-20 09:00:00.000Z","updated":"2026-07-20 09:00:00.000Z"}"#.utf8)

            case ("PATCH", "/api/llm/models/model-2"):
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(fields["name"] as? String, "Claude Updated")
                XCTAssertNil(fields["apiKey"])
                response = Data(#"{"id":"model-2","name":"Claude Updated","modelId":"claude-sonnet-4","baseUrl":"https://api.anthropic.com","protocol":"anthropic","maxOutputTokens":32768,"maxContextTokens":200000,"isDefault":false,"sharedFrom":"","sharedFromName":"","hasApiKey":true,"created":"2026-07-20 09:00:00.000Z","updated":"2026-07-20 10:00:00.000Z"}"#.utf8)

            case ("POST", "/api/llm/models/model-2/default"):
                response = Data(#"{"id":"model-2","name":"Claude Updated","modelId":"claude-sonnet-4","baseUrl":"https://api.anthropic.com","protocol":"anthropic","maxOutputTokens":32768,"maxContextTokens":200000,"isDefault":true,"sharedFrom":"","sharedFromName":"","hasApiKey":true,"created":"2026-07-20 09:00:00.000Z","updated":"2026-07-20 10:00:00.000Z"}"#.utf8)

            case ("GET", "/api/llm/share-targets"):
                response = Data(#"[{"id":"user-2","name":"Ada"},{"id":"user-3","name":"Grace"}]"#.utf8)

            case ("POST", "/api/llm/models/model-2/share"):
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: [String]]
                )
                XCTAssertEqual(fields["userIds"], ["user-2", "user-3"])
                response = Data(#"{"shared":2}"#.utf8)

            case ("DELETE", "/api/llm/models/model-2"):
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            default:
                XCTFail("Unexpected LLM request: \(request.httpMethod ?? "nil") \(request.url?.absoluteString ?? "nil")")
                response = Data()
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let client = try makeClient()
        let listed = try await client.getLLMModels(token: "token-value")
        XCTAssertEqual(listed.first?.name, "Primary GPT")
        XCTAssertEqual(listed.first?.protocolType, .openAI)
        XCTAssertEqual(listed.first?.hasAPIKey, true)

        let createInput = LLMModelInput(
            name: "Claude",
            modelID: "claude-sonnet-4",
            baseURL: "https://api.anthropic.com",
            protocolType: .anthropic,
            maxOutputTokens: 32_768,
            maxContextTokens: 200_000,
            apiKey: "secret-value"
        )
        let created = try await client.createLLMModel(input: createInput, token: "token-value")
        XCTAssertEqual(created.id, "model-2")

        let updateInput = LLMModelInput(
            name: "Claude Updated",
            modelID: createInput.modelID,
            baseURL: createInput.baseURL,
            protocolType: createInput.protocolType,
            maxOutputTokens: createInput.maxOutputTokens,
            maxContextTokens: createInput.maxContextTokens,
            apiKey: nil
        )
        let updated = try await client.updateLLMModel(
            id: created.id,
            input: updateInput,
            token: "token-value"
        )
        XCTAssertEqual(updated.name, "Claude Updated")

        let defaultModel = try await client.setDefaultLLMModel(id: created.id, token: "token-value")
        XCTAssertTrue(defaultModel.isDefault)

        let targets = try await client.getLLMShareTargets(token: "token-value")
        XCTAssertEqual(targets.map(\.name), ["Ada", "Grace"])
        let shared = try await client.shareLLMModel(
            id: created.id,
            userIDs: targets.map(\.id),
            token: "token-value"
        )
        XCTAssertEqual(shared, 2)
        try await client.deleteLLMModel(id: created.id, token: "token-value")
    }

    func testSavedMemoriesCRUDUsesChatMemoriesContract() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            XCTAssertTrue(request.url?.path.hasPrefix("/api/collections/chat_memories/records") == true)

            let response: Data
            switch request.httpMethod {
            case "GET":
                let components = try XCTUnwrap(
                    URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                )
                let query = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
                )
                XCTAssertEqual(request.url?.path, "/api/collections/chat_memories/records")
                XCTAssertEqual(query["page"], "1")
                XCTAssertEqual(query["perPage"], "200")
                XCTAssertEqual(query["sort"], "-updated")
                XCTAssertNil(query["filter"])
                response = Data(#"{"page":1,"totalPages":1,"items":[{"id":"memory-1","owner":"user-1","category":"preference","content":"Prefer concise answers.","active":true,"origin":"explicit","source_conversation":"conversation-1","source_message":"message-1","created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 09:00:00.000Z"}]}"#.utf8)

            case "POST":
                XCTAssertEqual(request.url?.path, "/api/collections/chat_memories/records")
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: String]
                )
                XCTAssertEqual(fields, ["category": "goal", "content": "Ship the app."])
                response = Data(#"{"id":"memory-2","owner":"user-1","category":"goal","content":"Ship the app.","active":true,"origin":"manual","source_conversation":"","source_message":"","created":"2026-07-20 10:00:00.000Z","updated":"2026-07-20 10:00:00.000Z"}"#.utf8)

            case "PATCH":
                XCTAssertEqual(request.url?.path, "/api/collections/chat_memories/records/memory-1")
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                if let active = fields["active"] as? Bool {
                    XCTAssertFalse(active)
                    XCTAssertEqual(fields.count, 1)
                    response = Data(#"{"id":"memory-1","owner":"user-1","category":"preference","content":"Prefer concise answers.","active":false,"origin":"explicit","source_conversation":"conversation-1","source_message":"message-1","created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 11:00:00.000Z"}"#.utf8)
                } else {
                    XCTAssertEqual(fields["category"] as? String, "constraint")
                    XCTAssertEqual(fields["content"] as? String, "Do not send email without approval.")
                    XCTAssertEqual(fields.count, 2)
                    response = Data(#"{"id":"memory-1","owner":"user-1","category":"constraint","content":"Do not send email without approval.","active":true,"origin":"explicit","source_conversation":"conversation-1","source_message":"message-1","created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 10:30:00.000Z"}"#.utf8)
                }

            case "DELETE":
                XCTAssertEqual(request.url?.path, "/api/collections/chat_memories/records/memory-1")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            default:
                XCTFail("Unexpected saved memory method: \(request.httpMethod ?? "nil")")
                response = Data()
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let client = try makeClient()
        let memories = try await client.getSavedMemories(token: "token-value")
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].category, .preference)
        XCTAssertEqual(memories[0].origin, .explicit)
        XCTAssertEqual(memories[0].sourceConversationID, "conversation-1")

        let created = try await client.createSavedMemory(
            category: .goal,
            content: "Ship the app.",
            token: "token-value"
        )
        XCTAssertEqual(created.category, .goal)
        XCTAssertEqual(created.origin, .manual)
        XCTAssertNil(created.sourceConversationID)

        let updated = try await client.updateSavedMemory(
            id: "memory-1",
            category: .constraint,
            content: "Do not send email without approval.",
            token: "token-value"
        )
        XCTAssertEqual(updated.category, .constraint)
        XCTAssertEqual(updated.content, "Do not send email without approval.")

        let disabled = try await client.setSavedMemoryActive(
            id: "memory-1",
            active: false,
            token: "token-value"
        )
        XCTAssertFalse(disabled.active)

        try await client.deleteSavedMemory(id: "memory-1", token: "token-value")
    }

    func testCalendarSnapshotAndEventCRUDMatchWebContract() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )
            let response: Data

            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/configs/system"):
                response = Data(#"{"timezone":"Asia/Shanghai"}"#.utf8)

            case ("GET", "/api/collections/calendar_events/records"):
                XCTAssertEqual(query["page"], "1")
                XCTAssertEqual(query["perPage"], "200")
                XCTAssertEqual(query["sort"], "start_at")
                XCTAssertNil(query["filter"])
                response = Data(#"{"page":1,"totalPages":1,"items":[{"id":"event-1","owner":"user-1","title":"Weekly planning","description":"Plan the next sprint","start_at":"2026-07-20 01:00:00.000Z","end_at":"2026-07-20 02:00:00.000Z","all_day":false,"timezone":"UTC","location":"Room 3","color":"purple","recurrence_frequency":"weekly","recurrence_interval":1,"reminder_minutes_before":10}]}"#.utf8)

            case ("GET", "/api/collections/board_tasks/records"):
                XCTAssertEqual(query["page"], "1")
                XCTAssertEqual(query["perPage"], "200")
                XCTAssertEqual(
                    query["filter"],
                    "due_date != \"\" && archived = false && assignees.id ?= \"user-1\""
                )
                XCTAssertEqual(query["sort"], "due_date")
                XCTAssertEqual(query["expand"], "project,state")
                response = Data(#"{"page":1,"totalPages":1,"items":[{"id":"task-1","project":"project-1","title":"Ship iOS","description":"Release build","priority":"urgent","due_date":"2026-07-21 00:00:00.000Z","expand":{"project":{"name":"Mobile"},"state":{"category":"active"}}}]}"#.utf8)

            case ("POST", "/api/collections/calendar_events/records"):
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(fields["owner"] as? String, "user-1")
                XCTAssertEqual(fields["title"] as? String, "Design review")
                XCTAssertEqual(fields["start_at"] as? String, "2026-07-21T01:00:00.000Z")
                XCTAssertEqual(fields["end_at"] as? String, "2026-07-21T02:00:00.000Z")
                XCTAssertEqual(fields["recurrence_frequency"] as? String, "none")
                XCTAssertEqual(fields["recurrence_interval"] as? Int, 1)
                XCTAssertEqual(fields["reminder_minutes_before"] as? Int, 30)
                response = Data(#"{"id":"event-2","owner":"user-1","title":"Design review","description":"","start_at":"2026-07-21 01:00:00.000Z","end_at":"2026-07-21 02:00:00.000Z","all_day":false,"timezone":"Asia/Shanghai","location":"","color":"blue","recurrence_frequency":"none","recurrence_interval":1,"reminder_minutes_before":30}"#.utf8)

            case ("PATCH", "/api/collections/calendar_events/records/event-2"):
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertNil(fields["owner"])
                XCTAssertEqual(fields["title"] as? String, "Updated design review")
                XCTAssertEqual(fields["timezone"] as? String, "Asia/Shanghai")
                response = Data(#"{"id":"event-2","owner":"user-1","title":"Updated design review","description":"","start_at":"2026-07-21 01:00:00.000Z","end_at":"2026-07-21 02:00:00.000Z","all_day":false,"timezone":"Asia/Shanghai","location":"","color":"blue","recurrence_frequency":"none","recurrence_interval":1,"reminder_minutes_before":30}"#.utf8)

            case ("DELETE", "/api/collections/calendar_events/records/event-2"):
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            default:
                XCTFail("Unexpected Calendar request: \(request.httpMethod ?? "nil") \(request.url?.absoluteString ?? "nil")")
                response = Data()
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                response
            )
        }

        let client = try makeClient()
        let snapshot = try await client.getCalendarSnapshot(
            userID: "user-1",
            token: "token-value"
        )
        XCTAssertEqual(snapshot.timezone, "Asia/Shanghai")
        XCTAssertEqual(snapshot.events.first?.timezone, "Asia/Shanghai")
        XCTAssertEqual(snapshot.events.first?.recurrenceFrequency, .weekly)
        XCTAssertEqual(snapshot.events.first?.reminder, .tenMinutes)
        XCTAssertEqual(snapshot.tasks.first?.projectName, "Mobile")
        XCTAssertEqual(snapshot.tasks.first?.dueDate, "2026-07-21")
        XCTAssertEqual(snapshot.tasks.first?.completed, false)

        let selectedDay = try XCTUnwrap(CalendarDate.parse("2026-07-27T00:00:00+08:00"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: snapshot.timezone))
        let occurrence = try XCTUnwrap(snapshot.events.first?.occurrences(
            overlapping: selectedDay,
            calendar: calendar
        ).first)
        XCTAssertEqual(CalendarDate.string(from: occurrence.startAt), "2026-07-27T01:00:00.000Z")

        let start = try XCTUnwrap(CalendarDate.parse("2026-07-21T01:00:00Z"))
        let end = try XCTUnwrap(CalendarDate.parse("2026-07-21T02:00:00Z"))
        let input = CalendarEventInput(
            title: "Design review",
            description: "",
            startAt: start,
            endAt: end,
            allDay: false,
            timezone: "Asia/Shanghai",
            location: "",
            color: .blue,
            recurrenceFrequency: .none,
            recurrenceInterval: 1,
            reminder: .thirtyMinutes
        )
        let created = try await client.createCalendarEvent(
            ownerID: "user-1",
            input: input,
            token: "token-value"
        )
        XCTAssertEqual(created.id, "event-2")

        let updatedInput = CalendarEventInput(
            title: "Updated design review",
            description: input.description,
            startAt: input.startAt,
            endAt: input.endAt,
            allDay: input.allDay,
            timezone: input.timezone,
            location: input.location,
            color: input.color,
            recurrenceFrequency: input.recurrenceFrequency,
            recurrenceInterval: input.recurrenceInterval,
            reminder: input.reminder
        )
        let updated = try await client.updateCalendarEvent(
            id: created.id,
            input: updatedInput,
            token: "token-value"
        )
        XCTAssertEqual(updated.title, "Updated design review")
        try await client.deleteCalendarEvent(id: created.id, token: "token-value")
    }

    func testCalendarRealtimeSubscribesToEventsAndTaskDeadlines() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/realtime")
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(fields["clientId"] as? String, "calendar-client")
                XCTAssertEqual(
                    Set(fields["subscriptions"] as? [String] ?? []),
                    Set(["calendar_events/*", "board_tasks/*"])
                )
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            let body = Data(#"""
            id:calendar-client
            event:PB_CONNECT
            data:{"clientId":"calendar-client"}

            id:calendar-client
            event:board_tasks/*
            data:{"action":"update","record":{"id":"task-1"}}

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

        let stream = try makeClient().calendarRealtimeSignals(token: "token-value")
        var iterator = stream.makeAsyncIterator()
        let signal = try await iterator.next()
        XCTAssertEqual(signal?.action, .update)
        XCTAssertEqual(signal?.record.id, "task-1")
    }

    func testBoardRealtimeSubscribesToEveryBoardCollection() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/realtime")
            if request.httpMethod == "POST" {
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(
                    Set(fields["subscriptions"] as? [String] ?? []),
                    Set([
                        "board_projects/*",
                        "board_project_preferences/*",
                        "board_project_states/*",
                        "board_tasks/*",
                        "board_project_labels/*",
                        "board_project_members/*"
                    ])
                )
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            let body = Data(#"""
            id:board-client
            event:PB_CONNECT
            data:{"clientId":"board-client"}

            id:board-client
            event:board_project_states/*
            data:{"action":"update","record":{"id":"state-1"}}

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

        let stream = try makeClient().boardRealtimeSignals(token: "token-value")
        var iterator = stream.makeAsyncIterator()
        let signal = try await iterator.next()
        XCTAssertEqual(signal?.action, .update)
        XCTAssertEqual(signal?.record.id, "state-1")
    }

    func testDashboardRealtimeSubscribesToEverySummarySource() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/realtime")
            if request.httpMethod == "POST" {
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(
                    Set(fields["subscriptions"] as? [String] ?? []),
                    Set([
                        "board_projects/*",
                        "board_tasks/*",
                        "calendar_events/*",
                        "reading_items/*"
                    ])
                )
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            let body = Data(#"""
            id:dashboard-client
            event:PB_CONNECT
            data:{"clientId":"dashboard-client"}

            id:dashboard-client
            event:reading_items/*
            data:{"action":"update","record":{"id":"reading-1"}}

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

        let stream = try makeClient().dashboardRealtimeSignals(token: "token-value")
        var iterator = stream.makeAsyncIterator()
        let signal = try await iterator.next()
        XCTAssertEqual(signal?.action, .update)
        XCTAssertEqual(signal?.record.id, "reading-1")
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

    func testChatConversationListUsesStatusPaginationAndWebSort() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/collections/chat_conversations/records")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )
            XCTAssertEqual(query["page"], "2")
            XCTAssertEqual(query["perPage"], "20")
            XCTAssertEqual(query["filter"], "status = \"active\"")
            XCTAssertEqual(query["sort"], "-pinned,-last_message_at,-updated")
            let body = Data(#"{"page":2,"totalPages":3,"totalItems":42,"items":[{"id":"chat-1","owner":"user-1","title":"Planning","status":"active","pinned":true,"model_config":"model-1","message_count":8,"tool_call_count":2,"input_tokens":100,"output_tokens":40,"total_tokens":140,"context_tokens":120,"last_message_at":"2026-07-21 08:00:00.000Z","created":"2026-07-20 08:00:00.000Z","updated":"2026-07-21 08:00:00.000Z"}]}"#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let page = try await makeClient().getChatConversations(
            status: .active,
            page: 2,
            pageSize: 20,
            token: "token-value"
        )

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.totalItems, 42)
        XCTAssertEqual(page.items.first?.title, "Planning")
        XCTAssertEqual(page.items.first?.pinned, true)
        XCTAssertEqual(page.items.first?.messageSummary, "8 messages · 2 tools")
        XCTAssertEqual(page.items.first?.modelConfigID, "model-1")
    }

    func testChatConversationSearchAddsTitleFilter() async throws {
        MockURLProtocol.handler = { request in
            let components = try XCTUnwrap(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            )
            XCTAssertEqual(
                components.queryItems?.first(where: { $0.name == "filter" })?.value,
                "status = \"active\" && title ~ \"Roadmap\""
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"page":1,"totalPages":1,"totalItems":0,"items":[]}"#.utf8)
            )
        }

        let page = try await makeClient().getChatConversations(
            status: .active,
            page: 1,
            pageSize: 20,
            query: "  Roadmap  ",
            token: "token-value"
        )

        XCTAssertEqual(page.totalItems, 0)
    }

    func testChatMessagesUseProtectedEndpointAndDecodeParts() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/chat/conversations/chat-1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"[{"id":"message-1","role":"user","metadata":{"conversationId":"chat-1","status":"complete"},"parts":[{"type":"text","text":"Hello"}]}]"#.utf8)
            )
        }

        let messages = try await makeClient().getChatMessages(
            conversationID: "chat-1",
            token: "token-value"
        )

        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.parts.first?.text, "Hello")
    }

    func testChatStreamSendsNewUserMessageAndDecodesSSEChunks() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/chat/stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
            )
            XCTAssertEqual(body["runId"] as? String, "run-1")
            XCTAssertEqual(body["conversationId"] as? String, "chat-1")
            XCTAssertEqual(body["modelConfigId"] as? String, "model-1")
            let message = try XCTUnwrap(body["message"] as? [String: Any])
            XCTAssertEqual(message["role"] as? String, "user")
            let stream = """
            data: {"type":"start","messageId":"assistant-1","messageMetadata":{"runId":"run-1"}}

            data: {"type":"text-delta","id":"text-1","delta":"Hello"}

            data: [DONE]

            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!,
                Data(stream.utf8)
            )
        }
        let request = ChatStreamRequest(
            runID: "run-1",
            conversationID: "chat-1",
            modelConfigID: "model-1",
            message: ChatMessage(
                id: "user-1",
                role: .user,
                parts: [ChatMessagePart(type: "text", text: "Hello")]
            )
        )

        var chunks: [ChatStreamChunk] = []
        let client = try makeClient()
        for try await chunk in client.startChatStream(
            request: request,
            token: "token-value"
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.map(\.type), ["start", "text-delta"])
        XCTAssertEqual(chunks.first?.messageID, "assistant-1")
        XCTAssertEqual(chunks.last?.delta, "Hello")
    }

    func testChatConversationMutationsUsePocketBaseRecordAPI() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-value")
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/collections/chat_conversations/records"):
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: String]
                )
                XCTAssertEqual(body, ["title": "New conversation"])
                return Self.chatConversationResponse(for: request, title: "New conversation")

            case ("PATCH", "/api/collections/chat_conversations/records/chat-1"):
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
                )
                XCTAssertEqual(body["title"] as? String, "Renamed")
                XCTAssertEqual(body["pinned"] as? Bool, true)
                XCTAssertNil(body["status"])
                return Self.chatConversationResponse(
                    for: request,
                    title: "Renamed",
                    pinned: true
                )

            case ("DELETE", "/api/collections/chat_conversations/records/chat-1"):
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                    Data()
                )

            default:
                XCTFail("Unexpected chat request: \(request.httpMethod ?? "nil") \(request.url?.absoluteString ?? "nil")")
                throw URLError(.badURL)
            }
        }
        let client = try makeClient()

        let created = try await client.createChatConversation(
            title: "New conversation",
            token: "token-value"
        )
        let updated = try await client.updateChatConversation(
            id: created.id,
            update: ChatConversationUpdate(title: "Renamed", pinned: true),
            token: "token-value"
        )
        try await client.deleteChatConversation(id: updated.id, token: "token-value")

        XCTAssertEqual(updated.title, "Renamed")
        XCTAssertTrue(updated.pinned)
    }

    private static func chatConversationResponse(
        for request: URLRequest,
        title: String,
        pinned: Bool = false
    ) -> (HTTPURLResponse, Data) {
        let body = Data(
            #"{"id":"chat-1","owner":"user-1","title":"\#(title)","status":"active","pinned":\#(pinned),"model_config":"","message_count":0,"tool_call_count":0,"input_tokens":0,"output_tokens":0,"total_tokens":0,"context_tokens":0,"last_message_at":"","created":"2026-07-21 08:00:00.000Z","updated":"2026-07-21 08:00:00.000Z"}"#.utf8
        )
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            body
        )
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
