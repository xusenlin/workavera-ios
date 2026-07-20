import SwiftUI

enum AppNotificationType: String, Decodable, Equatable {
    case modelShare = "model_share"
    case taskDue = "task_due"
    case calendarEvent = "calendar_event"
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }

    var icon: String {
        switch self {
        case .modelShare: "square.and.arrow.up"
        case .taskDue: "checklist"
        case .calendarEvent: "calendar"
        case .unknown: "bell"
        }
    }

    var color: Color {
        switch self {
        case .modelShare: .purple
        case .taskDue: .blue
        case .calendarEvent: .orange
        case .unknown: .secondary
        }
    }
}

enum AppNotificationStatus: String, Decodable {
    case active
    case archived
}

enum ModelShareDecision: String, Encodable {
    case accept
    case reject
}

enum ModelShareStatus: String, Decodable, Equatable {
    case pending
    case accepted
    case rejected
}

struct AppNotificationData: Decodable, Equatable {
    let senderID: String?
    let sourceModelID: String?
    let senderName: String?
    let modelName: String?
    var shareStatus: ModelShareStatus?

    private enum CodingKeys: String, CodingKey {
        case senderID = "senderId"
        case sourceModelID = "sourceModelId"
        case senderName, modelName, shareStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        senderID = try container.decodeIfPresent(String.self, forKey: .senderID)
        sourceModelID = try container.decodeIfPresent(String.self, forKey: .sourceModelID)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        shareStatus = try container.decodeIfPresent(ModelShareStatus.self, forKey: .shareStatus)
    }

    private init() {
        senderID = nil
        sourceModelID = nil
        senderName = nil
        modelName = nil
        shareStatus = nil
    }

    static let empty = AppNotificationData()
}

struct AppNotification: Decodable, Identifiable, Equatable {
    let id: String
    let recipient: String
    let type: AppNotificationType
    let title: String
    let body: String
    var data: AppNotificationData
    var readAt: Date?
    let status: AppNotificationStatus
    let pinned: Bool
    let createdAt: Date
    let updatedAt: Date

    var isRead: Bool { readAt != nil }

    private enum CodingKeys: String, CodingKey {
        case id, recipient, type, title, body, data, status, pinned
        case readAt = "read_at"
        case createdAt = "created"
        case updatedAt = "updated"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        recipient = try container.decode(String.self, forKey: .recipient)
        type = try container.decode(AppNotificationType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        data = try container.decodeIfPresent(AppNotificationData.self, forKey: .data) ?? .empty
        let rawReadAt = try container.decodeIfPresent(String.self, forKey: .readAt)
        readAt = try rawReadAt.flatMap { value in
            guard !value.isEmpty else { return nil }
            return try Self.decodeDate(value, codingPath: container.codingPath + [CodingKeys.readAt])
        }
        status = try container.decodeIfPresent(AppNotificationStatus.self, forKey: .status) ?? .active
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try Self.decodeDate(
            container.decode(String.self, forKey: .createdAt),
            codingPath: container.codingPath + [CodingKeys.createdAt]
        )
        updatedAt = try Self.decodeDate(
            container.decode(String.self, forKey: .updatedAt),
            codingPath: container.codingPath + [CodingKeys.updatedAt]
        )
    }

    private static func decodeDate(_ value: String, codingPath: [any CodingKey]) throws -> Date {
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardISO = ISO8601DateFormatter()
        standardISO.formatOptions = [.withInternetDateTime]
        let pocketBase = DateFormatter()
        pocketBase.locale = Locale(identifier: "en_US_POSIX")
        pocketBase.calendar = Calendar(identifier: .gregorian)
        pocketBase.timeZone = TimeZone(secondsFromGMT: 0)
        pocketBase.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"

        if let date = fractionalISO.date(from: value)
            ?? standardISO.date(from: value)
            ?? pocketBase.date(from: value) {
            return date
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: codingPath, debugDescription: "Invalid PocketBase date: \(value)")
        )
    }
}

struct NotificationPage: Equatable {
    let items: [AppNotification]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

enum NotificationRealtimeAction: String, Decodable, Equatable {
    case create
    case update
    case delete
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

struct NotificationRealtimeEvent: Decodable, Equatable {
    let action: NotificationRealtimeAction
    let record: AppNotification
}
