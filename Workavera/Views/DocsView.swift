import MarkdownUI
import SwiftUI
import UIKit

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
    @State private var showShare = false

    private var document: WorkspaceDocument? {
        docs.documentCache[documentID]
    }

    /// Archiving already takes a public link out of service, and the server
    /// refuses to publish an archived document, so the action is offered only
    /// where it can do something.
    private var canShare: Bool {
        guard let document, let userID = auth.user?.id else { return false }
        return document.status == .draft && document.ownerID == userID
    }

    private var isShared: Bool {
        docs.shares[documentID] != nil
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
            if canShare {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        // Tinted while a link is live, as in the web app: the
                        // fact that a document is public belongs on the
                        // document, not only inside the sheet that made it so.
                        Image(systemName: isShared ? "link" : "square.and.arrow.up")
                            .foregroundStyle(isShared ? Color.green : Color.accentColor)
                    }
                    .accessibilityLabel(isShared ? "Shared publicly" : "Share document")
                }
            }
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
        .task(id: canShare) {
            // Only decides how the toolbar reads, so a failure here stays
            // quiet; opening the sheet retries and reports it properly.
            guard canShare, !docs.resolvedShareIDs.contains(documentID) else { return }
            try? await docs.loadShare(id: documentID, using: auth)
        }
        .sheet(isPresented: $showVersions) {
            if let document {
                DocumentVersionsView(document: document)
            }
        }
        .sheet(isPresented: $showShare) {
            if let document {
                DocumentShareView(document: document)
            }
        }
    }

    /// The body gets the whole screen and scrolls itself: metadata above it takes
    /// away screen the document needs, and a page with sticky elements of its own
    /// is left scrolling inside a strip.
    @ViewBuilder
    private func documentContent(_ document: WorkspaceDocument) -> some View {
        Group {
            if document.kind == .html {
                // Reaches the screen edges the way the markdown ScrollView
                // below does; without this the web view is laid out inside the
                // safe area and the document stops at a seam under the bar.
                HTMLView(html: document.content)
                    .ignoresSafeArea(edges: .vertical)
            } else {
                ScrollView {
                    MarkdownDocumentView(content: document.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.always)
                .refreshable {
                    await docs.loadDocument(id: document.id, using: auth, force: true)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let error = docs.errorMessage {
                InlineErrorBanner(message: error) {
                    Task { await docs.loadDocument(id: document.id, using: auth, force: true) }
                }
                .padding(.horizontal, 20)
            }
        }
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
                .workspaceDocumentMarkdownStyle()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Publishes a document to a public link (web app ShareDocumentButton).
/// Publishing pins the revision the link serves, so the snapshot stays where it
/// is while editing continues; changing the expiry leaves it alone and only
/// "Publish Latest" moves it.
private struct DocumentShareView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(DocsStore.self) private var docs
    let document: WorkspaceDocument

    /// The store owns the link, so the toolbar behind this sheet reflects
    /// publishing and revoking without being told twice.
    private var share: DocumentShare? { docs.shares[document.id] }
    private var hasLoaded: Bool { docs.resolvedShareIDs.contains(document.id) }

    @State private var expiry: DocumentShareExpiry = .never
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copied = false
    // Publishing roughly triples the height of the sheet. Left at .medium it
    // would hide the link it just created below the fold, so the sheet grows
    // with what it has to show.
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        """
                        Anyone with the link can read this document without \
                        signing in. The link serves the revision you publish, \
                        so later edits stay private until you publish again.
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    InlineErrorListSection(message: errorMessage) {
                        Task { await load() }
                    }
                }

                if !hasLoaded {
                    Section { ProgressView("Loading link…") }
                } else if let share {
                    linkSection(share)
                    revisionSection(share)
                    expirySection
                    Section {
                        Button(role: .destructive) {
                            Task { await revoke() }
                        } label: {
                            Text("Revoke Link").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(isWorking)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    expirySection
                    Section {
                        Button {
                            Task { await publish(republish: false, expiry: expiry) }
                        } label: {
                            Text(isWorking ? "Creating…" : "Create Link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWorking)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("Share Document")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    @ViewBuilder
    private func linkSection(_ share: DocumentShare) -> some View {
        Section("Public Link") {
            if let url = auth.publicDocumentURL(for: share) {
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button {
                    copy(url)
                } label: {
                    Label(
                        copied ? "Copied" : "Copy Link",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
                }
                ShareLink(item: url) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
            } else {
                Text("The server address could not be read.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func revisionSection(_ share: DocumentShare) -> some View {
        Section {
            LabeledContent("Published revision", value: "\(share.revision)")
            if share.revision < document.revision {
                Button("Publish Latest") {
                    Task { await publish(republish: true, expiry: expiry) }
                }
                .disabled(isWorking)
            }
        } footer: {
            Text(
                share.revision < document.revision
                    ? "The document is at revision \(document.revision). Publish to move the link to it."
                    : "The link serves the newest revision."
            )
        }
    }

    private var expirySection: some View {
        Section {
            Picker("Expires", selection: expirySelection) {
                ForEach(expiryOptions) { option in
                    Text(label(for: option)).tag(option)
                }
            }
            .disabled(isWorking)
        }
    }

    /// Changing the expiry of a published link takes effect at once, matching
    /// the web app; before there is a link it only stages the choice.
    private var expirySelection: Binding<DocumentShareExpiry> {
        Binding(get: { expiry }, set: { option in
            expiry = option
            if share != nil {
                Task { await publish(republish: false, expiry: option) }
            }
        })
    }

    /// "Keep" is offered only for a link that already expires, so every other
    /// change to it leaves that date where the creator set it.
    private var expiryOptions: [DocumentShareExpiry] {
        DocumentShareExpiry.allCases.filter { $0 != .keep || share?.expiresAt != nil }
    }

    private func label(for option: DocumentShareExpiry) -> String {
        guard option == .keep, let expiresAt = share?.expiresAt else { return option.label }
        return "Keep \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
    }

    /// The label carries its own confirmation, the way the code-block copy
    /// button does: a sheet this small has nowhere to put a banner.
    private func copy(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }

    private func load() async {
        errorMessage = nil
        // The toolbar may already have resolved the link, so open at the right
        // size instead of growing once the refresh lands.
        syncToShare(animated: false)
        do {
            try await docs.loadShare(id: document.id, using: auth)
            syncToShare()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publish(republish: Bool, expiry option: DocumentShareExpiry) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await docs.publishShare(
                id: document.id,
                expires: option.requestValue(share: share),
                republish: republish,
                using: auth
            )
            syncToShare()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await docs.revokeShare(id: document.id, using: auth)
            syncToShare()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Brings the picker and the sheet's height in line with the link the
    /// store now holds.
    private func syncToShare(animated: Bool = true) {
        expiry = share?.expiresAt == nil ? .never : .keep
        let target: PresentationDetent = share == nil ? .medium : .large
        if animated {
            withAnimation { detent = target }
        } else {
            detent = target
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

    var body: some View {
        Group {
            if let version {
                if kind == .html {
                    HTMLView(html: version.content ?? "")
                        .ignoresSafeArea(edges: .vertical)
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
