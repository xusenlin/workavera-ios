import XCTest
@testable import Workavera

final class ContactsToolPayloadTests: XCTestCase {
    private func json(_ string: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    func testArrayOutputDecodesContacts() throws {
        let output = try json(#"""
        [
          {
            "id": "user-1",
            "name": "Ada Lovelace",
            "title": "Engineer",
            "status": "online",
            "avatar": "ada.png",
            "collectionId": "users"
          },
          {
            "id": "user-2",
            "name": "Grace Hopper"
          }
        ]
        """#)

        let payload = try XCTUnwrap(ContactsToolPayload(output: output))

        XCTAssertEqual(payload.contacts.count, 2)
        XCTAssertEqual(payload.contacts[0].name, "Ada Lovelace")
        XCTAssertEqual(payload.contacts[0].title, "Engineer")
        XCTAssertEqual(payload.contacts[0].status, .online)
        XCTAssertEqual(payload.contacts[0].avatar, "ada.png")
        XCTAssertEqual(payload.contacts[0].collectionID, "users")
        XCTAssertNil(payload.contacts[1].status)
        XCTAssertNil(payload.contacts[1].avatar)
    }

    func testEmptyOptionalFieldsDecodeAsNil() throws {
        let output = try json(#"[{"id":"user-1","name":"A","title":"","status":"","avatar":""}]"#)

        let payload = try XCTUnwrap(ContactsToolPayload(output: output))

        XCTAssertNil(payload.contacts[0].title)
        XCTAssertNil(payload.contacts[0].status)
        XCTAssertNil(payload.contacts[0].avatar)
    }

    func testStringEncodedOutputDecodesLikeAnArray() throws {
        let output = JSONValue.string(#"[{"id":"user-1","name":"Ada"}]"#)

        let payload = try XCTUnwrap(ContactsToolPayload(output: output))

        XCTAssertEqual(payload.contacts.first?.name, "Ada")
    }

    func testItemsWithoutIdAreSkipped() throws {
        let output = try json(#"[{"name":"No ID"},{"id":"user-1","name":"Ada"}]"#)

        let payload = try XCTUnwrap(ContactsToolPayload(output: output))

        XCTAssertEqual(payload.contacts.count, 1)
    }

    func testMalformedOutputFailsToDecode() throws {
        let object = try json(#"{"id":"user-1"}"#)
        XCTAssertNil(ContactsToolPayload(output: object))
        XCTAssertNil(ContactsToolPayload(output: nil))
    }
}
