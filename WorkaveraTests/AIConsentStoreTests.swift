import XCTest
@testable import Workavera

final class AIConsentStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AIConsentStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAuthorizationIsScopedToUserAndModel() {
        let store = AIConsentStore(defaults: defaults)

        XCTAssertFalse(store.isAuthorized(userID: "user-1", modelID: "model-1"))

        store.authorize(userID: "user-1", modelID: "model-1")

        XCTAssertTrue(store.isAuthorized(userID: "user-1", modelID: "model-1"))
        XCTAssertFalse(store.isAuthorized(userID: "user-1", modelID: "model-2"))
        XCTAssertFalse(store.isAuthorized(userID: "user-2", modelID: "model-1"))
    }

    func testAuthorizationPersistsAcrossStoreInstances() {
        AIConsentStore(defaults: defaults).authorize(userID: "user-1", modelID: "model-1")

        let restoredStore = AIConsentStore(defaults: defaults)

        XCTAssertTrue(restoredStore.isAuthorized(userID: "user-1", modelID: "model-1"))
    }
}
