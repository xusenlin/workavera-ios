import Foundation

/// Parsed view of the `contacts_search` assistant tool output — a JSON array
/// of the non-sensitive contact projection (no email/phone, those never leave
/// the backend for tool results).
struct ContactsToolPayload: Equatable, Sendable {
    struct Contact: Equatable, Sendable, Identifiable {
        let id: String
        var name: String = ""
        var title: String?
        var status: UserStatus?
        var avatar: String?
        var collectionID: String?
    }

    var contacts: [Contact] = []

    init?(output: JSONValue?) {
        guard let items = output?.decodingEmbeddedJSON.arrayValue else { return nil }
        contacts = items.compactMap { item in
            guard let object = item.objectValue,
                  let id = object["id"]?.stringValue else { return nil }
            return Contact(
                id: id,
                name: object["name"]?.stringValue ?? "",
                title: object["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
                status: object["status"]?.stringValue.flatMap(UserStatus.init(rawValue:)),
                avatar: object["avatar"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
                collectionID: object["collectionId"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }
}
