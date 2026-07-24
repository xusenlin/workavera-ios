import MarkdownUI
import SwiftUI

struct DocsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DocsStore.self) private var docs
    @State private var showLocationSwitcher = false
    @State private var deleteTarget: DocumentSummary?
    @State private var searchInput = ""

    var body: some View {
        CachedContentView(
            isLoading: docs.isLoading,
            hasLoaded: docs.hasLoaded,
            loadingTitle: "Loading documents…"
        ) {
            documentList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Docs")
        .searchable(
            text: $searchInput,
            prompt: "Search documents"
        )
        .onSubmit(of: .search) {
            Task { await docs.search(searchInput, using: auth) }
        }
        .onChange(of: searchInput) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.isEmpty, !docs.query.isEmpty {
                Task { await docs.search("", using: auth) }
            }
        }
        .task(id: auth.user?.id) {
            await docs.loadForPresentation(using: auth)
            searchInput = docs.query
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
        .alert("Delete document?", isPresented: deletePresented) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                guard let document = deleteTarget else { return }
                Task {
                    if await docs.delete(id: document.id, using: auth) {
                        deleteTarget = nil
                    }
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let error = docs.errorMessage {
                    InlineErrorBanner(message: error) {
                        Task { await docs.refresh(using: auth) }
                    }
                }

                locationHeader

                if docs.documents.isEmpty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.text")
                    } description: {
                        Text("No documents match this location and search.")
                    } actions: {
                        if docs.query.isEmpty {
                            Button("Refresh") {
                                Task { await docs.refresh(using: auth) }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Clear Search") {
                                clearSearch()
                            }
                            .buttonStyle(.bordered)
                        }
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
                        HStack(spacing: 12) {
                            NavigationLink {
                                DocumentDetailView(documentID: document.id)
                            } label: {
                                DocumentRow(
                                    document: document,
                                    location: docs.locationName(for: document)
                                )
                            }
                            .buttonStyle(.plain)

                            if docs.pinningDocumentIDs.contains(document.id)
                                || docs.mutatingDocumentIDs.contains(document.id)
                            {
                                ProgressView().controlSize(.small)
                                    .frame(width: 28, height: 28)
                            } else {
                                documentMenu(document)
                            }
                        }
                        .padding(16)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }

                documentPagination
            }
            .padding(20)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await docs.refresh(using: auth)
        }
    }

    @ViewBuilder
    private var documentPagination: some View {
        if docs.view.usesPagination, docs.hasLoaded, docs.totalItems > 0 {
            ListPaginationFooter(
                pageCount: docs.totalPages,
                page: pageBinding
            )
            .padding(.horizontal, 2)
            .padding(.top, 2)
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

    private func select(_ filter: DocsViewFilter) {
        Task { await docs.selectView(filter, using: auth) }
    }

    private func clearSearch() {
        searchInput = ""
        Task { await docs.search("", using: auth) }
    }

    private func documentMenu(_ document: DocumentSummary) -> some View {
        Menu {
            if document.status == .draft {
                Button {
                    Task { await docs.togglePin(id: document.id, using: auth) }
                } label: {
                    Label(
                        document.pinned ? "Unpin" : "Pin",
                        systemImage: document.pinned ? "pin.slash" : "pin"
                    )
                }

                Button {
                    Task { await docs.setArchived(id: document.id, archived: true, using: auth) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } else {
                Button {
                    Task { await docs.setArchived(id: document.id, archived: false, using: auth) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()
            Button(role: .destructive) { deleteTarget = document } label: {
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

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var deleteMessage: String {
        guard let deleteTarget else { return "This document will be permanently removed." }
        return "“\(deleteTarget.title)” will be permanently removed. This action cannot be undone."
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
                            ListPaginationFooter(
                                pageCount: projectPageCount,
                                page: $projectPage
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
        HStack(spacing: 14) {
            Image(systemName: document.kind == .html ? "chevron.left.forwardslash.chevron.right" : "doc.text")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(document.kind == .html ? .purple : Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    (document.kind == .html ? Color.purple : Color.accentColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(document.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if document.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    /// Location, version, and last-updated time on a single line.
    private var metaLine: String {
        var parts = ["\(location) · v\(document.revision)"]
        if document.updatedAt != .distantPast {
            parts.append(document.updatedAt.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
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
            if document != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVersions = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Version history")
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
                if let error = docs.errorMessage {
                    InlineErrorBanner(message: error) {
                        Task { await docs.loadDocument(id: document.id, using: auth, force: true) }
                    }
                    .padding(.horizontal, 20)
                }
                documentHeader(document)
                    .padding(.horizontal, 20)
                Divider()
                    .padding(.horizontal, 20)
                if document.kind == .html {
                    HTMLView(html: document.content, contentHeight: $htmlHeight)
                        .frame(height: max(htmlHeight, 1))
                        .frame(maxWidth: .infinity)
                } else {
                    MarkdownDocumentView(content: document.content)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
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
                if isLoading && versions.isEmpty {
                    ProgressView("Loading versions…")
                } else {
                    List {
                        if let errorMessage {
                            InlineErrorListSection(message: errorMessage) {
                                Task { await reloadFromNetwork() }
                            }
                        }
                        if versions.isEmpty {
                            ContentUnavailableView(
                                "No Version History",
                                systemImage: "clock.arrow.circlepath",
                                description: Text("No saved versions are available.")
                            )
                        } else {
                            ForEach(versions) { version in
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
                }
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await load()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do {
            versions = try await auth.loadDocumentVersions(
                id: document.id,
                strategy: .cacheOnly
            )
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            // Cache misses are expected and are never user-facing.
        }
        guard !Task.isCancelled else { return }
        await reloadFromNetwork()
    }

    private func reloadFromNetwork() async {
        if versions.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            versions = try await auth.loadDocumentVersions(
                id: document.id,
                strategy: .networkOnly
            )
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
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
        .safeAreaInset(edge: .top) {
            if let errorMessage {
                InlineErrorBanner(message: errorMessage) {
                    Task { await reloadFromNetwork() }
                }
                .padding(.horizontal, 20)
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            version = try await auth.loadDocumentVersion(
                id: documentID,
                revision: revision,
                strategy: .cacheOnly
            )
        } catch is CancellationError {
            return
        } catch {
            // Cache misses are expected and are never user-facing.
        }
        guard !Task.isCancelled else { return }
        await reloadFromNetwork()
    }

    private func reloadFromNetwork() async {
        do {
            version = try await auth.loadDocumentVersion(
                id: documentID,
                revision: revision,
                strategy: .networkOnly
            )
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
