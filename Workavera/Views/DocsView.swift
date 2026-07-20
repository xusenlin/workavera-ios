import MarkdownUI
import SwiftUI

/// 文档页面（只读）：按位置筛选（我的文档 / 一级目录 / 项目 / 已归档），
/// 列表 + 分页，支持移动位置、归档、二次确认删除（均为本地示例数据操作）。
/// 当前数据来自 AppDocument.sample，接入 API 后替换为真实数据。
struct DocsView: View {
    @State private var documents = AppDocument.sample
    @State private var filter: DocFilter = .location(.myDocuments)
    @State private var page = 0
    @State private var selectedDoc: AppDocument?
    @State private var docToMove: AppDocument?
    @State private var docToDelete: AppDocument?
    @State private var showLocationSheet = false

    private let pageSize = 8

    private var filtered: [AppDocument] {
        documents.filter { doc in
            switch filter {
            case .location(let location):
                doc.status == .draft && doc.location == location
            case .archived:
                doc.status == .archived
            }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(filtered.count) / Double(pageSize))))
    }

    private var pageDocuments: [AppDocument] {
        Array(filtered.dropFirst(page * pageSize).prefix(pageSize))
    }

    private var locationCounts: [DocFilter: Int] {
        var counts: [DocFilter: Int] = [.archived: documents.filter { $0.status == .archived }.count]
        for location in allLocations {
            counts[.location(location)] = documents.filter { $0.status == .draft && $0.location == location }.count
        }
        return counts
    }

    private var allLocations: [DocLocation] {
        [.myDocuments]
            + AppDocument.sampleFolders.map { .folder($0) }
            + AppDocument.sampleProjects.map { .project($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                locationHeader
                documentList
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Docs")
        .navigationDestination(item: $selectedDoc) { doc in
            DocDetailView(document: doc)
        }
        .sheet(isPresented: $showLocationSheet) {
            LocationSheet(
                filter: filter,
                counts: locationCounts,
                folders: AppDocument.sampleFolders,
                projects: AppDocument.sampleProjects
            ) { newFilter in
                withAnimation(.easeInOut(duration: 0.15)) {
                    filter = newFilter
                    page = 0
                }
            }
        }
        .sheet(item: $docToMove) { doc in
            MoveDocSheet(
                current: doc.location,
                folders: AppDocument.sampleFolders,
                projects: AppDocument.sampleProjects
            ) { destination in
                move(doc, to: destination)
            }
        }
        .confirmationDialog(
            "Delete this document?",
            isPresented: Binding(
                get: { docToDelete != nil },
                set: { if !$0 { docToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let doc = docToDelete {
                Button("Delete \"\(doc.title)\"", role: .destructive) {
                    delete(doc)
                }
                Button("Cancel", role: .cancel) {
                    docToDelete = nil
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .safeAreaInset(edge: .bottom) {
            if pageCount > 1 {
                VStack(spacing: 0) {
                    Divider()
                    PaginationBar(pageCount: pageCount, page: $page)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    // MARK: - 当前位置（点按弹出位置切换，与 Board 项目切换一致）

    private var locationHeader: some View {
        Button {
            showLocationSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: filter.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(filter.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(filtered.count) documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - 文档列表

    @ViewBuilder
    private var documentList: some View {
        if pageDocuments.isEmpty {
            Text("No documents here")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundStyle(Color(.separator))
                )
                .padding(.horizontal, 20)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(pageDocuments.enumerated()), id: \.element.id) { index, doc in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 62)
                    }
                    row(doc)
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 20)
        }
    }

    private func row(_ doc: AppDocument) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedDoc = doc
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: doc.kind.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(doc.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Label(doc.location.name, systemImage: doc.location.icon)
                            Text("·")
                            Text(doc.updatedAt.formatted(.relative(presentation: .named)))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    docToMove = doc
                } label: {
                    Label("Move", systemImage: "folder")
                }

                Button {
                    toggleArchive(doc)
                } label: {
                    if doc.status == .archived {
                        Label("Unarchive", systemImage: "archivebox")
                    } else {
                        Label("Archive", systemImage: "archivebox")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    docToDelete = doc
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 本地数据操作（接入 API 后改为调用后端路由）

    private func move(_ doc: AppDocument, to destination: DocLocation) {
        guard let index = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documents[index].location = destination
    }

    private func toggleArchive(_ doc: AppDocument) {
        guard let index = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documents[index].status = doc.status == .archived ? .draft : .archived
    }

    private func delete(_ doc: AppDocument) {
        documents.removeAll { $0.id == doc.id }
        docToDelete = nil
    }
}

// MARK: - 文档详情（只读）

private struct DocDetailView: View {
    let document: AppDocument

    @State private var htmlHeight: CGFloat = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.title)
                        .font(.title3.bold())
                    HStack(spacing: 8) {
                        Label(document.location.name, systemImage: document.location.icon)
                        Text("·")
                        Text("v\(document.revision)")
                        Text("·")
                        Text(document.updatedAt.formatted(.relative(presentation: .named)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()

                switch document.kind {
                case .markdown:
                    markdownContent
                case .html:
                    htmlContent
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var markdownContent: some View {
        Markdown(document.content)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// HTML 文档用 WKWebView 沙箱渲染（禁用 JS 与链接跳转），高度自适应内容。
    private var htmlContent: some View {
        HTMLView(html: document.content, contentHeight: $htmlHeight)
            .frame(height: max(htmlHeight, 1))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - 位置筛选（当前位置 / 已归档）

private enum DocFilter: Hashable {
    case location(DocLocation)
    case archived

    var title: String {
        switch self {
        case .location(let location): location.name
        case .archived: "Archived"
        }
    }

    var icon: String {
        switch self {
        case .location(let location): location.icon
        case .archived: "archivebox"
        }
    }
}

// MARK: - 位置切换（个人文档目录缩进一层展示层级）

private struct LocationSheet: View {
    let filter: DocFilter
    let counts: [DocFilter: Int]
    let folders: [DocFolder]
    let projects: [DocProjectRef]
    let onSelect: (DocFilter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Personal") {
                        row(.location(.myDocuments), name: "My Documents", icon: "tray")
                        ForEach(folders) { folder in
                            rowDivider
                            row(.location(.folder(folder)), name: folder.name, icon: "folder", indented: true)
                        }
                    }

                    section("Projects") {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            if index > 0 { rowDivider }
                            row(.location(.project(project)), name: project.name, icon: "square.3.layers.3d")
                        }
                    }

                    section("Other") {
                        row(.archived, name: "Archived", icon: "archivebox")
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 54)
    }

    private func row(
        _ value: DocFilter,
        name: String,
        icon: String,
        indented: Bool = false
    ) -> some View {
        let isSelected = filter == value
        return Button {
            onSelect(value)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(counts[value] ?? 0)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            // 一级目录向右缩进，体现 "My Documents 下的子层级"
            .padding(.leading, indented ? 40 : 16)
            .padding(.trailing, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 移动位置

private struct MoveDocSheet: View {
    let current: DocLocation
    let folders: [DocFolder]
    let projects: [DocProjectRef]
    let onMove: (DocLocation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    destinationSection(title: "My Documents", destinations: [.myDocuments] + folders.map { .folder($0) })
                    destinationSection(title: "Projects", destinations: projects.map { .project($0) })
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Move Document")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func destinationSection(title: String, destinations: [DocLocation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(destinations.enumerated()), id: \.element) { index, destination in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 54)
                    }
                    Button {
                        onMove(destination)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: destination.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                            Text(destination.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if destination == current {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}
