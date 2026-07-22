import Foundation

/// Parsed view of a `reading_*` assistant tool call output:
/// - `reading_search`: `[ItemSummary]`
/// - `reading_get` / `reading_summarize`: single `Item` — but summarize may
///   also return a plain-text error with state `output-available`
/// - `reading_upsert`: batch envelope whose per-item result is an `Item`
struct ReadingToolPayload: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        let id: String
        var title: String
        var url: String?
        var status: ReadingStatus?
        var description: String?
        var summary: String?
        var keyPoints: [String] = []
        var tags: [String] = []

        var host: String? {
            guard let url, let host = URL(string: url)?.host(), !host.isEmpty else { return nil }
            return host.replacingOccurrences(of: "www.", with: "")
        }
    }

    struct MutationItem: Equatable, Sendable, Identifiable {
        let index: Int
        var ok: Bool
        var title: String?
        var error: String?

        var id: Int { index }
    }

    var items: [Item] = []
    var mutationTotal = 0
    var mutationSucceeded = 0
    var mutationItems: [MutationItem] = []
    var isBatchMutation = false
    /// Non-JSON plain-text output (reading_summarize surfaces fetch/model
    /// failures this way).
    var plainText: String?

    init?(toolName: String, output: JSONValue?) {
        let value = output?.decodingEmbeddedJSON
        // A plain-text body (e.g. summarize failures) never decodes as JSON;
        // keep it so the card can show it instead of "not found".
        if let text = output?.stringValue, value?.objectValue == nil, value?.arrayValue == nil {
            plainText = text
            return
        }
        guard let value else { return nil }
        switch toolName {
        case "reading_search":
            guard let array = value.arrayValue else { return nil }
            items = array.compactMap(Self.item)
        case "reading_get", "reading_summarize":
            guard let item = Self.item(from: value) else { return nil }
            items = [item]
        case "reading_upsert":
            guard let object = value.objectValue else { return nil }
            if let results = object["results"]?.arrayValue {
                isBatchMutation = true
                mutationTotal = object["total"]?.intValue ?? results.count
                mutationSucceeded = object["succeeded"]?.intValue ?? 0
                mutationItems = results.map(Self.mutationItem)
            } else if let item = Self.item(from: value) {
                mutationItems = [MutationItem(index: 0, ok: true, title: item.title)]
                mutationTotal = 1
                mutationSucceeded = 1
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    private static func item(from value: JSONValue) -> Item? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let title = object["title"]?.stringValue else { return nil }
        return Item(
            id: id,
            title: title,
            url: nonEmpty(object["url"]?.stringValue),
            status: object["status"]?.stringValue.flatMap(ReadingStatus.init(rawValue:)),
            description: nonEmpty(object["description"]?.stringValue),
            summary: nonEmpty(object["summary"]?.stringValue),
            keyPoints: (object["keyPoints"]?.arrayValue ?? []).compactMap { $0.stringValue },
            tags: (object["tags"]?.arrayValue ?? []).compactMap { $0.stringValue }
        )
    }

    private static func mutationItem(from value: JSONValue) -> MutationItem {
        let object = value.objectValue
        return MutationItem(
            index: object?["index"]?.intValue ?? 0,
            ok: object?["ok"]?.boolValue ?? false,
            title: object?["result"]?.objectValue?["title"]?.stringValue,
            error: nonEmpty(object?["error"]?.stringValue)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
