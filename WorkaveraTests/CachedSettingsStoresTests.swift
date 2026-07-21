import XCTest
@testable import Workavera

@MainActor
final class CachedSettingsStoresTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tokenStore: CachedStoreTokenStore!
    private var auth: AuthStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CachedSettingsStoresTests-\(UUID().uuidString)")!
        defaults.set("https://example.com", forKey: "workavera.serverAddress")
        tokenStore = CachedStoreTokenStore()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        auth = AuthStore(
            defaults: defaults,
            tokenStore: tokenStore,
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
        tokenStore = nil
        defaults = nil
        super.tearDown()
    }

    func testAPIKeysRemainVisibleAfterOfflineRefresh() async throws {
        try await signIn()
        var isOffline = false
        MockURLProtocol.handler = { request in
            if isOffline { throw URLError(.notConnectedToInternet) }
            XCTAssertEqual(request.url?.path, "/api/collections/api_keys/records")
            return Self.response(
                for: request,
                body: #"{"page":1,"totalPages":1,"items":[{"id":"key-1","name":"Claude Code","prefix":"sk-wa-1234","allow_destructive":false,"expires":"","last_used":"","created":"2026-07-19 08:00:00.000Z"}]}"#
            )
        }

        let store = APIKeysStore()
        await store.refresh(using: auth)
        XCTAssertEqual(store.keys.map(\.id), ["key-1"])

        isOffline = true
        await store.refresh(using: auth)

        XCTAssertEqual(store.keys.map(\.id), ["key-1"])
        XCTAssertNotNil(store.errorMessage)
    }

    func testSavedMemoriesRemainVisibleAfterOfflineRefresh() async throws {
        try await signIn()
        var isOffline = false
        MockURLProtocol.handler = { request in
            if isOffline { throw URLError(.notConnectedToInternet) }
            XCTAssertEqual(request.url?.path, "/api/collections/chat_memories/records")
            return Self.response(
                for: request,
                body: #"{"page":1,"totalPages":1,"items":[{"id":"memory-1","owner":"user-1","category":"preference","content":"Prefer concise answers.","active":true,"origin":"explicit","source_conversation":"","source_message":"","created":"2026-07-20 08:00:00.000Z","updated":"2026-07-20 09:00:00.000Z"}]}"#
            )
        }

        let store = SavedMemoriesStore()
        await store.refresh(using: auth)
        XCTAssertEqual(store.memories.map(\.id), ["memory-1"])

        isOffline = true
        await store.refresh(using: auth)

        XCTAssertEqual(store.memories.map(\.id), ["memory-1"])
        XCTAssertNotNil(store.errorMessage)
    }

    func testAPIKeysColdStoreLoadsCacheThenUpdatesFromNetwork() async throws {
        try await signIn()
        var requestCount = 0
        var responseID = "key-cached"
        MockURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(
                for: request,
                body: #"{"page":1,"totalPages":1,"items":[{"id":"\#(responseID)","name":"Key","prefix":"sk-wa-cache","allow_destructive":false,"expires":"","last_used":"","created":"2026-07-19 08:00:00.000Z"}]}"#
            )
        }

        let onlineStore = APIKeysStore()
        await onlineStore.refresh(using: auth)
        XCTAssertEqual(requestCount, 1)

        responseID = "key-updated"
        let coldStore = APIKeysStore()
        await coldStore.loadForPresentation(using: auth)

        XCTAssertEqual(coldStore.keys.map(\.id), ["key-updated"])
        XCTAssertNil(coldStore.errorMessage)
        XCTAssertEqual(requestCount, 2)
    }

    func testPullRefreshUpdatesDiskCache() async throws {
        try await signIn()
        var responseID = "key-before-refresh"
        MockURLProtocol.handler = { request in
            Self.response(
                for: request,
                body: #"{"page":1,"totalPages":1,"items":[{"id":"\#(responseID)","name":"Key","prefix":"sk-wa-cache","allow_destructive":false,"expires":"","last_used":"","created":"2026-07-19 08:00:00.000Z"}]}"#
            )
        }

        let store = APIKeysStore()
        await store.refresh(using: auth)
        responseID = "key-after-refresh"
        await store.refresh(using: auth)

        let cached = try await auth.loadAPIKeys(strategy: .cacheOnly)
        XCTAssertEqual(cached.map(\.id), ["key-after-refresh"])
    }

    func testCachedPageLoaderAlwaysRevalidatesAfterCacheStep() async {
        var steps: [String] = []
        await CachedPageLoader.load(
            hasPresentedContent: false,
            cache: { steps.append("cache") },
            network: { steps.append("network") }
        )
        XCTAssertEqual(steps, ["cache", "network"])

        steps = []
        await CachedPageLoader.load(
            hasPresentedContent: true,
            cache: { steps.append("cache") },
            network: { steps.append("network") }
        )
        XCTAssertEqual(steps, ["network"])
    }

    func testCacheMissRequestsNetworkAndRetriesTransientCancellation() async throws {
        try await signIn()
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                throw URLError(.cancelled)
            }
            return Self.response(
                for: request,
                body: #"{"page":1,"totalPages":1,"items":[{"id":"key-loaded","name":"Loaded key","prefix":"sk-wa-live","allow_destructive":false,"expires":"","last_used":"","created":"2026-07-19 08:00:00.000Z"}]}"#
            )
        }

        let store = APIKeysStore()
        await store.loadForPresentation(using: auth)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(store.keys.map(\.id), ["key-loaded"])
        XCTAssertNil(store.errorMessage)
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

    private static func response(
        for request: URLRequest,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(body.utf8)
        )
    }
}

private final class CachedStoreTokenStore: TokenStoring {
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
