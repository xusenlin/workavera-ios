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
    var summary: String = ""
    var keyPoints: [String] = []
    var summaryLanguage: String = ""
}

// MARK: - Subscriptions (discover)

enum ReadingSourceKind: String, Codable, CaseIterable, Identifiable {
    case rss
    case githubTrending = "github_trending"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rss: "RSS / Atom feed"
        case .githubTrending: "GitHub Trending"
        }
    }
}

enum TrendingSince: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "today"
        case .weekly: "this week"
        case .monthly: "this month"
        }
    }
}

/// One subscription the user owns: an RSS/Atom feed of their own, or GitHub's
/// trending board for one language over a day, week, or month.
struct ReadingSource: Identifiable, Equatable {
    let id: String
    var name: String
    var kind: ReadingSourceKind
    var url: String
    var language: String
    var since: TrendingSince
    var enabled: Bool
    var lastFetchedAt: Date?
    var lastError: String
}

struct ReadingSourceInput: Equatable {
    var name: String = ""
    var kind: ReadingSourceKind = .rss
    var url: String = ""
    var language: String = ""
    var since: TrendingSince = .weekly
    var enabled: Bool = true
}

/// One entry a subscription offered. Candidates are never stored: the panel
/// holds them until the user keeps one, which then becomes an ordinary
/// reading item.
struct DiscoverCandidate: Identifiable, Equatable, Decodable {
    let sourceID: String
    let sourceName: String
    let title: String
    let url: String
    let description: String
    let publishedAt: String
    let language: String
    let stars: Int
    let periodStars: Int
    let starsPeriod: String
    var alreadySaved: Bool

    var id: String { url }

    private enum CodingKeys: String, CodingKey {
        case sourceID = "sourceId"
        case sourceName, title, url, description, publishedAt, language
        case stars, periodStars, starsPeriod, alreadySaved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        stars = try container.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        periodStars = try container.decodeIfPresent(Int.self, forKey: .periodStars) ?? 0
        starsPeriod = try container.decodeIfPresent(String.self, forKey: .starsPeriod) ?? ""
        alreadySaved = try container.decodeIfPresent(Bool.self, forKey: .alreadySaved) ?? false
    }
}

struct DiscoverFailure: Identifiable, Equatable, Decodable {
    let sourceID: String
    let sourceName: String
    let message: String

    var id: String { sourceID }

    private enum CodingKeys: String, CodingKey {
        case sourceID = "sourceId"
        case sourceName, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
    }
}

struct CandidateSummary: Equatable {
    let summary: String
    let keyPoints: [String]
    let language: String
}

/// Languages a candidate can be summarized into, matching the web app.
enum SummaryLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case chinese = "中文"
    case japanese = "日本語"

    var id: String { rawValue }
}

struct ReadingSourceRecord: Decodable {
    struct Params: Decodable {
        let language: String?
        let since: String?
    }

    let id: String
    let name: String
    let kind: ReadingSourceKind
    let url: String
    let params: Params?
    let enabled: Bool
    let lastFetchedAt: String
    let lastError: String

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, url, params, enabled
        case lastFetchedAt = "last_fetched_at"
        case lastError = "last_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try container.decodeIfPresent(ReadingSourceKind.self, forKey: .kind) ?? .rss
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        params = try container.decodeIfPresent(Params.self, forKey: .params)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        lastFetchedAt = try container.decodeIfPresent(String.self, forKey: .lastFetchedAt) ?? ""
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError) ?? ""
    }

    var source: ReadingSource {
        let since = TrendingSince(rawValue: params?.since ?? "") ?? .weekly
        let fetched = lastFetchedAt.isEmpty ? nil : ReadingDate.parse(lastFetchedAt)
        return ReadingSource(
            id: id,
            name: name,
            kind: kind,
            url: url,
            language: params?.language ?? "",
            since: since,
            enabled: enabled,
            lastFetchedAt: fetched == .distantPast ? nil : fetched,
            lastError: lastError
        )
    }
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
