import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// Tool outputs may arrive either as a JSON object or as a string holding
    /// serialized JSON; this normalizes both to the decoded value.
    var decodingEmbeddedJSON: JSONValue {
        guard case .string(let string) = self,
              let data = string.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return self }
        return decoded
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var prettyPrinted: String {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
              ) else {
            return String(describing: self)
        }
        return String(decoding: pretty, as: UTF8.self)
    }
}

enum ChatMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

enum ChatMessageStatus: String, Codable, Sendable {
    case pending
    case streaming
    case complete
    case error
    case cancelled
}

struct ChatModelSnapshot: Codable, Equatable, Sendable {
    let configID: String
    let modelID: String
    let name: String
    let protocolName: String

    private enum CodingKeys: String, CodingKey {
        case name
        case configID = "configId"
        case modelID = "modelId"
        case protocolName = "protocol"
    }
}

struct ChatTokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let reasoningTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalTokens: Int = 0,
        reasoningTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, totalTokens, reasoningTokens
        case cacheCreationTokens, cacheReadTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
        cacheCreationTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
    }
}

struct ChatSafeError: Codable, Equatable, Sendable {
    let code: String
    let message: String
}

struct ChatMessageMetadata: Codable, Equatable, Sendable {
    var conversationID: String? = nil
    var status: ChatMessageStatus? = nil
    var runID: String? = nil
    var model: ChatModelSnapshot? = nil
    var usage: ChatTokenUsage? = nil
    var contextUsage: ChatTokenUsage? = nil
    var contextTokens: Int? = nil
    var contextTokensEstimated: Bool? = nil
    var finishReason: String? = nil
    var stepCount: Int? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var error: ChatSafeError? = nil

    private enum CodingKeys: String, CodingKey {
        case status, model, usage, contextUsage, contextTokens
        case contextTokensEstimated, finishReason, stepCount, createdAt, updatedAt, error
        case conversationID = "conversationId"
        case runID = "runId"
    }

    mutating func merge(_ update: ChatMessageMetadata?) {
        guard let update else { return }
        conversationID = update.conversationID ?? conversationID
        status = update.status ?? status
        runID = update.runID ?? runID
        model = update.model ?? model
        usage = update.usage ?? usage
        contextUsage = update.contextUsage ?? contextUsage
        contextTokens = update.contextTokens ?? contextTokens
        contextTokensEstimated = update.contextTokensEstimated ?? contextTokensEstimated
        finishReason = update.finishReason ?? finishReason
        stepCount = update.stepCount ?? stepCount
        createdAt = update.createdAt ?? createdAt
        updatedAt = update.updatedAt ?? updatedAt
        error = update.error ?? error
    }

    var createdDate: Date? {
        ChatConversationDate.parseOptional(createdAt)
    }
}

struct ChatToolApprovalState: Codable, Equatable, Sendable {
    let id: String
    var approved: Bool?
}

struct ChatMessagePart: Codable, Equatable, Sendable {
    var type: String
    var text: String?
    var state: String?
    var toolCallID: String?
    var toolName: String?
    var input: JSONValue?
    var output: JSONValue?
    var errorText: String?
    var approval: ChatToolApprovalState?
    var sourceID: String?
    var url: String?
    var title: String?
    var mediaType: String?
    var filename: String?
    var data: JSONValue?
    var id: String?

    private enum CodingKeys: String, CodingKey {
        case type, text, state, input, output, errorText, approval
        case url, title, mediaType, filename, data, id
        case toolCallID = "toolCallId"
        case toolName
        case sourceID = "sourceId"
    }

    init(
        type: String,
        text: String? = nil,
        state: String? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        errorText: String? = nil,
        approval: ChatToolApprovalState? = nil,
        sourceID: String? = nil,
        url: String? = nil,
        title: String? = nil,
        mediaType: String? = nil,
        filename: String? = nil,
        data: JSONValue? = nil,
        id: String? = nil
    ) {
        self.type = type
        self.text = text
        self.state = state
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.input = input
        self.output = output
        self.errorText = errorText
        self.approval = approval
        self.sourceID = sourceID
        self.url = url
        self.title = title
        self.mediaType = mediaType
        self.filename = filename
        self.data = data
        self.id = id
    }
}

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var role: ChatMessageRole
    var metadata: ChatMessageMetadata?
    var parts: [ChatMessagePart]

    init(
        id: String,
        role: ChatMessageRole,
        metadata: ChatMessageMetadata? = nil,
        parts: [ChatMessagePart]
    ) {
        self.id = id
        self.role = role
        self.metadata = metadata
        self.parts = parts
    }
}

struct ChatStreamRequest: Encodable, Sendable {
    let runID: String
    let conversationID: String
    let modelConfigID: String
    let message: ChatMessage

    private enum CodingKeys: String, CodingKey {
        case message
        case runID = "runId"
        case conversationID = "conversationId"
        case modelConfigID = "modelConfigId"
    }
}

struct ChatStreamChunk: Decodable, Equatable, Sendable {
    let type: String
    let id: String?
    let delta: String?
    let messageID: String?
    let toolCallID: String?
    let toolName: String?
    let approvalID: String?
    let approved: Bool?
    let inputTextDelta: String?
    let input: JSONValue?
    let output: JSONValue?
    let errorText: String?
    let reason: String?
    let sourceID: String?
    let url: String?
    let title: String?
    let mediaType: String?
    let filename: String?
    let finishReason: String?
    let messageMetadata: ChatMessageMetadata?
    let data: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type, id, delta, approved, inputTextDelta, input, output
        case errorText, reason, url, title, mediaType, filename
        case finishReason, messageMetadata, data
        case messageID = "messageId"
        case toolCallID = "toolCallId"
        case toolName, approvalID = "approvalId"
        case sourceID = "sourceId"
    }

    /// Chunks that must reach the UI on arrival rather than waiting for the
    /// stream's flush throttle. An approval request stops the run until the
    /// user answers, so no later chunk would arrive to carry a skipped
    /// refresh, and the approval payload arrives with it.
    var requiresImmediateRender: Bool {
        type == "tool-approval-request" || type.hasPrefix("data-")
    }
}

struct ChatStreamReducer: Sendable {
    private(set) var message: ChatMessage
    private var activePartIndices: [String: Int] = [:]
    private var approvalToolCalls: [String: String] = [:]

    init(messageID: String, runID: String) {
        message = ChatMessage(
            id: messageID,
            role: .assistant,
            metadata: ChatMessageMetadata(status: .streaming, runID: runID),
            parts: []
        )
    }

    mutating func apply(_ chunk: ChatStreamChunk) {
        if chunk.type.hasPrefix("data-") {
            upsertDataPart(chunk)
            return
        }

        switch chunk.type {
        case "start":
            if let messageID = chunk.messageID { message.id = messageID }
            mergeMetadata(chunk.messageMetadata)
        case "start-step":
            message.parts.append(ChatMessagePart(type: "step-start"))
        case "text-start", "reasoning-start":
            let kind = chunk.type == "text-start" ? "text" : "reasoning"
            guard let id = chunk.id else { return }
            activePartIndices["\(kind):\(id)"] = message.parts.count
            message.parts.append(ChatMessagePart(type: kind, text: "", state: "streaming"))
        case "text-delta", "reasoning-delta":
            let kind = chunk.type == "text-delta" ? "text" : "reasoning"
            appendText(chunk.delta ?? "", key: "\(kind):\(chunk.id ?? "")", kind: kind)
        case "text-end", "reasoning-end":
            let kind = chunk.type == "text-end" ? "text" : "reasoning"
            finishPart(key: "\(kind):\(chunk.id ?? "")")
        case "tool-input-start":
            guard let callID = chunk.toolCallID else { return }
            activePartIndices["tool:\(callID)"] = message.parts.count
            message.parts.append(ChatMessagePart(
                type: "dynamic-tool",
                state: "input-streaming",
                toolCallID: callID,
                toolName: chunk.toolName
            ))
        case "tool-input-available", "tool-input-error":
            mutateToolPart(callID: chunk.toolCallID, toolName: chunk.toolName) { part in
                part.input = chunk.input
                part.state = chunk.type == "tool-input-error" ? "output-error" : "input-available"
                part.errorText = chunk.errorText
            }
        case "tool-approval-request":
            guard let approvalID = chunk.approvalID, let callID = chunk.toolCallID else { return }
            approvalToolCalls[approvalID] = callID
            mutateToolPart(callID: callID, toolName: chunk.toolName) { part in
                part.state = "approval-requested"
                part.approval = ChatToolApprovalState(id: approvalID, approved: nil)
            }
        case "tool-approval-response":
            guard let approvalID = chunk.approvalID,
                  let callID = approvalToolCalls[approvalID] else { return }
            mutateToolPart(callID: callID, toolName: nil) { part in
                part.state = "approval-responded"
                part.approval = ChatToolApprovalState(id: approvalID, approved: chunk.approved)
            }
            approvalToolCalls.removeValue(forKey: approvalID)
        case "tool-output-available", "tool-output-error", "tool-output-denied":
            mutateToolPart(callID: chunk.toolCallID, toolName: chunk.toolName) { part in
                if chunk.type == "tool-output-available" {
                    part.state = "output-available"
                    part.output = chunk.output
                } else {
                    part.state = "output-error"
                    part.errorText = chunk.errorText ?? "The tool action was denied."
                }
            }
        case "source-url", "source-document", "file":
            message.parts.append(ChatMessagePart(
                type: chunk.type,
                sourceID: chunk.sourceID,
                url: chunk.url,
                title: chunk.title,
                mediaType: chunk.mediaType,
                filename: chunk.filename
            ))
        case "message-metadata":
            mergeMetadata(chunk.messageMetadata)
        case "finish":
            mergeMetadata(chunk.messageMetadata)
            message.metadata?.status = .complete
            if let finishReason = chunk.finishReason {
                message.metadata?.finishReason = finishReason
            }
        case "error":
            message.metadata?.status = .error
            if message.metadata?.error == nil {
                message.metadata?.error = ChatSafeError(
                    code: "stream_error",
                    message: chunk.errorText ?? "The chat run failed."
                )
            }
        case "abort":
            message.metadata?.status = .cancelled
        default:
            break
        }
    }

    private mutating func upsertDataPart(_ chunk: ChatStreamChunk) {
        let key = "\(chunk.type):\(chunk.id ?? "")"
        if let index = activePartIndices[key], message.parts.indices.contains(index) {
            message.parts[index].data = chunk.data
            return
        }
        activePartIndices[key] = message.parts.count
        message.parts.append(ChatMessagePart(type: chunk.type, data: chunk.data, id: chunk.id))
    }

    private mutating func appendText(_ delta: String, key: String, kind: String) {
        if let index = activePartIndices[key], message.parts.indices.contains(index) {
            message.parts[index].text = (message.parts[index].text ?? "") + delta
            return
        }
        activePartIndices[key] = message.parts.count
        message.parts.append(ChatMessagePart(type: kind, text: delta, state: "streaming"))
    }

    private mutating func finishPart(key: String) {
        guard let index = activePartIndices.removeValue(forKey: key),
              message.parts.indices.contains(index) else { return }
        message.parts[index].state = "done"
    }

    private mutating func mutateToolPart(
        callID: String?,
        toolName: String?,
        mutation: (inout ChatMessagePart) -> Void
    ) {
        guard let callID else { return }
        let key = "tool:\(callID)"
        let index: Int
        if let existing = activePartIndices[key], message.parts.indices.contains(existing) {
            index = existing
        } else {
            index = message.parts.count
            activePartIndices[key] = index
            message.parts.append(ChatMessagePart(
                type: "dynamic-tool",
                state: "input-available",
                toolCallID: callID,
                toolName: toolName
            ))
        }
        if message.parts[index].toolName?.isEmpty != false {
            message.parts[index].toolName = toolName
        }
        mutation(&message.parts[index])
    }

    private mutating func mergeMetadata(_ update: ChatMessageMetadata?) {
        if message.metadata == nil { message.metadata = ChatMessageMetadata() }
        message.metadata?.merge(update)
    }
}
