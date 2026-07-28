import Foundation

/// One locked tool definition of a user-owned MCP server. The assistant only
/// ever sees definitions the user has accepted; `stale` is a suspicion raised
/// by a failed call, not a confirmed upstream change.
struct MCPTool: Identifiable, Equatable, Decodable {
    let name: String
    let description: String
    let enabled: Bool
    let approval: MCPToolApproval
    let stale: Bool

    var id: String { name }

    var requiresApproval: Bool { approval == .always }

    private enum CodingKeys: String, CodingKey {
        case name, description, enabled, approval, stale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        approval = try container.decodeIfPresent(MCPToolApproval.self, forKey: .approval) ?? .always
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
    }

    init(
        name: String,
        description: String,
        enabled: Bool,
        approval: MCPToolApproval,
        stale: Bool
    ) {
        self.name = name
        self.description = description
        self.enabled = enabled
        self.approval = approval
        self.stale = stale
    }
}

enum MCPToolApproval: String, Decodable, CaseIterable, Identifiable {
    case always
    case never

    var id: String { rawValue }
}

enum MCPTransport: String, Decodable, CaseIterable, Identifiable {
    case http
    case sse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .http: "Streamable HTTP"
        case .sse: "SSE (legacy)"
        }
    }
}

/// The default applied to tools a refresh discovers. Upstream read-only
/// annotations only pre-select checkboxes at review time and never decide
/// runtime approval.
enum MCPApprovalPolicy: String, Decodable, CaseIterable, Identifiable {
    case writes
    case all
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .writes: "Ask unless the server says read-only"
        case .all: "Ask for everything"
        case .none: "Never ask"
        }
    }

    /// Compact text for the collapsed picker row, where the full label wraps.
    var shortLabel: String {
        switch self {
        case .writes: "Unless read-only"
        case .all: "Always"
        case .none: "Never"
        }
    }

    var hint: String {
        switch self {
        case .writes:
            "Tools ask before running unless the server marks them read-only."
        case .all:
            "Every tool asks before running."
        case .none:
            "Tools run without asking. Only for servers you fully trust."
        }
    }
}

/// A user-owned MCP server. Credentials (`headers`) are write-only and are
/// never returned by any read path, so they are absent here.
///
/// Two response shapes are accepted: PocketBase collection reads use
/// snake_case field names, while the feature's own routes answer in camelCase.
struct MCPServer: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
    let slug: String
    let transport: MCPTransport
    let url: String
    let approvalPolicy: MCPApprovalPolicy
    let enabled: Bool
    let tools: [MCPTool]
    let lastError: String
    let lastRefreshedAt: Date?

    var enabledToolCount: Int { tools.filter(\.enabled).count }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, transport, url, enabled, tools
        case approvalPolicyCamel = "approvalPolicy"
        case approvalPolicySnake = "approval_policy"
        case lastErrorCamel = "lastError"
        case lastErrorSnake = "last_error"
        case lastRefreshedCamel = "lastRefreshed"
        case lastRefreshedSnake = "last_refreshed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        transport = try container.decodeIfPresent(MCPTransport.self, forKey: .transport) ?? .http
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        approvalPolicy = try container.decodeIfPresent(
            MCPApprovalPolicy.self, forKey: .approvalPolicyCamel
        ) ?? container.decodeIfPresent(
            MCPApprovalPolicy.self, forKey: .approvalPolicySnake
        ) ?? .writes
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        tools = try container.decodeIfPresent([MCPTool].self, forKey: .tools) ?? []
        lastError = try container.decodeIfPresent(String.self, forKey: .lastErrorCamel)
            ?? container.decodeIfPresent(String.self, forKey: .lastErrorSnake)
            ?? ""
        let refreshed = try container.decodeIfPresent(String.self, forKey: .lastRefreshedCamel)
            ?? container.decodeIfPresent(String.self, forKey: .lastRefreshedSnake)
        lastRefreshedAt = MCPDate.parseOptional(refreshed)
    }

    init(
        id: String,
        name: String,
        slug: String,
        transport: MCPTransport,
        url: String,
        approvalPolicy: MCPApprovalPolicy,
        enabled: Bool,
        tools: [MCPTool],
        lastError: String,
        lastRefreshedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.transport = transport
        self.url = url
        self.approvalPolicy = approvalPolicy
        self.enabled = enabled
        self.tools = tools
        self.lastError = lastError
        self.lastRefreshedAt = lastRefreshedAt
    }
}

/// What a refresh reconciled between the upstream tool list and the locked
/// definitions. New or changed tools arrive disabled until the user accepts
/// them.
struct MCPRefreshReport: Equatable, Decodable {
    let added: [String]
    let changed: [String]
    let removed: [String]
    let unchanged: [String]
    let unsupported: [String]

    var changeCount: Int { added.count + changed.count + removed.count }

    private enum CodingKeys: String, CodingKey {
        case added, changed, removed, unchanged, unsupported
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        added = try container.decodeIfPresent([String].self, forKey: .added) ?? []
        changed = try container.decodeIfPresent([String].self, forKey: .changed) ?? []
        removed = try container.decodeIfPresent([String].self, forKey: .removed) ?? []
        unchanged = try container.decodeIfPresent([String].self, forKey: .unchanged) ?? []
        unsupported = try container.decodeIfPresent([String].self, forKey: .unsupported) ?? []
    }
}

struct MCPRefreshResponse: Decodable {
    let ok: Bool
    let error: String?
    let report: MCPRefreshReport?
    let server: MCPServer
}

/// Fields for registering a new server. The record starts with no tools and
/// is not usable until it has been refreshed and reviewed.
struct MCPServerInput {
    let name: String
    let slug: String
    let transport: MCPTransport
    let url: String
    let approvalPolicy: MCPApprovalPolicy
    let headers: [String: String]
}

/// Fields of an edit. A `nil` value leaves the stored value alone; in
/// particular `headers == nil` keeps the write-only credentials untouched.
struct MCPServerUpdate {
    var name: String?
    var url: String?
    var transport: MCPTransport?
    var approvalPolicy: MCPApprovalPolicy?
    var headers: [String: String]?
    var enabled: Bool?
}

/// One review decision sent to the tools route.
struct MCPToolDecision {
    let name: String
    let enabled: Bool
    let approval: MCPToolApproval
}

enum MCPDate {
    static func parseOptional(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return parse(value)
    }

    static func parse(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
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
    }
}
