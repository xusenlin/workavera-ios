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

    private func makeStore() -> AuthStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AuthStore(
            defaults: defaults,
            tokenStore: tokenStore,
            session: URLSession(configuration: configuration)
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
