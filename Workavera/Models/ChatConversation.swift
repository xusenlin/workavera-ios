import Foundation

enum ChatConversationStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case archived

    var id: String { rawValue }
}

struct ChatConversation: Decodable, Identifiable, Equatable {
    let id: String
    let ownerID: String
    var title: String
    var status: ChatConversationStatus
    var pinned: Bool
    var modelConfigID: String?
    var messageCount: Int
    var toolCallCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var contextTokens: Int
    var lastMessageAt: Date?
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, status, pinned, created, updated
        case ownerID = "owner"
        case modelConfigID = "model_config"
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case contextTokens = "context_tokens"
        case lastMessageAt = "last_message_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New conversation"
        status = try container.decodeIfPresent(ChatConversationStatus.self, forKey: .status) ?? .active
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        modelConfigID = Self.nonEmpty(
            try container.decodeIfPresent(String.self, forKey: .modelConfigID)
        )
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        toolCallCount = try container.decodeIfPresent(Int.self, forKey: .toolCallCount) ?? 0
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        contextTokens = try container.decodeIfPresent(Int.self, forKey: .contextTokens) ?? 0
        lastMessageAt = ChatConversationDate.parseOptional(
            try container.decodeIfPresent(String.self, forKey: .lastMessageAt)
        )
        createdAt = ChatConversationDate.parse(
            try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        )
        updatedAt = ChatConversationDate.parse(
            try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
        )
    }

    var activityDate: Date {
        lastMessageAt ?? updatedAt
    }

    var messageSummary: String {
        var parts = ["\(messageCount) \(messageCount == 1 ? "message" : "messages")"]
        if toolCallCount > 0 {
            parts.append("\(toolCallCount) \(toolCallCount == 1 ? "tool" : "tools")")
        }
        return parts.joined(separator: " · ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

struct ChatConversationsPage: Equatable {
    let items: [ChatConversation]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

struct ChatConversationUpdate: Encodable, Equatable {
    var title: String?
    var status: ChatConversationStatus?
    var pinned: Bool?
}

enum ChatConversationDate {
    static func parse(_ value: String) -> Date {
        parseOptional(value) ?? .distantPast
    }

    static func parseOptional(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISO = ISO8601DateFormatter()
        let pocketBase = DateFormatter()
        pocketBase.locale = Locale(identifier: "en_US_POSIX")
        pocketBase.timeZone = TimeZone(secondsFromGMT: 0)
        pocketBase.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        return fractionalISO.date(from: value)
            ?? standardISO.date(from: value)
            ?? pocketBase.date(from: value)
    }
}
