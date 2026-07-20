import MarkdownUI
import SwiftUI

struct DocsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DocsStore.self) private var docs
    @State private var showLocationSwitcher = false

    var body: some View {
        Group {
            if !docs.hasLoaded && docs.isLoading {
                ProgressView("Loading documents…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                documentList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Docs")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if docs.view.usesPagination {
                VStack(spacing: 0) {
                    Divider()
                    PaginationBar(
                        pageCount: docs.totalPages,
                        page: pageBinding,
                        alwaysVisible: true
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .task(id: auth.user?.id) {
            await docs.loadIfNeeded(using: auth)
        }
        .alert("Could Not Load Documents", isPresented: errorPresented) {
            Button("OK", role: .cancel) { docs.clearError() }
        } message: {
            Text(docs.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showLocationSwitcher) {
            DocsLocationSwitcherSheet(
                selected: docs.view,
                folders: docs.folders,
                projects: docs.projects
            ) { filter in
                select(filter)
            }
        }
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                locationHeader

                if docs.documents.isEmpty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.text")
                    } description: {
                        if let error = docs.errorMessage {
                            Text(error)
                        } else {
                            Text("No documents match this location and search.")
                        }
                    } actions: {
                        Button("Refresh") {
                            Task { await docs.refresh(using: auth) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 36)
                } else {
                    HStack {
                        Text(docs.label().uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(docs.totalItems) total")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)

                    ForEach(docs.documents) { document in
                        NavigationLink {
                            DocumentDetailView(documentID: document.id)
                        } label: {
                            DocumentRow(
                                document: document,
                                location: docs.locationName(for: document)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
            }
            .padding(20)
        }
        .overlay {
            if docs.isLoading {
                ProgressView()
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await docs.refresh(using: auth)
        }
    }

    private var locationHeader: some View {
        Button {
            showLocationSwitcher = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: locationIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(docs.label())
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(docs.totalItems) documents")
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
    }

    private var locationIcon: String {
        switch docs.view {
        case .myDocuments: "tray"
        case .folder: "folder"
        case .project: "square.3.layers.3d"
        case .archived: "archivebox"
        case .recent: "clock"
        case .pinned: "pin"
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(get: { docs.page }, set: { page in
            Task { await docs.loadPage(page, using: auth) }
        })
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { docs.errorMessage != nil && !docs.documents.isEmpty },
            set: { if !$0 { docs.clearError() } }
        )
    }

    private func select(_ filter: DocsViewFilter) {
        Task { await docs.selectView(filter, using: auth) }
    }
}

private struct DocsLocationSwitcherSheet: View {
    private static let projectsPerPage = 4

    let selected: DocsViewFilter
    let folders: [DocumentFolder]
    let projects: [DocumentProject]
    let onSelect: (DocsViewFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var projectPage: Int

    init(
        selected: DocsViewFilter,
        folders: [DocumentFolder],
        projects: [DocumentProject],
        onSelect: @escaping (DocsViewFilter) -> Void
    ) {
        self.selected = selected
        self.folders = folders
        self.projects = projects
        self.onSelect = onSelect
        let selectedProjectID: String?
        if case .project(let id) = selected {
            selectedProjectID = id
        } else {
            selectedProjectID = nil
        }
        let selectedIndex = projects.firstIndex { $0.id == selectedProjectID } ?? 0
        _projectPage = State(initialValue: selectedIndex / Self.projectsPerPage)
    }

    private var projectPageCount: Int {
        max(1, Int(ceil(Double(projects.count) / Double(Self.projectsPerPage))))
    }

    private var pagedProjects: [DocumentProject] {
        let start = min(projectPage * Self.projectsPerPage, projects.count)
        return Array(projects.dropFirst(start).prefix(Self.projectsPerPage))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    section("Quick Access") {
                        row(.recent, name: "Recent", icon: "clock")
                        rowDivider
                        row(.pinned, name: "Pinned", icon: "pin")
                    }

                    section("Personal") {
                        row(.myDocuments, name: "My Documents", icon: "tray")
                        ForEach(folders) { folder in
                            rowDivider
                            row(
                                .folder(folder.id),
                                name: folder.name,
                                icon: "folder",
                                indented: true
                            )
                        }
                    }

                    section("Projects") {
                        if projects.isEmpty {
                            Text("No projects available")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(pagedProjects.enumerated()), id: \.element.id) { index, project in
                                if index > 0 { rowDivider }
                                row(
                                    .project(project.id),
                                    name: project.name,
                                    icon: "square.3.layers.3d"
                                )
                            }
                            Divider()
                            PaginationBar(
                                pageCount: projectPageCount,
                                page: $projectPage,
                                alwaysVisible: true
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }

                    section("Other") {
                        row(.archived, name: "Archived", icon: "archivebox")
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Browse Documents")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
        _ value: DocsViewFilter,
        name: String,
        icon: String,
        indented: Bool = false
    ) -> some View {
        Button {
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
                if selected == value {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, indented ? 40 : 16)
            .padding(.trailing, 16)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DocumentRow: View {
    let document: DocumentSummary
    let location: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: document.kind == .html ? "chevron.left.forwardslash.chevron.right" : "doc.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(document.kind == .html ? .purple : Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    (document.kind == .html ? Color.purple : Color.accentColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if document.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(document.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Text("\(location) · v\(document.revision)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if document.updatedAt != .distantPast {
                    Text(document.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
    }
}

private struct DocumentDetailView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DocsStore.self) private var docs
    let documentID: String
    @State private var showVersions = false
    @State private var htmlHeight: CGFloat = 120

    private var document: WorkspaceDocument? {
        docs.documentCache[documentID]
    }

    var body: some View {
        Group {
            if let document {
                documentContent(document)
            } else if docs.loadingDocumentIDs.contains(documentID) {
                ProgressView("Loading document…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Document Unavailable",
                    systemImage: "doc.questionmark",
                    description: Text(docs.errorMessage ?? "This document could not be loaded.")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document?.title ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let document {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showVersions = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Version history")

                    if document.status == .draft {
                        Button {
                            Task { await docs.togglePin(id: document.id, using: auth) }
                        } label: {
                            Image(systemName: document.pinned ? "pin.fill" : "pin")
                        }
                        .disabled(docs.pinningDocumentIDs.contains(document.id))
                        .accessibilityLabel(document.pinned ? "Unpin" : "Pin")
                    }
                }
            }
        }
        .task {
            await docs.loadDocument(id: documentID, using: auth)
        }
        .sheet(isPresented: $showVersions) {
            if let document {
                DocumentVersionsView(document: document)
            }
        }
    }

    private func documentContent(_ document: WorkspaceDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                documentHeader(document)
                Divider()
                if document.kind == .html {
                    HTMLView(html: document.content, contentHeight: $htmlHeight)
                        .frame(height: max(htmlHeight, 1))
                        .frame(maxWidth: .infinity)
                } else {
                    MarkdownDocumentView(content: document.content)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await docs.loadDocument(id: document.id, using: auth, force: true)
        }
    }

    private func documentHeader(_ document: WorkspaceDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(document.kind == .html ? "HTML" : "MARKDOWN")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                if document.status == .archived {
                    Text("ARCHIVED")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text("\(docs.locationName(for: document)) · Version \(document.revision)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Updated \(document.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownDocumentView: View {
    let content: String

    var body: some View {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("Empty Document", systemImage: "doc")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
        } else {
            Markdown(content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DocumentVersionsView: View {
    @Environment(AuthStore.self) private var auth
    let document: WorkspaceDocument
    @State private var versions: [DocumentVersion] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading versions…")
                } else if versions.isEmpty {
                    ContentUnavailableView(
                        "No Version History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(errorMessage ?? "No saved versions are available.")
                    )
                } else {
                    List(versions) { version in
                        NavigationLink {
                            DocumentVersionDetailView(
                                documentID: document.id,
                                kind: document.kind,
                                revision: version.revision
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version \(version.revision) · \(version.title)")
                                    .font(.subheadline.weight(.medium))
                                Text("\(version.source.capitalized) · \(version.createdAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    versions = try await auth.loadDocumentVersions(id: document.id)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DocumentVersionDetailView: View {
    @Environment(AuthStore.self) private var auth
    let documentID: String
    let kind: DocumentKind
    let revision: Int
    @State private var version: DocumentVersion?
    @State private var errorMessage: String?
    @State private var htmlHeight: CGFloat = 120

    var body: some View {
        Group {
            if let version {
                if kind == .html {
                    ScrollView {
                        HTMLView(
                            html: version.content ?? "",
                            contentHeight: $htmlHeight
                        )
                        .frame(height: max(htmlHeight, 1))
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    }
                } else {
                    ScrollView {
                        MarkdownDocumentView(content: version.content ?? "")
                            .padding(20)
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Version Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading version…")
            }
        }
        .navigationTitle("Version \(revision)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                version = try await auth.loadDocumentVersion(id: documentID, revision: revision)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
