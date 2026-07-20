import SwiftUI

/// 任务优先级，取值与后端 board_tasks.priority 一致。
enum TaskPriority: String, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    /// 与 Web 前端一致的颜色。
    var color: Color {
        switch self {
        case .none: Color(hex: "#94a3b8")
        case .low: Color(hex: "#64748b")
        case .medium: Color(hex: "#3b82f6")
        case .high: Color(hex: "#f59e0b")
        case .urgent: Color(hex: "#ef4444")
        }
    }
}

/// 状态列分类，取值与后端 board_project_states.category 一致。
enum BoardStateCategory: String {
    case pending
    case active
    case completed
}

/// 项目标签，对应后端 board_project_labels。
struct BoardLabel: Identifiable, Equatable {
    let id: String
    var name: String
    /// 十六进制颜色，如 "#3b82f6"。
    var color: String
}

/// 项目成员（布局阶段仅保留展示所需字段，接入 API 后对应 users 记录）。
struct BoardMember: Identifiable, Equatable {
    let id: String
    var name: String
}

/// 看板状态列，对应后端 board_project_states。
struct BoardState: Identifiable, Equatable {
    let id: String
    var name: String
    var color: String
    var category: BoardStateCategory
    var tasks: [BoardTask]
}

/// 看板任务卡片，字段对应后端 board_tasks。
struct BoardTask: Identifiable, Equatable {
    let id: String
    var title: String
    var description: String
    var priority: TaskPriority
    var dueDate: Date?
    var labels: [BoardLabel]
    var assignees: [BoardMember]
    var documentCount: Int

    var isOverdue: Bool {
        guard let dueDate else { return false }
        return dueDate < .now
    }
}

/// 看板项目，对应后端 board_projects。
struct BoardProject: Identifiable, Equatable {
    let id: String
    var name: String
    var description: String
    var members: [BoardMember]
    var states: [BoardState]

    var taskCount: Int {
        states.reduce(0) { $0 + $1.tasks.count }
    }

    /// 项目内使用到的标签数量（按 id 去重）。
    var labelCount: Int {
        Set(states.flatMap { $0.tasks.flatMap { $0.labels.map(\.id) } }).count
    }
}

// MARK: - 布局示例数据（接入 API 前的占位数据）

extension BoardProject {
    static let sample: [BoardProject] = {
        let senlin = BoardMember(id: "u1", name: "Senlin Xu")
        let ada = BoardMember(id: "u2", name: "Ada Chen")
        let marco = BoardMember(id: "u3", name: "Marco Li")
        let yuki = BoardMember(id: "u4", name: "Yuki Tanaka")

        let feature = BoardLabel(id: "l1", name: "Feature", color: "#3b82f6")
        let bug = BoardLabel(id: "l2", name: "Bug", color: "#ef4444")
        let design = BoardLabel(id: "l3", name: "Design", color: "#ec4899")
        let docs = BoardLabel(id: "l4", name: "Docs", color: "#8b5cf6")

        func days(fromNow offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        }

        return [
            BoardProject(
                id: "p1",
                name: "Workavera iOS App",
                description: "Native iOS client for the Workavera workspace.",
                members: [senlin, ada, marco, yuki],
                states: [
                    BoardState(
                        id: "s1", name: "Backlog", color: "#94a3b8", category: .pending,
                        tasks: [
                            BoardTask(
                                id: "t1",
                                title: "Offline cache for task lists",
                                description: "Cache board data locally so the board is readable without a network connection.",
                                priority: .low,
                                dueDate: nil,
                                labels: [feature],
                                assignees: [marco],
                                documentCount: 0
                            ),
                            BoardTask(
                                id: "t2",
                                title: "Push notification settings",
                                description: "",
                                priority: .none,
                                dueDate: days(fromNow: 12),
                                labels: [feature, design],
                                assignees: [ada],
                                documentCount: 1
                            ),
                        ]
                    ),
                    BoardState(
                        id: "s2", name: "In Progress", color: "#3b82f6", category: .active,
                        tasks: [
                            BoardTask(
                                id: "t3",
                                title: "Board page layout",
                                description: "Kanban board with projects, status columns and task cards, matching the web board.",
                                priority: .high,
                                dueDate: days(fromNow: 2),
                                labels: [feature],
                                assignees: [senlin, ada],
                                documentCount: 2
                            ),
                            BoardTask(
                                id: "t4",
                                title: "Fix avatar flicker on scroll",
                                description: "Avatars reload when cells are reused in long lists.",
                                priority: .urgent,
                                dueDate: days(fromNow: -1),
                                labels: [bug],
                                assignees: [senlin],
                                documentCount: 0
                            ),
                            BoardTask(
                                id: "t5",
                                title: "Dark mode polish",
                                description: "",
                                priority: .medium,
                                dueDate: days(fromNow: 5),
                                labels: [design],
                                assignees: [ada, yuki],
                                documentCount: 0
                            ),
                        ]
                    ),
                    BoardState(
                        id: "s3", name: "In Review", color: "#f59e0b", category: .active,
                        tasks: [
                            BoardTask(
                                id: "t6",
                                title: "Profile status switcher",
                                description: "Let users change their presence status from the profile page.",
                                priority: .medium,
                                dueDate: days(fromNow: 1),
                                labels: [feature],
                                assignees: [senlin, marco, yuki],
                                documentCount: 3
                            ),
                        ]
                    ),
                    BoardState(
                        id: "s4", name: "Done", color: "#22c55e", category: .completed,
                        tasks: [
                            BoardTask(
                                id: "t7",
                                title: "Login and session restore",
                                description: "",
                                priority: .high,
                                dueDate: nil,
                                labels: [feature],
                                assignees: [senlin],
                                documentCount: 1
                            ),
                        ]
                    ),
                ]
            ),
            BoardProject(
                id: "p2",
                name: "Marketing Site Redesign",
                description: "Refresh the public marketing pages.",
                members: [ada, yuki],
                states: [
                    BoardState(
                        id: "s5", name: "To Do", color: "#94a3b8", category: .pending,
                        tasks: [
                            BoardTask(
                                id: "t8",
                                title: "Draft new landing copy",
                                description: "Hero section plus three feature blocks.",
                                priority: .medium,
                                dueDate: days(fromNow: 7),
                                labels: [docs],
                                assignees: [ada],
                                documentCount: 2
                            ),
                        ]
                    ),
                    BoardState(
                        id: "s6", name: "Doing", color: "#3b82f6", category: .active,
                        tasks: []
                    ),
                    BoardState(
                        id: "s7", name: "Done", color: "#22c55e", category: .completed,
                        tasks: [
                            BoardTask(
                                id: "t9",
                                title: "Collect brand assets",
                                description: "",
                                priority: .low,
                                dueDate: nil,
                                labels: [design],
                                assignees: [yuki, ada],
                                documentCount: 4
                            ),
                        ]
                    ),
                ]
            ),
            BoardProject(
                id: "p3",
                name: "Content Calendar",
                description: "Plan and schedule blog and social posts.",
                members: [ada, marco],
                states: [
                    BoardState(
                        id: "s8", name: "Ideas", color: "#94a3b8", category: .pending,
                        tasks: [
                            BoardTask(
                                id: "t10",
                                title: "Q3 launch announcement",
                                description: "",
                                priority: .medium,
                                dueDate: days(fromNow: 20),
                                labels: [docs],
                                assignees: [marco],
                                documentCount: 0
                            ),
                        ]
                    ),
                    BoardState(
                        id: "s9", name: "Published", color: "#22c55e", category: .completed,
                        tasks: []
                    ),
                ]
            ),
            BoardProject(
                id: "p4",
                name: "Design System",
                description: "Shared components and design tokens.",
                members: [ada, yuki, senlin],
                states: [
                    BoardState(
                        id: "s10", name: "To Do", color: "#94a3b8", category: .pending,
                        tasks: [
                            BoardTask(
                                id: "t11",
                                title: "Define spacing tokens",
                                description: "",
                                priority: .low,
                                dueDate: nil,
                                labels: [design],
                                assignees: [yuki],
                                documentCount: 1
                            ),
                        ]
                    ),
                ]
            ),
            BoardProject(
                id: "p5",
                name: "Customer Feedback",
                description: "Triage incoming user feedback.",
                members: [senlin, marco, ada, yuki],
                states: [
                    BoardState(
                        id: "s11", name: "Inbox", color: "#94a3b8", category: .pending,
                        tasks: [
                            BoardTask(
                                id: "t12",
                                title: "Crash on iOS 16 login",
                                description: "Two reports of a crash right after tapping Sign In.",
                                priority: .urgent,
                                dueDate: days(fromNow: -3),
                                labels: [bug],
                                assignees: [senlin],
                                documentCount: 0
                            ),
                        ]
                    ),
                ]
            ),
        ]
    }()
}
