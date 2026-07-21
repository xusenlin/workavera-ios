import XCTest
@testable import Workavera

@MainActor
final class AuthStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tokenStore: MemoryTokenStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AuthStoreTests-\(UUID().uuidString)")!
        defaults.set("https://example.com", forKey: "workavera.serverAddress")
        tokenStore = MemoryTokenStore(value: "saved-token")
    }

    override func tearDown() {
        defaults = nil
        tokenStore = nil
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testTransportFailureKeepsTokenForRetry() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = makeStore()

        await store.restoreSession()

        XCTAssertEqual(store.phase, .recoveryFailed)
        XCTAssertEqual(tokenStore.value, "saved-token")
        XCTAssertNotNil(store.recoveryMessage)
    }

    func testUnauthorizedRefreshClearsToken() async {
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"message":"The request requires valid authentication."}"#.utf8)
            )
        }
        let store = makeStore()

        await store.restoreSession()

        XCTAssertEqual(store.phase, .loggedOut)
        XCTAssertNil(tokenStore.value)
        XCTAssertNil(store.token)
    }

    func testReloadPreferencesRecoversFromInitialTransportFailure() async throws {
        var preferenceAttempts = 0
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/collections/users/auth-with-password":
                let body = Data(#"{"token":"fresh-token","record":{"id":"user-1","collectionId":"_pb_users_auth_","collectionName":"users","email":"person@example.com","emailVisibility":true,"verified":true,"name":"Person","avatar":"","phone":"","title":"","bio":"","status":"online","created":"","updated":""}}"#.utf8)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    body
                )
            case "/api/collections/user_preferences/records":
                preferenceAttempts += 1
                if preferenceAttempts == 1 {
                    throw URLError(.notConnectedToInternet)
                }
                let body = Data(#"{"items":[{"id":"pref-1","owner":"user-1","theme":"dark","memory_enabled":true,"memory_auto_capture":false}]}"#.utf8)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    body
                )
            default:
                throw URLError(.badURL)
            }
        }
        let store = makeStore()

        try await store.login(email: "person@example.com", password: "secret")
        XCTAssertNil(store.preferences)
        XCTAssertNotNil(store.preferencesMessage)

        await store.reloadPreferences()

        XCTAssertEqual(store.preferences?.theme, .dark)
        XCTAssertTrue(store.memoryEnabled)
        XCTAssertNil(store.preferencesMessage)
        XCTAssertEqual(preferenceAttempts, 2)
    }

    func testCachedPreferencesSkipAutomaticRefreshOnSessionRestore() async throws {
        let authBody = Data(#"{"token":"fresh-token","record":{"id":"user-1","collectionId":"_pb_users_auth_","email":"person@example.com","name":"Person","avatar":"","status":"online"}}"#.utf8)
        var preferenceRequests = 0
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/collections/users/auth-with-password":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    authBody
                )
            case "/api/collections/user_preferences/records":
                let body = Data(#"{"items":[{"id":"pref-1","owner":"user-1","theme":"dark","memory_enabled":true,"memory_auto_capture":true}]}"#.utf8)
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    body
                )
            default:
                throw URLError(.badURL)
            }
        }
        let onlineStore = makeStore()
        try await onlineStore.login(email: "person@example.com", password: "secret")
        XCTAssertEqual(onlineStore.appearance, .dark)
        XCTAssertTrue(onlineStore.memoryEnabled)

        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/api/collections/users/auth-refresh":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    authBody
                )
            case "/api/collections/user_preferences/records":
                preferenceRequests += 1
                throw URLError(.notConnectedToInternet)
            default:
                throw URLError(.badURL)
            }
        }
        let offlineStore = makeStore()

        await offlineStore.restoreSession()

        XCTAssertEqual(offlineStore.phase, .loggedIn)
        XCTAssertEqual(offlineStore.appearance, .dark)
        XCTAssertTrue(offlineStore.memoryEnabled)
        XCTAssertTrue(offlineStore.memoryAutoCapture)
        XCTAssertNil(offlineStore.preferencesMessage)
        XCTAssertEqual(preferenceRequests, 0)
    }

    private func makeStore() -> AuthStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AuthStore(
            defaults: defaults,
            tokenStore: tokenStore,
            session: URLSession(configuration: configuration),
            responseCache: APIResponseCache(
                directory: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            )
        )
    }
}

private final class MemoryTokenStore: TokenStoring {
    var value: String?

    init(value: String?) {
        self.value = value
    }

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
