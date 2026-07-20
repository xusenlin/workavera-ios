import Foundation

enum ServerConfigurationError: LocalizedError, Equatable {
    case emptyAddress
    case invalidAddress
    case unsupportedScheme
    case credentialsNotAllowed
    case queryOrFragmentNotAllowed
    case insecureHTTPRequiresPermission

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            "Enter a server address."
        case .invalidAddress:
            "Enter a complete server address with a host name."
        case .unsupportedScheme:
            "The server address must use HTTPS or HTTP."
        case .credentialsNotAllowed:
            "Do not include a user name or password in the server address."
        case .queryOrFragmentNotAllowed:
            "The server address cannot contain a query or fragment."
        case .insecureHTTPRequiresPermission:
            "HTTP is not encrypted. Use HTTPS or explicitly allow insecure HTTP for this server."
        }
    }
}

struct ServerConfiguration: Equatable {
    let baseURL: URL
    let normalizedAddress: String
    let usesInsecureHTTP: Bool

    init(address: String, allowInsecureHTTP: Bool) throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServerConfigurationError.emptyAddress }
        guard var components = URLComponents(string: trimmed) else {
            throw ServerConfigurationError.invalidAddress
        }
        guard let rawScheme = components.scheme else {
            throw ServerConfigurationError.invalidAddress
        }
        let scheme = rawScheme.lowercased()
        guard scheme == "https" || scheme == "http" else {
            throw ServerConfigurationError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw ServerConfigurationError.invalidAddress
        }
        guard components.user == nil, components.password == nil else {
            throw ServerConfigurationError.credentialsNotAllowed
        }
        guard components.query == nil, components.fragment == nil else {
            throw ServerConfigurationError.queryOrFragmentNotAllowed
        }

        let insecure = scheme == "http"
        if insecure && !Self.isLoopback(host) && !allowInsecureHTTP {
            throw ServerConfigurationError.insecureHTTPRequiresPermission
        }

        components.scheme = scheme
        if components.path == "/" {
            components.path = ""
        } else {
            while components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }
        guard let url = components.url else {
            throw ServerConfigurationError.invalidAddress
        }

        baseURL = url
        normalizedAddress = url.absoluteString
        usesInsecureHTTP = insecure
    }

    private static func isLoopback(_ host: String) -> Bool {
        let value = host.lowercased()
        return value == "localhost" || value.hasSuffix(".localhost") || value == "127.0.0.1" || value == "::1"
    }
}
