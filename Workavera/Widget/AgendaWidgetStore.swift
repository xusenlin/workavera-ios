import Foundation
import Security

/// Shared storage between the app and the agenda widget extension.
///
/// The app writes the signed-in server, user, and token here so the widget can
/// refresh on its own, plus the latest agenda snapshot so the widget can render
/// immediately (and offline). Everything lives in the App Group container; the
/// token goes to the App Group keychain access group rather than a plain file.
enum AgendaWidgetStore {
    static let appGroupID = "group.com.xusenlin.workavera.ios"
    static let widgetKind = "WorkaveraAgendaWidget"
    /// Opened when the widget is tapped; the app maps the host to an `AppSection`.
    static let calendarURL = URL(string: "workavera://calendar")!
    /// Opened by the widget's AI button.
    static let chatURL = URL(string: "workavera://chat")!

    struct Session: Codable, Equatable {
        let baseURL: URL
        let userID: String
    }

    private static let sessionFileName = "agenda-widget-session.json"
    private static let snapshotFileName = "agenda-widget-snapshot.json"
    private static let keychainService = "com.xusenlin.workavera.ios.widget"
    private static let tokenAccount = "workavera.widget.authToken"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    // MARK: Session

    static func saveSession(_ session: Session, token: String) {
        write(session, to: sessionFileName)
        saveToken(token)
    }

    static func loadSession() -> (session: Session, token: String)? {
        guard let session: Session = read(sessionFileName), let token = readToken() else { return nil }
        return (session, token)
    }

    /// Removes credentials and cached agenda, e.g. after sign-out.
    static func clear() {
        remove(sessionFileName)
        remove(snapshotFileName)
        SecItemDelete(tokenQuery() as CFDictionary)
    }

    // MARK: Snapshot

    static func saveSnapshot(_ snapshot: AgendaWidgetSnapshot) {
        write(snapshot, to: snapshotFileName)
    }

    static func loadSnapshot() -> AgendaWidgetSnapshot? {
        read(snapshotFileName)
    }

    // MARK: Files

    private static func write<Value: Encodable>(_ value: Value, to fileName: String) {
        guard let url = containerURL?.appending(path: fileName),
              let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read<Value: Decodable>(_ fileName: String) -> Value? {
        guard let url = containerURL?.appending(path: fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func remove(_ fileName: String) {
        guard let url = containerURL?.appending(path: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Keychain

    private static func saveToken(_ token: String) {
        let query = tokenQuery()
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // Widgets refresh in the background, including while the device is locked.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readToken() -> String? {
        var query = tokenQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func tokenQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrAccessGroup as String: appGroupID,
        ]
    }
}
