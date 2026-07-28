import XCTest
@testable import Workavera

final class ToolParameterFormatterTests: XCTestCase {
    func testSummaryDoesNotSerializeLargeString() {
        let value = JSONValue.object([
            "content": .string(String(repeating: "<p>large</p>", count: 1_000)),
            "title": .string("Plan"),
        ])

        let summary = ToolParameterFormatter.summary(value)

        XCTAssertTrue(summary.contains("content: 12000 chars"))
        XCTAssertTrue(summary.contains(#"title: "Plan""#))
        XCTAssertFalse(summary.contains("<p>large</p>"))
    }

    func testPreviewBoundsStringsArraysObjectsDepthAndNodes() {
        let deep = JSONValue.object([
            "level1": .object([
                "level2": .object([
                    "level3": .object([
                        "level4": .object(["hidden": .string("value")]),
                    ]),
                ]),
            ]),
        ])
        let value = JSONValue.object([
            "html": .string(String(repeating: "x", count: 3_000)),
            "items": .array((0..<15).map { .number(Double($0)) }),
            "fields": .object(
                Dictionary(uniqueKeysWithValues: (0..<40).map {
                    ("key-\($0)", JSONValue.bool(true))
                })
            ),
            "deep": deep,
        ])

        let preview = ToolParameterFormatter.preview(value)

        XCTAssertTrue(preview.truncated)
        XCTAssertLessThanOrEqual(
            preview.text.count,
            ToolParameterFormatter.maxPreviewCharacters
                + "\n… preview shortened".count
        )
        XCTAssertTrue(preview.text.contains("1000 more chars"))
        XCTAssertTrue(preview.text.contains("5 more items"))
        XCTAssertTrue(preview.text.contains("10 more fields"))
        XCTAssertTrue(preview.text.contains("hidden at depth limit"))
    }
}
