import XCTest
@testable import Workavera

final class ServerConfigurationTests: XCTestCase {
    func testHTTPSIsAcceptedAndTrailingSlashIsNormalized() throws {
        let configuration = try ServerConfiguration(
            address: " https://example.com/workavera/ ",
            allowInsecureHTTP: false
        )

        XCTAssertEqual(configuration.normalizedAddress, "https://example.com/workavera")
        XCTAssertFalse(configuration.usesInsecureHTTP)
    }

    func testLoopbackHTTPDoesNotRequireOptIn() throws {
        let configuration = try ServerConfiguration(
            address: "http://127.0.0.1:8090",
            allowInsecureHTTP: false
        )

        XCTAssertEqual(configuration.baseURL.host, "127.0.0.1")
        XCTAssertTrue(configuration.usesInsecureHTTP)
    }

    func testRemoteHTTPRequiresExplicitOptIn() {
        XCTAssertThrowsError(
            try ServerConfiguration(
                address: "http://192.168.1.20:8090",
                allowInsecureHTTP: false
            )
        ) { error in
            XCTAssertEqual(
                error as? ServerConfigurationError,
                .insecureHTTPRequiresPermission
            )
        }
    }

    func testMalformedAndQueryAddressesAreRejected() {
        XCTAssertThrowsError(
            try ServerConfiguration(address: "http:/broken", allowInsecureHTTP: true)
        )
        XCTAssertThrowsError(
            try ServerConfiguration(
                address: "https://example.com?token=secret",
                allowInsecureHTTP: false
            )
        )
    }
}
