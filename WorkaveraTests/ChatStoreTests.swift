import XCTest
@testable import Workavera

@MainActor
final class ChatStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var auth: AuthStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ChatStoreTests-\(UUID().uuidString)")!
        defaults.set("https://example.com", forKey: "workavera.serverAddress")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        auth = AuthStore(
            defaults: defaults,
            tokenStore: ChatStoreTokenStore(),
            session: URLSession(configuration: configuration),
            responseCache: APIResponseCache(
                directory: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            )
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        auth = nil
        defaults = nil
        super.tearDown()
    }

    func testArchiveRemovesSelectionAndArchivedListCanRestoreConversation() async throws {
        try await signIn()
        let store = ChatStore()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.response(
                for: request,
                body: Self.pageJSON(status: "active", ids: ["chat-pinned", "chat-next"])
            )
        }
        await store.refresh(using: auth)

        XCTAssertEqual(store.conversations.map(\.id), ["chat-pinned", "chat-next"])
        XCTAssertEqual(store.selectedConversationID, "chat-pinned")

        let archived = try XCTUnwrap(store.conversations.first)
        MockURLProtocol.handler = { request in
            if request.httpMethod == "PATCH" {
                return Self.response(
                    for: request,
                    body: Self.conversationJSON(id: archived.id, status: "archived")
                )
            }
            return Self.response(
                for: request,
                body: Self.pageJSON(status: "active", ids: ["chat-next"])
            )
        }
        try await store.archive(archived, using: auth)

        XCTAssertEqual(store.conversations.map(\.id), ["chat-next"])
        XCTAssertEqual(store.selectedConversationID, "chat-next")

        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                body: Self.pageJSON(status: "archived", ids: [archived.id])
            )
        }
        await store.loadArchived(using: auth)
        let restoreTarget = try XCTUnwrap(store.archivedConversations.first)

        MockURLProtocol.handler = { request in
            if request.httpMethod == "PATCH" {
                return Self.response(
                    for: request,
                    body: Self.conversationJSON(id: restoreTarget.id, status: "active")
                )
            }
            return Self.response(
                for: request,
                body: Self.pageJSON(status: "archived", ids: [])
            )
        }
        try await store.unarchive(restoreTarget, using: auth)

        XCTAssertTrue(store.conversations.contains(where: { $0.id == restoreTarget.id }))
        XCTAssertTrue(store.archivedConversations.isEmpty)
        XCTAssertEqual(store.archivedTotalItems, 0)
    }

    func testPinAndRenameReplaceConversationWithoutLosingSelection() async throws {
        try await signIn()
        let store = ChatStore()
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                body: Self.pageJSON(status: "active", ids: ["chat-1"])
            )
        }
        await store.refresh(using: auth)
        let conversation = try XCTUnwrap(store.selectedConversation)

        MockURLProtocol.handler = { request in
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try Self.bodyData(from: request)) as? [String: Any]
            )
            if payload["pinned"] as? Bool == true {
                return Self.response(
                    for: request,
                    body: Self.conversationJSON(id: conversation.id, status: "active", pinned: true)
                )
            }
            XCTAssertEqual(payload["title"] as? String, "Roadmap")
            return Self.response(
                for: request,
                body: Self.conversationJSON(
                    id: conversation.id,
                    status: "active",
                    title: "Roadmap",
                    pinned: true
                )
            )
        }

        try await store.togglePin(conversation, using: auth)
        let pinned = try XCTUnwrap(store.selectedConversation)
        try await store.rename(pinned, title: " Roadmap ", using: auth)

        XCTAssertEqual(store.selectedConversationID, conversation.id)
        XCTAssertEqual(store.selectedConversation?.title, "Roadmap")
        XCTAssertEqual(store.selectedConversation?.pinned, true)
    }

    private func signIn() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/collections/users/auth-with-password":
                return Self.response(
                    for: request,
                    body: #"{"token":"fresh-token","record":{"id":"user-1","collectionId":"_pb_users_auth_","email":"person@example.com","name":"Person","avatar":"","status":"online"}}"#
                )
            case "/api/collections/user_preferences/records":
                return Self.response(
                    for: request,
                    body: #"{"items":[{"id":"pref-1","owner":"user-1","theme":"system","memory_enabled":true,"memory_auto_capture":false}]}"#
                )
            default:
                throw URLError(.badURL)
            }
        }
        try await auth.login(email: "person@example.com", password: "secret")
    }

    private static func pageJSON(status: String, ids: [String]) -> String {
        let items = ids.map { id in
            conversationJSON(
                id: id,
                status: status,
                pinned: id == "chat-pinned"
            )
        }.joined(separator: ",")
        return "{\"page\":1,\"totalPages\":1,\"totalItems\":\(ids.count),\"items\":[\(items)]}"
    }

    private static func conversationJSON(
        id: String,
        status: String,
        title: String = "Conversation",
        pinned: Bool = false
    ) -> String {
        #"{"id":"\#(id)","owner":"user-1","title":"\#(title)","status":"\#(status)","pinned":\#(pinned),"model_config":"","message_count":2,"tool_call_count":0,"input_tokens":0,"output_tokens":0,"total_tokens":0,"context_tokens":0,"last_message_at":"2026-07-21 08:00:00.000Z","created":"2026-07-21 07:00:00.000Z","updated":"2026-07-21 08:00:00.000Z"}"#
    }

    private static func response(
        for request: URLRequest,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
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

private final class ChatStoreTokenStore: TokenStoring {
    private var value: String?

    func save(_ value: String, account: String) throws {
        self.value = value
    }

    func read(account: String) throws -> String? {
        value
    }

    func delete(account: String) throws {
        value = nil
    }
}
