import Foundation

struct UserPreferences: Decodable, Identifiable, Equatable {
    let id: String
    let owner: String
    var theme: AppAppearance
    var memoryEnabled: Bool
    var memoryAutoCapture: Bool
    let created: String?
    var updated: String?

    private enum CodingKeys: String, CodingKey {
        case id, owner, theme, created, updated
        case memoryEnabled = "memory_enabled"
        case memoryAutoCapture = "memory_auto_capture"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decode(String.self, forKey: .owner)
        let rawTheme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        theme = AppAppearance(rawValue: rawTheme) ?? .system
        memoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? false
        memoryAutoCapture = try container.decodeIfPresent(Bool.self, forKey: .memoryAutoCapture) ?? false
        created = try container.decodeIfPresent(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
    }
}

struct ProfileUpdate {
    var name: String
    var phone: String
    var title: String
    var bio: String
    var status: UserStatus
}

struct AvatarUpload {
    let data: Data
    let fileName: String
    let mimeType: String
}
