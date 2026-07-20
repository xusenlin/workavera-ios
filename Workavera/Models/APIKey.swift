import Foundation

struct WorkaveraAPIKey: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
    let prefix: String
    let allowsDestructiveActions: Bool
    let expiresAt: Date?
    let lastUsedAt: Date?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, prefix, expires, created
        case allowsDestructiveActions = "allow_destructive"
        case lastUsed = "last_used"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prefix = try container.decode(String.self, forKey: .prefix)
        allowsDestructiveActions = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowsDestructiveActions
        ) ?? false
        expiresAt = APIKeyDate.parseOptional(
            try container.decodeIfPresent(String.self, forKey: .expires)
        )
        lastUsedAt = APIKeyDate.parseOptional(
            try container.decodeIfPresent(String.self, forKey: .lastUsed)
        )
        createdAt = APIKeyDate.parse(
            try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        )
    }
}

struct CreatedWorkaveraAPIKey: Equatable, Decodable {
    let id: String
    let key: String
    let prefix: String
    let name: String
    let allowsDestructiveActions: Bool

    private enum CodingKeys: String, CodingKey {
        case id, key, prefix, name
        case allowsDestructiveActions = "allowDestructive"
    }
}

enum APIKeyExpiration: String, CaseIterable, Identifiable {
    case never
    case sevenDays
    case thirtyDays
    case ninetyDays
    case oneYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Never expires"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .oneYear: "1 year"
        }
    }

    private var dayCount: Int? {
        switch self {
        case .never: nil
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .oneYear: 365
        }
    }

    func requestValue(now: Date = .now) -> String {
        guard let dayCount,
              let date = Calendar(identifier: .gregorian).date(
                byAdding: .day,
                value: dayCount,
                to: now
              ) else {
            return ""
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private enum APIKeyDate {
    static func parseOptional(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let parsed = parse(value)
        return parsed == .distantPast ? nil : parsed
    }

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
