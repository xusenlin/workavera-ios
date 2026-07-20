import Foundation

struct AuthResponse: Decodable {
    let token: String
    let record: User
}

enum APIError: LocalizedError {
    case invalidResponse
    case transport(URLError)
    case http(statusCode: Int, message: String, fieldMessages: [String: String])
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .transport(let error):
            "Could not reach the server. \(error.localizedDescription)"
        case .http(_, let message, let fieldMessages):
            if let first = fieldMessages.sorted(by: { $0.key < $1.key }).first {
                "\(message) \(first.key): \(first.value)"
            } else {
                message
            }
        case .decoding:
            "The server returned data this version of Workavera could not read."
        }
    }

    var isAuthenticationFailure: Bool {
        guard case .http(let statusCode, _, _) = self else { return false }
        return statusCode == 401 || statusCode == 403
    }
}

struct PocketBaseClient {
    let configuration: ServerConfiguration
    private let session: URLSession

    init(
        baseURLString: String,
        allowInsecureHTTP: Bool,
        session: URLSession = .shared
    ) throws {
        configuration = try ServerConfiguration(
            address: baseURLString,
            allowInsecureHTTP: allowInsecureHTTP
        )
        self.session = session
    }

    func authWithPassword(identity: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable {
            let identity: String
            let password: String
        }
        return try await sendJSON(
            path: "/api/collections/users/auth-with-password",
            method: "POST",
            body: Body(identity: identity, password: password)
        )
    }

    func authRefresh(token: String) async throws -> AuthResponse {
        try await send(path: "/api/collections/users/auth-refresh", method: "POST", token: token)
    }

    func updateStatus(id: String, status: UserStatus, token: String) async throws -> User {
        struct Body: Encodable { let status: UserStatus }
        return try await sendJSON(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: Body(status: status),
            token: token
        )
    }

    func updateProfile(
        id: String,
        profile: ProfileUpdate,
        avatar: AvatarUpload?,
        token: String
    ) async throws -> User {
        var form = MultipartFormData()
        form.addField(name: "name", value: profile.name)
        form.addField(name: "phone", value: profile.phone)
        form.addField(name: "title", value: profile.title)
        form.addField(name: "bio", value: profile.bio)
        form.addField(name: "status", value: profile.status.rawValue)
        if let avatar {
            form.addFile(
                name: "avatar",
                fileName: avatar.fileName,
                mimeType: avatar.mimeType,
                data: avatar.data
            )
        }
        let payload = form.finalize()
        return try await send(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: payload.data,
            contentType: "multipart/form-data; boundary=\(payload.boundary)",
            token: token
        )
    }

    func changePassword(
        id: String,
        currentPassword: String,
        newPassword: String,
        token: String
    ) async throws -> User {
        struct Body: Encodable {
            let oldPassword: String
            let password: String
            let passwordConfirm: String
        }
        return try await sendJSON(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: Body(
                oldPassword: currentPassword,
                password: newPassword,
                passwordConfirm: newPassword
            ),
            token: token
        )
    }

    func getPreferences(ownerID: String, token: String) async throws -> UserPreferences {
        let response: RecordListResponse<UserPreferences> = try await send(
            path: "/api/collections/user_preferences/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "filter", value: "owner = \"\(ownerID)\""),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perPage", value: "1"),
            ],
            token: token
        )
        guard let preferences = response.items.first else {
            throw APIError.http(
                statusCode: 404,
                message: "User preferences were not found.",
                fieldMessages: [:]
            )
        }
        return preferences
    }

    func updatePreferences(
        id: String,
        theme: AppAppearance? = nil,
        memoryEnabled: Bool? = nil,
        memoryAutoCapture: Bool? = nil,
        token: String
    ) async throws -> UserPreferences {
        struct Body: Encodable {
            let theme: String?
            let memoryEnabled: Bool?
            let memoryAutoCapture: Bool?

            enum CodingKeys: String, CodingKey {
                case theme
                case memoryEnabled = "memory_enabled"
                case memoryAutoCapture = "memory_auto_capture"
            }
        }
        return try await sendJSON(
            path: "/api/collections/user_preferences/records/\(id)",
            method: "PATCH",
            body: Body(
                theme: theme?.rawValue,
                memoryEnabled: memoryEnabled,
                memoryAutoCapture: memoryAutoCapture
            ),
            token: token
        )
    }

    func getNotifications(page: Int, pageSize: Int, token: String) async throws -> NotificationPage {
        let response: RecordListResponse<AppNotification> = try await send(
            path: "/api/collections/notifications/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "-pinned,-created"),
                URLQueryItem(name: "filter", value: "status = \"active\""),
            ],
            token: token
        )
        return NotificationPage(
            items: response.items,
            page: response.page,
            totalPages: response.totalPages,
            totalItems: response.totalItems
        )
    }

    func getUnreadNotificationCount(token: String) async throws -> Int {
        let response: RecordListResponse<AppNotification> = try await send(
            path: "/api/collections/notifications/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perPage", value: "1"),
                URLQueryItem(name: "filter", value: "status = \"active\" && read_at = \"\""),
            ],
            token: token
        )
        return response.totalItems
    }

    func markNotificationRead(id: String, token: String) async throws {
        let _: NotificationMutationResponse = try await send(
            path: "/api/notifications/\(id)/read",
            method: "POST",
            token: token
        )
    }

    func markAllNotificationsRead(token: String) async throws {
        let _: NotificationMutationResponse = try await send(
            path: "/api/notifications/read-all",
            method: "POST",
            token: token
        )
    }

    func respondToModelShare(
        notificationID: String,
        decision: ModelShareDecision,
        token: String
    ) async throws -> ModelShareStatus {
        struct Body: Encodable { let decision: ModelShareDecision }
        struct Response: Decodable { let status: ModelShareStatus }
        let response: Response = try await sendJSON(
            path: "/api/llm/shares/\(notificationID)/respond",
            method: "POST",
            body: Body(decision: decision),
            token: token
        )
        return response.status
    }

    func archiveNotification(id: String, token: String) async throws -> AppNotification {
        struct Body: Encodable {
            let status = "archived"
            let pinned = false
        }
        return try await sendJSON(
            path: "/api/collections/notifications/records/\(id)",
            method: "PATCH",
            body: Body(),
            token: token
        )
    }

    func deleteNotification(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/notifications/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func fileURL(collectionId: String, recordId: String, fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        return configuration.baseURL.appending(
            path: "/api/files/\(collectionId)/\(recordId)/\(fileName)"
        )
    }

    private func sendJSON<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        token: String? = nil
    ) async throws -> T {
        try await send(
            path: path,
            method: method,
            body: try JSONEncoder().encode(body),
            contentType: "application/json",
            token: token
        )
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        token: String? = nil
    ) async throws -> T {
        let data = try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            contentType: contentType,
            token: token
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func sendWithoutResponse(
        path: String,
        method: String,
        token: String? = nil
    ) async throws {
        _ = try await perform(path: path, method: method, token: token)
    }

    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        token: String? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            throw APIError.transport(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let details = Self.errorDetails(from: data, statusCode: http.statusCode)
            throw APIError.http(
                statusCode: http.statusCode,
                message: details.message,
                fieldMessages: details.fieldMessages
            )
        }
        return data
    }

    private static func errorDetails(
        from data: Data,
        statusCode: Int
    ) -> (message: String, fieldMessages: [String: String]) {
        struct FieldError: Decodable { let message: String? }
        struct ErrorResponse: Decodable {
            let message: String?
            let data: [String: FieldError]?
        }
        if let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            let fields = response.data?.compactMapValues(\.message) ?? [:]
            return (
                response.message?.isEmpty == false ? response.message! : "Request failed (HTTP \(statusCode)).",
                fields
            )
        }
        return ("Request failed (HTTP \(statusCode)).", [:])
    }
}

private struct RecordListResponse<Record: Decodable>: Decodable {
    let items: [Record]
    let page: Int
    let totalPages: Int
    let totalItems: Int

    private enum CodingKeys: String, CodingKey {
        case items, page, totalPages, totalItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([Record].self, forKey: .items)
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 1
        totalItems = try container.decodeIfPresent(Int.self, forKey: .totalItems) ?? items.count
    }
}

private struct NotificationMutationResponse: Decodable {}

private struct MultipartFormData {
    private let boundary = "Workavera-\(UUID().uuidString)"
    private var data = Data()

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(escaped(name))\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(escaped(name))\"; filename=\"\(escaped(fileName))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finalize() -> (data: Data, boundary: String) {
        append("--\(boundary)--\r\n")
        return (data, boundary)
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
