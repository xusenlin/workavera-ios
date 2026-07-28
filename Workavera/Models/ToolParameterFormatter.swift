import Foundation

struct ToolParameterPreview: Equatable, Sendable {
    let text: String
    let truncated: Bool
}

/// Shared product limits for the compact tool-parameter panel.
///
/// These values intentionally match the web client. Formatting the bounded
/// preview happens only after the panel opens; formatting the complete value
/// happens only when the user copies it.
enum ToolParameterFormatter {
    static let maxPreviewCharacters = 12_000
    static let maxStringCharacters = 2_000
    static let maxArrayItems = 10
    static let maxObjectKeys = 30
    static let maxDepth = 4
    static let maxNodes = 120

    static func summary(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case let .string(string):
            return "\(string.count) chars"
        case let .array(items):
            return "\(items.count) items"
        case let .object(object):
            guard !object.isEmpty else { return "" }
            let keys = object.keys.sorted()
            var fields = keys.prefix(4).map { key in
                "\(key): \(summarizeValue(object[key] ?? .null))"
            }
            if keys.count > fields.count {
                fields.append("+\(keys.count - fields.count) fields")
            }
            return fields.joined(separator: " · ")
        case .number, .bool:
            return value.prettyPrinted
        }
    }

    static func preview(_ value: JSONValue) -> ToolParameterPreview {
        var context = PreviewContext()
        let limited = limitedValue(value, depth: 0, context: &context)
        var text = limited.prettyPrinted
        if text.count > maxPreviewCharacters {
            text = String(text.prefix(maxPreviewCharacters)) + "\n… preview shortened"
            context.truncated = true
        }
        return ToolParameterPreview(text: text, truncated: context.truncated)
    }

    static func fullText(_ value: JSONValue) -> String {
        value.prettyPrinted
    }

    private struct PreviewContext {
        var nodes = 0
        var truncated = false
    }

    private static func summarizeValue(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case let .array(items):
            return "\(items.count) items"
        case let .object(object):
            return "\(object.count) fields"
        case let .string(string):
            if string.count > 48 { return "\(string.count) chars" }
            return jsonStringLiteral(string)
        case .number, .bool:
            return value.prettyPrinted
        }
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return value }
        return String(decoding: data, as: UTF8.self)
    }

    private static func limitedValue(
        _ value: JSONValue,
        depth: Int,
        context: inout PreviewContext
    ) -> JSONValue {
        guard context.nodes < maxNodes else {
            context.truncated = true
            return .string("… preview node limit reached")
        }
        context.nodes += 1

        switch value {
        case let .string(string):
            guard string.count > maxStringCharacters else { return value }
            context.truncated = true
            return .string(
                String(string.prefix(maxStringCharacters))
                    + "… [\(string.count - maxStringCharacters) more chars]"
            )

        case let .array(items):
            guard depth < maxDepth else {
                context.truncated = true
                return .string("[Array(\(items.count)) hidden at depth limit]")
            }
            let visible = items.prefix(maxArrayItems).map {
                limitedValue($0, depth: depth + 1, context: &context)
            }
            var result = visible
            if items.count > visible.count {
                context.truncated = true
                result.append(.string("… \(items.count - visible.count) more items"))
            }
            return .array(result)

        case let .object(object):
            guard depth < maxDepth else {
                context.truncated = true
                return .string("[Object with \(object.count) fields hidden at depth limit]")
            }
            let keys = object.keys.sorted()
            let visibleKeys = keys.prefix(maxObjectKeys)
            var result: [String: JSONValue] = [:]
            for key in visibleKeys {
                result[key] = limitedValue(
                    object[key] ?? .null,
                    depth: depth + 1,
                    context: &context
                )
            }
            if keys.count > visibleKeys.count {
                context.truncated = true
                result["…"] = .string("\(keys.count - visibleKeys.count) more fields")
            }
            return .object(result)

        case .number, .bool, .null:
            return value
        }
    }
}
