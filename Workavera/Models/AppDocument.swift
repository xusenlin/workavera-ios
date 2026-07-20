import SwiftUI

/// 文档格式，取值与后端 docs.kind 一致。
enum DocKind: String {
    case markdown
    case html

    var icon: String {
        switch self {
        case .markdown: "doc.richtext"
        case .html: "globe"
        }
    }
}

/// 文档状态，取值与后端 docs.status 一致。
enum DocStatus: String {
    case draft
    case archived
}

/// 个人文档一级目录，对应后端 doc_folders（仅一层，不可嵌套）。
struct DocFolder: Identifiable, Hashable {
    let id: String
    var name: String
}

/// 文档所属项目的轻量引用（与 BoardProject 的 id / name 对齐）。
struct DocProjectRef: Identifiable, Hashable {
    let id: String
    var name: String
}

/// 文档位置：个人文档（根目录或一级目录）或项目文档，对应后端
/// docs.project / docs.folder 字段的组合（project 为空即个人文档）。
enum DocLocation: Hashable {
    case myDocuments
    case folder(DocFolder)
    case project(DocProjectRef)

    var name: String {
        switch self {
        case .myDocuments: "My Documents"
        case .folder(let folder): folder.name
        case .project(let project): project.name
        }
    }

    var icon: String {
        switch self {
        case .myDocuments: "tray"
        case .folder: "folder"
        case .project: "square.3.layers.3d"
        }
    }
}

/// 一篇文档，字段对应后端 docs 集合。
struct AppDocument: Identifiable, Hashable {
    let id: String
    var title: String
    var content: String
    var kind: DocKind
    var status: DocStatus
    var location: DocLocation
    var revision: Int
    var updatedAt: Date
}

// MARK: - 布局示例数据（接入 API 前的占位数据）

extension AppDocument {
    static let sampleFolders: [DocFolder] = [
        DocFolder(id: "f1", name: "Reading Notes"),
        DocFolder(id: "f2", name: "Ideas"),
    ]

    static let sampleProjects: [DocProjectRef] = [
        DocProjectRef(id: "p1", name: "Workavera iOS App"),
        DocProjectRef(id: "p2", name: "Marketing Site Redesign"),
    ]

    static let sample: [AppDocument] = {
        let folders = sampleFolders
        let projects = sampleProjects

        func daysAgo(_ value: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -value, to: .now) ?? .now
        }

        return [
            AppDocument(
                id: "d1",
                title: "Weekly Sync Notes",
                content: """
                # Weekly Sync

                ## Highlights
                - Board page layout shipped on iOS
                - Notifications page with pull-to-refresh

                ## Next
                - Docs page read-only viewer
                """,
                kind: .markdown, status: .draft, location: .myDocuments,
                revision: 3, updatedAt: daysAgo(0)
            ),
            AppDocument(
                id: "d2",
                title: "Reading: Designing Mobile Kanban",
                content: """
                # Designing Mobile Kanban

                Horizontal columns do not translate well to phones.
                Prefer a single-column list with a state switcher on top.
                """,
                kind: .markdown, status: .draft, location: .folder(folders[0]),
                revision: 1, updatedAt: daysAgo(1)
            ),
            AppDocument(
                id: "d3",
                title: "iOS Release Checklist",
                content: """
                # Release Checklist

                1. Bump version and build number
                2. Archive and upload to App Store Connect
                3. Submit for review
                """,
                kind: .markdown, status: .draft, location: .project(projects[0]),
                revision: 5, updatedAt: daysAgo(2)
            ),
            AppDocument(
                id: "d4",
                title: "Landing Page Copy Draft",
                content: """
                # Hero

                Workavera — your calm workspace for projects, docs and reading.

                ## Feature blocks
                - Board: kanban that stays out of your way
                - Docs: markdown with version history
                """,
                kind: .markdown, status: .draft, location: .project(projects[1]),
                revision: 2, updatedAt: daysAgo(3)
            ),
            AppDocument(
                id: "d5",
                title: "App Ideas Parking Lot",
                content: """
                # Ideas

                - Offline-first sync for board tasks
                - Widget for due-soon tasks
                - Share extension to save links into Reading
                """,
                kind: .markdown, status: .draft, location: .folder(folders[1]),
                revision: 1, updatedAt: daysAgo(4)
            ),
            AppDocument(
                id: "d6",
                title: "API Conventions",
                content: """
                # API Conventions

                - List queries sort by `-updated`
                - Mutations go through custom routes, not collection CRUD
                - Optimistic locking via `revision`
                """,
                kind: .markdown, status: .draft, location: .myDocuments,
                revision: 4, updatedAt: daysAgo(5)
            ),
            AppDocument(
                id: "d7",
                title: "Reading: Offline-First Patterns",
                content: """
                # Offline-First Patterns

                Queue mutations locally, replay on reconnect.
                Conflict resolution: last-writer-wins with revision checks.
                """,
                kind: .markdown, status: .draft, location: .folder(folders[0]),
                revision: 2, updatedAt: daysAgo(6)
            ),
            AppDocument(
                id: "d8",
                title: "Component Status Board",
                content: "<h1>Component Status</h1><p>Avatar: done. Board: in progress.</p>",
                kind: .html, status: .draft, location: .project(projects[0]),
                revision: 1, updatedAt: daysAgo(7)
            ),
            AppDocument(
                id: "d9",
                title: "Meeting Notes Template",
                content: """
                # Meeting Notes — YYYY-MM-DD

                ## Attendees
                ## Agenda
                ## Action items
                """,
                kind: .markdown, status: .draft, location: .myDocuments,
                revision: 1, updatedAt: daysAgo(9)
            ),
            AppDocument(
                id: "d10",
                title: "Old Onboarding Draft",
                content: "# Onboarding\n\nSuperseded by the new flow.",
                kind: .markdown, status: .archived, location: .myDocuments,
                revision: 6, updatedAt: daysAgo(30)
            ),
            AppDocument(
                id: "d11",
                title: "2024 Retrospective",
                content: "# 2024 Retro\n\nWhat went well, what to improve.",
                kind: .markdown, status: .archived, location: .folder(folders[1]),
                revision: 2, updatedAt: daysAgo(60)
            ),
        ]
    }()
}
