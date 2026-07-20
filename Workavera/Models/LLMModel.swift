import Foundation

enum LLMProtocol: String, Codable, CaseIterable, Identifiable {
    case openAI = "openai"
    case openAICompatible = "openai-compatible"
    case anthropic
    case google

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI compatible"
        case .anthropic: "Anthropic"
        case .google: "Google"
        }
    }

    var details: String {
        switch self {
        case .openAI, .openAICompatible: "Chat Completions API"
        case .anthropic: "Messages API"
        case .google: "Gemini generateContent API"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI, .openAICompatible: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .google: "https://generativelanguage.googleapis.com/"
        }
    }
}

struct LLMModelConfiguration: Identifiable, Equatable, Decodable {
    let id: String
    var name: String
    var modelID: String
    var baseURL: String
    var protocolType: LLMProtocol
    var maxOutputTokens: Int
    var maxContextTokens: Int
    var isDefault: Bool
    let sharedFromID: String
    let sharedFromName: String
    var hasAPIKey: Bool
    let created: String
    var updated: String

    var isSharedCopy: Bool { !sharedFromID.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, name, isDefault, sharedFromName, created, updated
        case baseURL = "baseUrl"
        case modelID = "modelId"
        case protocolType = "protocol"
        case maxOutputTokens, maxContextTokens
        case sharedFromID = "sharedFrom"
        case hasAPIKey = "hasApiKey"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        modelID = try container.decode(String.self, forKey: .modelID)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        protocolType = try container.decode(LLMProtocol.self, forKey: .protocolType)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 0
        maxContextTokens = try container.decodeIfPresent(Int.self, forKey: .maxContextTokens) ?? 256_000
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        sharedFromID = try container.decodeIfPresent(String.self, forKey: .sharedFromID) ?? ""
        sharedFromName = try container.decodeIfPresent(String.self, forKey: .sharedFromName) ?? ""
        hasAPIKey = try container.decodeIfPresent(Bool.self, forKey: .hasAPIKey) ?? false
        created = try container.decodeIfPresent(String.self, forKey: .created) ?? ""
        updated = try container.decodeIfPresent(String.self, forKey: .updated) ?? ""
    }
}

struct LLMModelInput: Equatable, Encodable {
    let name: String
    let modelID: String
    let baseURL: String
    let protocolType: LLMProtocol
    let maxOutputTokens: Int
    let maxContextTokens: Int
    let apiKey: String?

    private enum CodingKeys: String, CodingKey {
        case name, maxOutputTokens, maxContextTokens, apiKey
        case baseURL = "baseUrl"
        case modelID = "modelId"
        case protocolType = "protocol"
    }
}

struct LLMShareTarget: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
}

struct LLMShareResponse: Decodable, Equatable {
    let shared: Int
}

enum LLMTokenFormat {
    static func display(_ value: Int) -> String {
        if value >= 1_000_000 {
            return compact(Double(value) / 1_000_000) + "M"
        }
        if value >= 1_000 {
            return compact(Double(value) / 1_000) + "k"
        }
        return String(value)
    }

    private static func compact(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
