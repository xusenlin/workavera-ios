import XCTest
@testable import Workavera

final class ChatMessageTests: XCTestCase {
    func testPersistedMessageDecodesMarkdownReasoningToolAndMetadata() throws {
        let data = Data(
            #"""
            {
              "id":"message-1",
              "role":"assistant",
              "metadata":{
                "conversationId":"chat-1",
                "status":"complete",
                "runId":"run-1",
                "model":{"configId":"model-1","modelId":"gpt-4o","name":"GPT","protocol":"openai"},
                "usage":{"inputTokens":12,"outputTokens":7,"totalTokens":19,"reasoningTokens":2,"cacheCreationTokens":0,"cacheReadTokens":3}
              },
              "parts":[
                {"type":"reasoning","text":"Think","state":"done"},
                {"type":"text","text":"## Result\nDone","state":"done"},
                {"type":"dynamic-tool","toolCallId":"tool-1","toolName":"reading_search","state":"output-available","input":{"query":"Swift"},"output":{"items":[{"id":"reading-1"}]}},
                {"type":"source-url","sourceId":"source-1","url":"https://example.com","title":"Example"}
              ]
            }
            """#.utf8
        )

        let message = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.metadata?.status, .complete)
        XCTAssertEqual(message.metadata?.model?.name, "GPT")
        XCTAssertEqual(message.metadata?.usage?.cacheReadTokens, 3)
        XCTAssertEqual(message.parts[1].text, "## Result\nDone")
        XCTAssertEqual(message.parts[2].input?.objectValue?["query"]?.stringValue, "Swift")
        XCTAssertEqual(message.parts[3].url, "https://example.com")
    }

    func testStreamReducerBuildsTextAndToolStateFromUISDKChunks() throws {
        var reducer = ChatStreamReducer(messageID: "pending", runID: "run-1")
        let chunks = [
            #"{"type":"start","messageId":"assistant-1","messageMetadata":{"runId":"run-1"}}"#,
            #"{"type":"text-start","id":"text-1"}"#,
            #"{"type":"text-delta","id":"text-1","delta":"Hello "}"#,
            #"{"type":"text-delta","id":"text-1","delta":"world"}"#,
            #"{"type":"text-end","id":"text-1"}"#,
            #"{"type":"tool-input-start","toolCallId":"tool-1","toolName":"contacts_search"}"#,
            #"{"type":"tool-input-available","toolCallId":"tool-1","toolName":"contacts_search","input":{"query":"Ada"}}"#,
            #"{"type":"tool-output-available","toolCallId":"tool-1","output":{"count":1}}"#,
            #"{"type":"finish","finishReason":"stop","messageMetadata":{"status":"complete","usage":{"inputTokens":10,"outputTokens":4,"totalTokens":14}}}"#,
        ]

        for json in chunks {
            reducer.apply(try JSONDecoder().decode(ChatStreamChunk.self, from: Data(json.utf8)))
        }

        XCTAssertEqual(reducer.message.id, "assistant-1")
        XCTAssertEqual(reducer.message.metadata?.status, .complete)
        XCTAssertEqual(reducer.message.metadata?.usage?.totalTokens, 14)
        XCTAssertEqual(reducer.message.parts.first?.text, "Hello world")
        XCTAssertEqual(reducer.message.parts.first?.state, "done")
        XCTAssertEqual(reducer.message.parts.last?.state, "output-available")
        XCTAssertEqual(reducer.message.parts.last?.output?.objectValue?["count"], .number(1))
    }

    func testStreamReducerUpsertsCompactionDataByStableID() throws {
        var reducer = ChatStreamReducer(messageID: "pending", runID: "run-1")
        for json in [
            #"{"type":"data-compaction","id":"compaction","data":{"state":"started"}}"#,
            #"{"type":"data-compaction","id":"compaction","data":{"state":"done","untilSequence":12}}"#,
        ] {
            reducer.apply(try JSONDecoder().decode(ChatStreamChunk.self, from: Data(json.utf8)))
        }

        XCTAssertEqual(reducer.message.parts.count, 1)
        XCTAssertEqual(
            reducer.message.parts[0].data?.objectValue?["state"]?.stringValue,
            "done"
        )
    }
}
