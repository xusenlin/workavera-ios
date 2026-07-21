import XCTest
@testable import Workavera

final class DocsToolPayloadTests: XCTestCase {
    private func json(_ string: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    func testSearchOutputDecodesDocumentList() throws {
        let output = try json(#"""
        [
          {
            "id": "doc-1",
            "title": "Roadmap",
            "kind": "markdown",
            "content": "# Roadmap\nShip v1",
            "folderName": "Plans",
            "revision": 3,
            "updated": "2026-07-20 08:00:00.000Z"
          },
          {
            "id": "doc-2",
            "title": "Landing",
            "kind": "html",
            "content": "<p>hi</p>",
            "projectName": "Website",
            "revision": 1
          }
        ]
        """#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_search", output: output))

        XCTAssertEqual(payload.documents.count, 2)
        XCTAssertEqual(payload.documents[0].title, "Roadmap")
        XCTAssertEqual(payload.documents[0].kind, .markdown)
        XCTAssertEqual(payload.documents[0].location, "Plans")
        XCTAssertEqual(payload.documents[0].revision, 3)
        XCTAssertNotNil(payload.documents[0].updatedDate)
        XCTAssertEqual(payload.documents[1].location, "Website")
    }

    func testUpsertCreateDecodesBareDocument() throws {
        let output = try json(#"{"id":"doc-1","title":"Notes","kind":"markdown","content":"body","revision":1}"#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_upsert", output: output))

        XCTAssertTrue(payload.isCreation)
        XCTAssertEqual(payload.documents.first?.title, "Notes")
        XCTAssertNil(payload.changed)
    }

    func testUpsertUpdateDecodesWrappedDocumentAndChanged() throws {
        let output = try json(#"""
        {"document":{"id":"doc-1","title":"Notes","content":"body","revision":4},"changed":false}
        """#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_upsert", output: output))

        XCTAssertFalse(payload.isCreation)
        XCTAssertEqual(payload.changed, false)
        XCTAssertEqual(payload.documents.first?.revision, 4)
    }

    func testReplaceDecodesMatches() throws {
        let output = try json(#"""
        {"document":{"id":"doc-1","title":"Notes","revision":5},"matches":3,"changed":true}
        """#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_replace", output: output))

        XCTAssertEqual(payload.matches, 3)
        XCTAssertEqual(payload.changed, true)
    }

    func testMoveDecodesBatchEnvelope() throws {
        let output = try json(#"""
        {
          "ok": true, "total": 3, "succeeded": 2, "failed": 1,
          "results": [
            {"index": 0, "ok": true, "result": {"id": "doc-1", "title": "Roadmap", "folderName": "Plans"}},
            {"index": 1, "ok": true, "result": {"id": "doc-2", "title": "Draft", "folderName": "", "projectName": ""}},
            {"index": 2, "ok": false, "error": "not found"}
          ]
        }
        """#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_move", output: output))

        XCTAssertEqual(payload.moveTotal, 3)
        XCTAssertEqual(payload.moveSucceeded, 2)
        XCTAssertEqual(payload.moveResults.count, 3)
        XCTAssertEqual(payload.moveResults[0].title, "Roadmap")
        XCTAssertEqual(payload.moveResults[0].destination, "Plans")
        XCTAssertEqual(payload.moveResults[1].destination, "My Documents")
        XCTAssertNil(payload.moveResults[2].destination)
        XCTAssertEqual(payload.moveResults[2].error, "not found")
    }

    func testWriteChunkDecodesLengthAndRevision() throws {
        let output = try json(#"{"id":"doc-1","kind":"markdown","revision":2,"contentLength":4200}"#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_write_chunk", output: output))

        XCTAssertEqual(payload.chunkContentLength, 4200)
        XCTAssertEqual(payload.chunkRevision, 2)
    }

    func testListFoldersDecodesNames() throws {
        let output = try json(#"[{"id":"folder-1","name":"Plans"},{"id":"folder-2","name":"Archive"}]"#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_list_folders", output: output))

        XCTAssertEqual(payload.folders.map(\.name), ["Plans", "Archive"])
    }

    func testStringEncodedOutputDecodesLikeAnObject() throws {
        let output = JSONValue.string(#"{"id":"doc-1","title":"Notes","revision":2}"#)

        let payload = try XCTUnwrap(DocsToolPayload(toolName: "docs_get", output: output))

        XCTAssertEqual(payload.documents.first?.title, "Notes")
    }

    func testUnknownToolAndMalformedOutputFailToDecode() throws {
        let output = try json(#"{"id":"doc-1"}"#)
        XCTAssertNil(DocsToolPayload(toolName: "reading_search", output: output))
        XCTAssertNil(DocsToolPayload(toolName: "docs_search", output: output))
        XCTAssertNil(DocsToolPayload(toolName: "docs_search", output: nil))
    }
}
