import Foundation

/// Parsed view of a `board_*` assistant tool call output, used by the chat UI
/// to render purpose-built cards. Shapes mirror the backend:
/// - `board_search_projects`: `[ProjectSummary]`
/// - `board_get_project`: `ProjectSummary`
/// - `board_search_tasks`: `{"states":…, "tasks":[…]}`
/// - `board_list_templates`: `[TemplateSummary]`
/// - mutations (`board_create_project`, `board_update_project`,
///   `board_upsert_state`, `board_upsert_label`, `board_upsert_member`,
///   `board_create_task`, `board_update_task`): batch envelope
///   `{"total":…, "succeeded":…, "results":[…]}` or a single `MutationResult`.
/// `board_delete_task` is approval-gated and stays on the generic tool card.
struct BoardToolPayload: Equatable, Sendable {
    struct Participant: Equatable, Sendable, Identifiable {
        let id: String
        var name: String = ""
        var avatar: String?
        var collectionID: String?
        var role: String?
    }

    struct StateChip: Equatable, Sendable, Identifiable {
        let id: String
        var name: String
        var color: String?
        var taskCount: Int?
    }

    struct LabelChip: Equatable, Sendable, Identifiable {
        let id: String
        var name: String
        var color: String?
    }

    struct Project: Equatable, Sendable, Identifiable {
        let id: String
        var name: String
        var description: String?
        var archived = false
        var role: String?
        var taskCount = 0
        var states: [StateChip] = []
        var labels: [LabelChip] = []
        var members: [Participant] = []
    }

    struct Task: Equatable, Sendable, Identifiable {
        let id: String
        var title: String
        var description: String?
        var priority: TaskPriority?
        var startDate: String?
        var dueDate: String?
        var projectName: String?
        var stateName: String?
        var stateColor: String?
        var labels: [LabelChip] = []
        var assignees: [Participant] = []

        /// Due dates arrive as `YYYY-MM-DD`; overdue means before today.
        var isOverdue: Bool {
            guard let dueDate else { return false }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: dueDate) else { return false }
            return date < Calendar.current.startOfDay(for: .now)
        }
    }

    struct Template: Equatable, Sendable, Identifiable {
        let id: String
        var name: String
        var description: String?
        var stateCount = 0
        var labelCount = 0
    }

    struct MutationItem: Equatable, Sendable, Identifiable {
        let index: Int
        var ok: Bool
        var name: String?
        var detail: String?
        var error: String?

        var id: Int { index }
    }

    var projects: [Project] = []
    var tasks: [Task] = []
    var templates: [Template] = []
    var mutationTotal = 0
    var mutationSucceeded = 0
    var mutationItems: [MutationItem] = []
    var isBatchMutation = false

    init?(toolName: String, output: JSONValue?) {
        guard let value = output?.decodingEmbeddedJSON else { return nil }
        switch toolName {
        case "board_search_projects":
            guard let items = value.arrayValue else { return nil }
            projects = items.compactMap(Self.project)
        case "board_get_project":
            guard let project = Self.project(from: value) else { return nil }
            projects = [project]
        case "board_search_tasks":
            guard let items = value.objectValue?["tasks"]?.arrayValue else { return nil }
            tasks = items.compactMap(Self.task)
        case "board_list_templates":
            guard let items = value.arrayValue else { return nil }
            templates = items.compactMap(Self.template)
        case "board_create_project", "board_update_project",
             "board_upsert_state", "board_upsert_label", "board_upsert_member",
             "board_create_task", "board_update_task":
            guard let object = value.objectValue else { return nil }
            if let results = object["results"]?.arrayValue {
                isBatchMutation = true
                mutationTotal = object["total"]?.intValue ?? results.count
                mutationSucceeded = object["succeeded"]?.intValue ?? 0
                mutationItems = results.map(Self.mutationItem)
            } else {
                let result = Self.mutationItem(from: value)
                mutationItems = [result]
                mutationTotal = 1
                mutationSucceeded = result.ok ? 1 : 0
            }
        default:
            return nil
        }
    }

    // MARK: - Element parsing

    private static func participant(from value: JSONValue) -> Participant? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue else { return nil }
        return Participant(
            id: id,
            name: object["name"]?.stringValue ?? "",
            avatar: nonEmpty(object["avatar"]?.stringValue),
            collectionID: nonEmpty(object["collectionId"]?.stringValue),
            role: nonEmpty(object["role"]?.stringValue)
        )
    }

    private static func stateChip(from value: JSONValue) -> StateChip? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let name = object["name"]?.stringValue else { return nil }
        return StateChip(
            id: id,
            name: name,
            color: nonEmpty(object["color"]?.stringValue),
            taskCount: object["taskCount"]?.intValue
        )
    }

    private static func labelChip(from value: JSONValue) -> LabelChip? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let name = object["name"]?.stringValue else { return nil }
        return LabelChip(id: id, name: name, color: nonEmpty(object["color"]?.stringValue))
    }

    private static func project(from value: JSONValue) -> Project? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let name = object["name"]?.stringValue else { return nil }
        let states = (object["states"]?.arrayValue ?? []).compactMap(stateChip)
        let members = (object["members"]?.arrayValue ?? []).compactMap(participant)
        return Project(
            id: id,
            name: name,
            description: nonEmpty(object["description"]?.stringValue),
            archived: object["archived"]?.boolValue ?? false,
            role: nonEmpty(object["currentActorRole"]?.stringValue),
            taskCount: states.reduce(0) { $0 + ($1.taskCount ?? 0) },
            states: states,
            labels: (object["labels"]?.arrayValue ?? []).compactMap(labelChip),
            members: members
        )
    }

    private static func task(from value: JSONValue) -> Task? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let title = object["title"]?.stringValue else { return nil }
        return Task(
            id: id,
            title: title,
            description: nonEmpty(object["description"]?.stringValue),
            priority: object["priority"]?.stringValue.flatMap(TaskPriority.init(rawValue:)),
            startDate: nonEmpty(object["startDate"]?.stringValue),
            dueDate: nonEmpty(object["dueDate"]?.stringValue),
            projectName: nonEmpty(object["project"]?.objectValue?["name"]?.stringValue),
            stateName: nonEmpty(object["state"]?.objectValue?["name"]?.stringValue),
            stateColor: nonEmpty(object["state"]?.objectValue?["color"]?.stringValue),
            labels: (object["labels"]?.arrayValue ?? []).compactMap(labelChip),
            assignees: (object["assignees"]?.arrayValue ?? []).compactMap(participant)
        )
    }

    private static func template(from value: JSONValue) -> Template? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue,
              let name = object["name"]?.stringValue else { return nil }
        return Template(
            id: id,
            name: name,
            description: nonEmpty(object["description"]?.stringValue),
            stateCount: object["states"]?.arrayValue?.count ?? 0,
            labelCount: object["labels"]?.arrayValue?.count ?? 0
        )
    }

    private static func mutationItem(from value: JSONValue) -> MutationItem {
        let object = value.objectValue
        if let result = object?["result"]?.objectValue {
            // Batch per-item shape: {index, ok, result: MutationResult, error}
            return MutationItem(
                index: object?["index"]?.intValue ?? 0,
                ok: object?["ok"]?.boolValue ?? false,
                name: result["name"]?.stringValue,
                detail: [result["action"]?.stringValue, result["resourceType"]?.stringValue]
                    .compactMap({ $0 })
                    .joined(separator: " "),
                error: nonEmpty(object?["error"]?.stringValue)
            )
        }
        // Single MutationResult shape: {ok, action, resourceType, name};
        // failed batch items land here too ({index, ok, error}).
        let ok = object?["ok"]?.boolValue ?? true
        return MutationItem(
            index: object?["index"]?.intValue ?? 0,
            ok: ok,
            name: object?["name"]?.stringValue,
            detail: [object?["action"]?.stringValue, object?["resourceType"]?.stringValue]
                .compactMap({ $0 })
                .joined(separator: " "),
            error: nonEmpty(object?["error"]?.stringValue)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
