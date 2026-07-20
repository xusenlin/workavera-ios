import Foundation

struct Contact: Identifiable, Equatable {
    let id: String
    let collectionID: String
    var name: String
    var email: String
    var phone: String?
    var title: String?
    var bio: String?
    var status: UserStatus
    var avatarURL: URL?
    var isFavorite: Bool

    var displayName: String {
        name.isEmpty ? email : name
    }
}

struct ContactRecord: Decodable {
    let id: String
    let collectionID: String
    let name: String
    let email: String
    let phone: String?
    let title: String?
    let bio: String?
    let status: UserStatus
    let avatar: String

    private enum CodingKeys: String, CodingKey {
        case id, name, email, phone, title, bio, status, avatar
        case collectionID = "collectionId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        collectionID = try container.decodeIfPresent(String.self, forKey: .collectionID) ?? "users"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .phone))
        title = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .title))
        bio = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .bio))
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        status = UserStatus(rawValue: rawStatus) ?? .offline
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

struct ContactFavoriteRecord: Decodable {
    let id: String
    let owner: String
    let contact: String
}

struct ContactsSnapshot: Equatable {
    let contacts: [Contact]
    let favoriteRecordIDs: [String: String]
}
