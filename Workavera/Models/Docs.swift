import Foundation

enum DocumentKind: String, Decodable, Hashable {
    case markdown
    case html
}

enum DocumentStatus: String, Decodable, Hashable {
    case draft
    case archived
}

enum DocsViewFilter: Hashable, Codable {
    case recent
    case pinned
    case myDocuments
    case folder(String)
    case project(String)
    case archived

    var usesPagination: Bool {
        switch self {
        case .myDocuments, .folder, .project, .archived: true
        case .recent, .pinned: false
        }
    }
}

struct DocumentFolder: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DocumentProject: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DocumentSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: DocumentKind
    let ownerID: String
    let projectID: String?
    let folderID: String?
    let status: DocumentStatus
    let revision: Int
    let updatedAt: Date
    var pinned: Bool
}

struct WorkspaceDocument: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: DocumentKind
    let content: String
    let ownerID: String
    let projectID: String?
    let folderID: String?
    let status: DocumentStatus
    let revision: Int
    let lastEditedBy: String
    let createdAt: Date
    let updatedAt: Date
    var pinned: Bool
}

struct DocumentVersion: Identifiable, Hashable, Decodable {
    let id: String
    let revision: Int
    let title: String
    let content: String?
    let createdBy: String
    let source: String
    let created: String

    var createdAt: Date { DocsDate.parse(created) }
}

/// A document's public link. `revision` is the snapshot the link serves, which
/// stays where it is while the document is edited; a nil `expiresAt` means the
/// link never expires.
struct DocumentShare: Equatable, Decodable {
    let docID: String
    let slug: String
    let revision: Int
    let expires: String
    let created: String
    let updated: String

    private enum CodingKeys: String, CodingKey {
        case docID = "docId"
        case slug, revision, expires, created, updated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        docID = try container.decodeIfPresent(String.self, forKey: .docID) ?? ""
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        expires = try container.decodeIfPresent(String.self, forKey: .expires) ?? ""
        created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
    }

    var expiresAt: Date? {
        guard !expires.isEmpty else { return nil }
        let parsed = DocsDate.parse(expires)
        return parsed == .distantPast ? nil : parsed
    }
}

/// Expiry choices offered when publishing.
enum DocumentShareExpiry: String, CaseIterable, Identifiable {
    /// Leaves an existing expiry untouched while other fields change.
    case keep
    case never
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep: "Keep current expiry"
        case .never: "No expiry"
        case .sevenDays: "7 days from now"
        case .thirtyDays: "30 days from now"
        }
    }

    private var dayCount: Int? {
        switch self {
        case .keep, .never: nil
        case .sevenDays: 7
        case .thirtyDays: 30
        }
    }

    /// Expiry for the request body; an empty string means "never expires".
    func requestValue(share: DocumentShare?, now: Date = .now) -> String {
        if self == .keep { return share?.expires ?? "" }
        guard let dayCount,
              let date = Calendar(identifier: .gregorian).date(
                  byAdding: .day,
                  value: dayCount,
                  to: now
              )
        else {
            return ""
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

struct DocsPage: Equatable {
    let documents: [DocumentSummary]
    let folders: [DocumentFolder]
    let projects: [DocumentProject]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

// MARK: - PocketBase records

struct DocumentRecord: Decodable {
    let id: String
    let title: String
    let kind: DocumentKind
    let content: String
    let owner: String
    let project: String
    let folder: String
    let status: DocumentStatus
    let revision: Int
    let lastEditedBy: String
    let created: String
    let updated: String

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, content, owner, project, folder, status, revision, created, updated
        case lastEditedBy = "last_edited_by"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        kind = try container.decodeIfPresent(DocumentKind.self, forKey: .kind) ?? .markdown
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        project = try container.decodeIfPresent(String.self, forKey: .project) ?? ""
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        status = try container.decodeIfPresent(DocumentStatus.self, forKey: .status) ?? .draft
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        lastEditedBy = try container.decodeIfPresent(String.self, forKey: .lastEditedBy) ?? ""
        created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
    }
}

struct PinnedDocumentRecord: Decodable {
    let id: String
    let title: String
    let kind: DocumentKind
    let ownerID: String
    let projectID: String?
    let folderID: String?
    let status: DocumentStatus
    let revision: Int
    let updated: String

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, ownerID = "ownerId", projectID = "projectId", folderID = "folderId"
        case status, revision, updated
    }
}

struct DocumentFolderRecord: Decodable {
    let id: String
    let name: String
}

enum DocsDate {
    static func parse(_ value: String) -> Date {
        guard !value.isEmpty else { return .distantPast }
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISO = ISO8601DateFormatter()
        standardISO.formatOptions = [.withInternetDateTime]
        let pocketBase = DateFormatter()
        pocketBase.locale = Locale(identifier: "en_US_POSIX")
        pocketBase.calendar = Calendar(identifier: .gregorian)
        pocketBase.timeZone = TimeZone(secondsFromGMT: 0)
        pocketBase.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        return fractionalISO.date(from: value)
            ?? standardISO.date(from: value)
            ?? pocketBase.date(from: value)
            ?? .distantPast
    }
}
