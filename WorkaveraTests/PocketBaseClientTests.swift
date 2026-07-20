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
