import Foundation

/// User presence values matching the status field in the Workavera users collection.
enum UserStatus: String, Codable, CaseIterable, Identifiable {
    case online
    case away
    case busy
    case offline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .online: "Online"
        case .away: "Away"
        case .busy: "Busy"
        case .offline: "Offline"
        }
    }
}

/// A record from the PocketBase users collection.
struct User: Decodable, Identifiable, Equatable {
    let id: String
    let collectionId: String
    var name: String
    var email: String
    var avatar: String
    var phone: String?
    var title: String?
    var bio: String?
    var status: UserStatus?
    var created: String?
    var updated: String?

    private enum CodingKeys: String, CodingKey {
        case id, collectionId, name, email, avatar, phone, title, bio, status, created, updated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId) ?? "users"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        phone = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .phone))
        title = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .title))
        bio = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .bio))
        // PocketBase returns "" for an empty select field, which cannot decode directly as UserStatus.
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        status = UserStatus(rawValue: rawStatus)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
    }

    var displayName: String {
        name.isEmpty ? email : name
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
