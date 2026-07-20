import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case unread
    case read
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unread: "Unread"
        case .read: "Read"
        case .archived: "Archived"
        }
    }
}

enum ReadingListFilter: String, CaseIterable, Identifiable {
    case active
    case unread
    case read
    case pinned
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: "All"
        case .unread: "Unread"
        case .read: "Read"
        case .pinned: "Pinned"
        case .archived: "Archived"
        }
    }

    var icon: String {
        switch self {
        case .active: "book"
        case .unread: "circle.fill"
        case .read: "checkmark.circle"
        case .pinned: "pin.fill"
        case .archived: "archivebox"
        }
    }
}

struct ReadingItem: Decodable, Identifiable, Equatable {
    let id: String
    let ownerID: String
    var projectID: String?
    var url: String
    var title: String
    var description: String
    var tags: [String]
    var status: ReadingStatus
    var pinned: Bool
    var contentText: String
    var summary: String
    var keyPoints: [String]
    var summaryLanguage: String?
    let createdAt: Date
    var updatedAt: Date

    var host: String {
        guard let host = URL(string: url)?.host(), !host.isEmpty else { return url }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var preview: String {
        if !summary.isEmpty { return summary }
        if !description.isEmpty { return description }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, title, description, tags, status, pinned, summary, created, updated
        case ownerID = "owner"
        case projectID = "project"
        case contentText = "content_text"
        case keyPoints = "key_points"
        case summaryLanguage = "summary_language"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerID = try container.decode(String.self, forKey: .ownerID)
        projectID = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .projectID))
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try container.decodeIfPresent(ReadingStatus.self, forKey: .status) ?? .unread
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        contentText = try container.decodeIfPresent(String.self, forKey: .contentText) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        summaryLanguage = Self.nonEmpty(
            try container.decodeIfPresent(String.self, forKey: .summaryLanguage)
        )
        createdAt = ReadingDate.parse(try container.decodeIfPresent(String.self, forKey: .created) ?? "")
        updatedAt = ReadingDate.parse(try container.decodeIfPresent(String.self, forKey: .updated) ?? "")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

struct ReadingPage: Equatable {
    let items: [ReadingItem]
    let page: Int
    let totalPages: Int
    let totalItems: Int
    let unreadCount: Int
}

struct ReadingItemInput {
    var url: String
    var title: String
    var description: String
    var tags: [String]
    var status: ReadingStatus = .unread
}

struct ReadingSummaryResponse: Decodable, Equatable {
    let contentText: String
    let summary: String
    let keyPoints: [String]
}

enum ReadingDate {
    static func parse(_ value: String) -> Date {
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
            ?? .distantPast
    }
}
