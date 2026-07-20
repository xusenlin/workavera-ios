import Foundation

struct AuthResponse: Decodable {
    let token: String
    let record: User
}

struct PocketBaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 极简 PocketBase HTTP 客户端，只封装本 App 用到的接口。
struct PocketBaseClient {
    let baseURL: URL

    init?(baseURLString: String) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https"
        else { return nil }
        baseURL = url
    }

    // MARK: - Auth

    func authWithPassword(identity: String, password: String) async throws -> AuthResponse {
        try await send(
            path: "/api/collections/users/auth-with-password",
            method: "POST",
            body: ["identity": identity, "password": password]
        )
    }

    func authRefresh(token: String) async throws -> AuthResponse {
        try await send(
            path: "/api/collections/users/auth-refresh",
            method: "POST",
            token: token
        )
    }

    func updateUser(id: String, fields: [String: Any], token: String) async throws -> User {
        try await send(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: fields,
            token: token
        )
    }

    // MARK: - Files

    func fileURL(collectionId: String, recordId: String, fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        return baseURL.appending(path: "/api/files/\(collectionId)/\(recordId)/\(fileName)")
    }

    // MARK: - Transport

    private func send<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PocketBaseError(message: "Could not reach the server. Check the address and your network. (\(error.localizedDescription))")
        }

        guard let http = response as? HTTPURLResponse else {
            throw PocketBaseError(message: "The server returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PocketBaseError(message: Self.errorMessage(from: data, statusCode: http.statusCode))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return "Request failed (HTTP \(statusCode))."
    }
}
