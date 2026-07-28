import Foundation

/// A display-sized row in chat history.
///
/// Messages are intentionally flattened before they reach `LazyVStack`.
/// Assistant messages can contain dozens of tool and reasoning parts; keeping
/// the whole message as one row makes SwiftUI eagerly build and measure every
/// part as soon as that message enters the lazy layout.
struct ChatHistoryEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case header
        case userContent([ChatMessagePart])
        case waiting
        case assistantPart(ChatMessagePart, approvalData: JSONValue?)
        case error(ChatSafeError)
        case usage(ChatTokenUsage)
    }

    let id: String
    let messageID: String
    let role: ChatMessageRole
    let metadata: ChatMessageMetadata?
    let kind: Kind
    /// Gap above this row. Precomputed here because the list reads it once per
    /// row per layout pass; deriving it from neighbours at that point meant
    /// rebuilding the whole entry array twice for every visible row.
    var topSpacing: CGFloat = 0

    static func makeEntries(from messages: [ChatMessage]) -> [ChatHistoryEntry] {
        var entries = flatten(messages)
        for index in entries.indices where index > 0 {
            entries[index].topSpacing = spacing(
                for: entries[index].kind,
                after: entries[index - 1].kind
            )
        }
        return entries
    }

    private static func spacing(for kind: Kind, after previous: Kind) -> CGFloat {
        if case .header = kind { return 20 }
        if case .header = previous { return 7 }
        if case .usage = kind { return 7 }
        return 12
    }

    private static func flatten(_ messages: [ChatMessage]) -> [ChatHistoryEntry] {
        messages.flatMap { message in
            var entries = [
                ChatHistoryEntry(
                    id: "\(message.id):header",
                    messageID: message.id,
                    role: message.role,
                    metadata: message.metadata,
                    kind: .header
                ),
            ]

            if message.role == .user {
                let textParts = message.parts.filter {
                    $0.type == "text" && $0.text?.isEmpty == false
                }
                if !textParts.isEmpty {
                    entries.append(
                        ChatHistoryEntry(
                            id: "\(message.id):user-content",
                            messageID: message.id,
                            role: message.role,
                            metadata: message.metadata,
                            kind: .userContent(textParts)
                        )
                    )
                }
                return entries
            }

            if showsWaitingIndicator(for: message) {
                entries.append(
                    ChatHistoryEntry(
                        id: "\(message.id):waiting",
                        messageID: message.id,
                        role: message.role,
                        metadata: message.metadata,
                        kind: .waiting
                    )
                )
            }

            let approvals = approvalsByToolCallID(in: message.parts)
            for (index, part) in message.parts.enumerated() where isRenderable(part) {
                entries.append(
                    ChatHistoryEntry(
                        id: "\(message.id):part:\(index)",
                        messageID: message.id,
                        role: message.role,
                        metadata: message.metadata,
                        kind: .assistantPart(
                            part,
                            approvalData: part.type == "dynamic-tool"
                                ? part.toolCallID.flatMap { approvals[$0] }
                                : nil
                        )
                    )
                )
            }

            if let error = message.metadata?.error {
                entries.append(
                    ChatHistoryEntry(
                        id: "\(message.id):error",
                        messageID: message.id,
                        role: message.role,
                        metadata: message.metadata,
                        kind: .error(error)
                    )
                )
            }

            if let usage = message.metadata?.usage,
               usage.inputTokens > 0 || usage.outputTokens > 0 {
                entries.append(
                    ChatHistoryEntry(
                        id: "\(message.id):usage",
                        messageID: message.id,
                        role: message.role,
                        metadata: message.metadata,
                        kind: .usage(usage)
                    )
                )
            }

            return entries
        }
    }

    private static func showsWaitingIndicator(for message: ChatMessage) -> Bool {
        let status = message.metadata?.status
        guard status == .streaming || status == .pending else { return false }
        return !message.parts.contains { part in
            (part.text?.isEmpty == false) || part.type == "dynamic-tool"
        }
    }

    private static func isRenderable(_ part: ChatMessagePart) -> Bool {
        switch part.type {
        case "text", "reasoning":
            return part.text?.isEmpty == false
        case "dynamic-tool", "source-document", "data-compaction":
            return true
        case "source-url":
            guard let url = part.url else { return false }
            return URL(string: url) != nil
        default:
            return false
        }
    }

    /// Indexed in one pass. Scanning the part list per tool call made a
    /// tool-heavy message quadratic in its own part count.
    private static func approvalsByToolCallID(
        in parts: [ChatMessagePart]
    ) -> [String: JSONValue] {
        var approvals: [String: JSONValue] = [:]
        for part in parts where part.type == "data-approval" {
            guard let data = part.data,
                  let toolCallID = data.objectValue?["toolCallId"]?.stringValue,
                  approvals[toolCallID] == nil else { continue }
            approvals[toolCallID] = data
        }
        return approvals
    }
}
