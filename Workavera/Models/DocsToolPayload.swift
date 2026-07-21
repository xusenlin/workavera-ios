import Foundation

/// Parsed view of a `docs_*` assistant tool call output, used by the chat UI
/// to render a purpose-built card instead of raw JSON. Output shapes mirror
/// the backend tools:
/// - `docs_search`: `[Document]`
/// - `docs_get`: `Document`
/// - `docs_upsert`: bare `Document` on create, `{"document":…, "changed":…}` on update
/// - `docs_replace`: `{"document":…, "matches":…, "changed":…}`
/// - `docs_move`: batch envelope `{"total":…, "succeeded":…, "results":[…]}`
/// - `docs_write_chunk`: `{"id":…, "revision":…, "contentLength":…}`
/// - `docs_list_folders`: `[{"id":…, "name":…}]`
struct DocsToolPayload: Equatable, Sendable {
    struct Document: Equatable, Sendable, Identifiable {
        let id: String
        var title: String = "Untitled"
        var kind: DocumentKind?
        var excerpt: String?
        var location: String?
        var revision: Int?
        var updated: String?

        var updatedDate: Date? {
            guard let updated, !updated.isEmpty else { return nil }
            let date = DocsDate.parse(updated)
            return date == .distantPast ? nil : date
        }
    }

    struct Folder: Equatable, Sendable, Identifiable {
        let id: String
        var name: String
    }

    struct MoveResult: Equatable, Sendable, Identifiable {
        let index: Int
        var ok: Bool
        var title: String?
        var destination: String?
        var error: String?

        var id: Int { index }
    }

    var documents: [Document] = []
    var folders: [Folder] = []
    var isCreation = false
    var changed: Bool?
    var matches: Int?
    var moveTotal = 0
    var moveSucceeded = 0
    var moveResults: [MoveResult] = []
    var chunkContentLength: Int?
    var chunkRevision: Int?

    init?(toolName: String, output: JSONValue?) {
        guard let value = output?.decodingEmbeddedJSON else { return nil }
        switch toolName {
        case "docs_search":
            guard let items = value.arrayValue else { return nil }
            documents = items.compactMap(Self.document)
        case "docs_get":
            guard let doc = Self.document(from: value) else { return nil }
            documents = [doc]
        case "docs_upsert":
            guard let object = value.objectValue else { return nil }
            if let inner = object["document"], let doc = Self.document(from: inner) {
                documents = [doc]
                changed = object["changed"]?.boolValue
            } else if let doc = Self.document(from: value) {
                documents = [doc]
                isCreation = true
            } else {
                return nil
            }
        case "docs_replace":
            guard let object = value.objectValue,
                  let inner = object["document"],
                  let doc = Self.document(from: inner) else { return nil }
            documents = [doc]
            changed = object["changed"]?.boolValue
            matches = object["matches"]?.intValue
        case "docs_move":
            guard let object = value.objectValue else { return nil }
            moveTotal = object["total"]?.intValue ?? 0
            moveSucceeded = object["succeeded"]?.intValue ?? 0
            moveResults = (object["results"]?.arrayValue ?? []).map { result in
                let object = result.objectValue
                let document = object?["result"]?.objectValue
                let ok = object?["ok"]?.boolValue ?? false
                // The backend only reports where a document ended up (the
                // destination names live on the moved document); the source
                // location is not part of the tool data.
                let names = [document?["folderName"]?.stringValue, document?["projectName"]?.stringValue]
                let destination = names.compactMap({ $0 }).first(where: { !$0.isEmpty })
                    ?? (ok ? "My Documents" : nil)
                return MoveResult(
                    index: object?["index"]?.intValue ?? 0,
                    ok: ok,
                    title: document?["title"]?.stringValue,
                    destination: destination,
                    error: object?["error"]?.stringValue
                )
            }
        case "docs_write_chunk":
            guard let object = value.objectValue else { return nil }
            chunkContentLength = object["contentLength"]?.intValue
            chunkRevision = object["revision"]?.intValue
        case "docs_list_folders":
            guard let items = value.arrayValue else { return nil }
            folders = items.compactMap { item in
                guard let object = item.objectValue,
                      let id = object["id"]?.stringValue else { return nil }
                return Folder(id: id, name: object["name"]?.stringValue ?? "Untitled")
            }
        default:
            return nil
        }
    }

    private static func document(from value: JSONValue) -> Document? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue else { return nil }
        return Document(
            id: id,
            title: object["title"]?.stringValue ?? "Untitled",
            kind: object["kind"]?.stringValue.flatMap(DocumentKind.init(rawValue:)),
            excerpt: object["content"]?.stringValue,
            location: [object["projectName"]?.stringValue, object["folderName"]?.stringValue]
                .compactMap({ $0 })
                .first(where: { !$0.isEmpty }),
            revision: object["revision"]?.intValue,
            updated: object["updated"]?.stringValue
        )
    }
}
