import XCTest
@testable import Workavera

final class ChatHistoryEntryTests: XCTestCase {
    func testAssistantPartsBecomeIndependentRowsAndHiddenPartsAreSkipped() {
        let message = ChatMessage(
            id: "assistant-1",
            role: .assistant,
            parts: [
                ChatMessagePart(type: "step-start"),
                ChatMessagePart(type: "reasoning", text: "Think"),
                ChatMessagePart(
                    type: "data-approval",
                    data: .object(["toolCallId": .string("tool-1")])
                ),
                ChatMessagePart(
                    type: "dynamic-tool",
                    toolCallID: "tool-1",
                    toolName: "board_create_task"
                ),
                ChatMessagePart(type: "text", text: "Done"),
            ]
        )

        let entries = ChatHistoryEntry.makeEntries(from: [message])

        XCTAssertEqual(
            entries.map(\.id),
            [
                "assistant-1:header",
                "assistant-1:part:1",
                "assistant-1:part:3",
                "assistant-1:part:4",
            ]
        )
        guard case let .assistantPart(_, approvalData) = entries[2].kind else {
            return XCTFail("Expected tool row")
        }
        XCTAssertEqual(
            approvalData?.objectValue?["toolCallId"]?.stringValue,
            "tool-1"
        )
    }

    func testLargeAssistantMessageProducesIndependentlyAddressableRows() {
        let message = ChatMessage(
            id: "assistant-1",
            role: .assistant,
            parts: (0..<50).map {
                ChatMessagePart(type: "text", text: "Part \($0)")
            }
        )
        let entries = ChatHistoryEntry.makeEntries(from: [message])

        XCTAssertEqual(entries.count, 51)
        XCTAssertEqual(entries.first?.id, "assistant-1:header")
        XCTAssertEqual(entries[39].id, "assistant-1:part:38")
        XCTAssertEqual(entries.last?.id, "assistant-1:part:49")
    }

    /// Spacing has to travel with the row. Deriving it from neighbours at
    /// render time meant rebuilding the whole array twice per visible row.
    func testEntriesCarryTheirOwnTopSpacing() {
        let entries = ChatHistoryEntry.makeEntries(from: [
            ChatMessage(
                id: "user-1",
                role: .user,
                parts: [ChatMessagePart(type: "text", text: "Hi")]
            ),
            ChatMessage(
                id: "assistant-1",
                role: .assistant,
                metadata: ChatMessageMetadata(usage: ChatTokenUsage(inputTokens: 5, outputTokens: 7)),
                parts: [
                    ChatMessagePart(type: "text", text: "One"),
                    ChatMessagePart(type: "text", text: "Two"),
                ]
            ),
        ])

        XCTAssertEqual(
            entries.map { "\($0.id)=\($0.topSpacing)" },
            [
                "user-1:header=0.0",          // first row never adds a gap
                "user-1:user-content=7.0",    // hugs its own header
                "assistant-1:header=20.0",    // new message opens a wider gap
                "assistant-1:part:0=7.0",     // hugs its own header
                "assistant-1:part:1=12.0",    // normal gap between parts
                "assistant-1:usage=7.0",      // hugs the message it totals
            ]
        )
    }

    func testExistingPartIDsStayStableWhenStreamingAppendsAnotherPart() {
        let original = ChatMessage(
            id: "assistant-1",
            role: .assistant,
            parts: [
                ChatMessagePart(type: "text", text: "One"),
                ChatMessagePart(type: "text", text: "Two"),
            ]
        )
        var appended = original
        appended.parts.append(ChatMessagePart(type: "text", text: "Three"))

        let originalIDs = ChatHistoryEntry.makeEntries(from: [original]).map(\.id)
        let appendedIDs = ChatHistoryEntry.makeEntries(from: [appended]).map(\.id)

        XCTAssertEqual(Array(appendedIDs.prefix(originalIDs.count)), originalIDs)
        XCTAssertEqual(appendedIDs.last, "assistant-1:part:2")
    }
}
