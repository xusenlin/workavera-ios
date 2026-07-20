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

    private func makeClient() throws -> PocketBaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return try PocketBaseClient(
            baseURLString: "https://example.com",
            allowInsecureHTTP: false,
            session: URLSession(configuration: configuration)
        )
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
