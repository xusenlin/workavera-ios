import XCTest
@testable import Workavera

final class MemoryToolPayloadTests: XCTestCase {
    private func json(_ string: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    func testUpsertInputDecodesCategoryContentAndOrigin() throws {
        let input = try json(#"{"category":"work","content":"Uses SwiftUI","origin":"explicit"}"#)

        let payload = try XCTUnwrap(MemoryToolPayload(input: input))

        XCTAssertNil(payload.action)
        XCTAssertEqual(payload.category, .work)
        XCTAssertEqual(payload.content, "Uses SwiftUI")
        XCTAssertEqual(payload.origin, .explicit)
    }

    func testForgetInputDecodesWithoutMemoryFields() throws {
        let input = try json(#"{"id":"memory-1"}"#)

        let payload = try XCTUnwrap(MemoryToolPayload(input: input))

        XCTAssertNil(payload.category)
        XCTAssertNil(payload.content)
        XCTAssertNil(payload.origin)
    }

    func testObjectOutputDecodesActionAndMemory() throws {
        let output = try json(#"""
        {
          "action": "created",
          "memory": {
            "id": "memory-1",
            "category": "preference",
            "content": "Prefers concise answers",
            "active": true,
            "origin": "automatic",
            "updated": "2026-07-01 10:00:00.000Z"
          }
        }
        """#)

        let payload = try XCTUnwrap(MemoryToolPayload(output: output))

        XCTAssertEqual(payload.action, .created)
        XCTAssertEqual(payload.category, .preference)
        XCTAssertEqual(payload.content, "Prefers concise answers")
        XCTAssertEqual(payload.origin, .automatic)
    }

    func testStringEncodedOutputDecodesLikeAnObject() throws {
        let inner = #"{"action":"forgotten","memory":{"id":"memory-1","category":"goal","content":"Ship v1","active":false,"origin":"explicit"}}"#
        let output = JSONValue.string(inner)

        let payload = try XCTUnwrap(MemoryToolPayload(output: output))

        XCTAssertEqual(payload.action, .forgotten)
        XCTAssertEqual(payload.category, .goal)
        XCTAssertEqual(payload.content, "Ship v1")
    }

    func testOutputWithoutKnownActionFailsToDecode() throws {
        let output = try json(#"{"action":"bogus","memory":{}}"#)
        XCTAssertNil(MemoryToolPayload(output: output))
    }

    func testNilValuesFailToDecode() {
        XCTAssertNil(MemoryToolPayload(input: nil))
        XCTAssertNil(MemoryToolPayload(output: nil))
    }
}
