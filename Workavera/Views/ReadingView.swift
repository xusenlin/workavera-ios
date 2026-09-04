import SwiftUI

struct ReadingView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ReadingStore.self) private var store
    @Environment(ReadingDiscoverStore.self) private var discover

    @State private var searchInput = ""
    @State private var selectedItem: ReadingItem?
    @State private var deleteTarget: ReadingItem?
    @State private var showAddSheet = false
    @State private var showDiscoverSheet = false

    var body: some View {
        CachedContentView(
            isLoading: store.isLoading,
            hasLoaded: store.hasLoaded,
            loadingTitle: "Loading reading list…"
        ) {
            ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = store.errorMessage {
                            InlineErrorBanner(message: error) {
                                Task { await store.refresh(using: auth) }
                            }
                            .padding(.horizontal, 20)
                        }
                        filterPicker
                        summaryLine
                        itemList
                        readingPagination
                    }
                    .padding(.vertical, 20)
                }
            .refreshable { await store.refresh(using: auth) }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reading")
        .searchable(
            text: $searchInput,
            prompt: "Search title, URL, tags or summary"
        )
        .onSubmit(of: .search) {
            Task { await store.search(searchInput, using: auth) }
        }
        .onChange(of: searchInput) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.isEmpty, !store.query.isEmpty {
                Task { await store.search("", using: auth) }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showDiscoverSheet = true } label: {
                    Image(systemName: "sparkle.magnifyingglass")
                }
                .accessibilityLabel("Discover from subscriptions")
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add reading item")
            }
        }
        .task(id: auth.user?.id) {
            // Subscriptions and candidates belong to the signed-in user.
            discover.reset()
            await store.loadForPresentation(using: auth)
            searchInput = store.query
        }
        .sheet(item: $selectedItem) { item in
            ReadingDetailSheet(initialItem: item)
        }
        .sheet(isPresented: $showAddSheet) {
            AddReadingItemSheet()
        }
        .sheet(isPresented: $showDiscoverSheet) {
            ReadingDiscoverView()
        }
        .alert("Delete reading item?", isPresented: deletePresented) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                guard let item = deleteTarget else { return }
                Task {
                    if await store.delete(item, using: auth) {
                        deleteTarget = nil
                    }
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }

    @ViewBuilder
    private var readingPagination: some View {
        if store.hasLoaded, store.totalItems > 0 {
            ListPaginationFooter(
                pageCount: store.totalPages,
                page: pageBinding
            )
            .padding(.horizontal, 20)
            .padding(.top, 2)
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReadingListFilter.allCases) { filter in
                    let selected = store.filter == filter
                    WorkspaceFilterChip(
                        title: filter.label,
                        isSelected: selected,
                        systemImage: filter.icon
                    ) {
                        Task { await store.selectFilter(filter, using: auth) }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var summaryLine: some View {
        Text("\(store.totalItems) \(store.filter == .archived ? "archived" : "matching") · \(store.unreadCount) unread")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var itemList: some View {
        if store.items.isEmpty {
            ContentUnavailableView {
                Label("Nothing Here Yet", systemImage: store.filter.icon)
            } description: {
                Text(emptyDescription)
            } actions: {
                if store.filter == .active && store.query.isEmpty {
                    Button("Add Link") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(store.items) { item in
                    readingCard(item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func readingCard(_ item: ReadingItem) -> some View {
        HStack(spacing: 12) {
            Button { selectedItem = item } label: {
                HStack(spacing: 12) {
                    Text(String(item.host.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.accentColor.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if item.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(item.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Text(item.host)
                            Text("·")
                            Text(item.status.label)
                            Text("·")
                            Text(item.updatedAt.formatted(.relative(presentation: .named)))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.mutatingItemIDs.contains(item.id) {
                ProgressView().controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                itemMenu(item)
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func itemMenu(_ item: ReadingItem) -> some View {
        Menu {
            if item.status != .archived {
                Button {
                    Task { _ = try? await store.togglePin(item, using: auth) }
                } label: {
                    Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
                }

                Button {
                    let status: ReadingStatus = item.status == .unread ? .read : .unread
                    Task { _ = try? await store.updateStatus(item, status: status, using: auth) }
                } label: {
                    Label(
                        item.status == .unread ? "Mark as Read" : "Mark as Unread",
                        systemImage: item.status == .unread ? "checkmark.circle" : "circle"
                    )
                }

                Button {
                    Task { _ = try? await store.updateStatus(item, status: .archived, using: auth) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } else {
                Button {
                    Task { _ = try? await store.updateStatus(item, status: .unread, using: auth) }
                } label: {
                    Label("Restore as Unread", systemImage: "arrow.uturn.backward")
                }
            }

            Divider()
            Button(role: .destructive) { deleteTarget = item } label: {
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

    private var pageBinding: Binding<Int> {
        Binding(
            get: { store.page },
            set: { newPage in Task { await store.loadPage(newPage, using: auth) } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var deleteMessage: String {
        guard let deleteTarget else { return "This item will be permanently removed." }
        return "“\(deleteTarget.title)” will be permanently removed. This action cannot be undone."
    }

    private var emptyDescription: String {
        if !store.query.isEmpty { return "Try another search." }
        return switch store.filter {
        case .active: "Add a link to start your reading library."
        case .unread: "No unread items remain."
        case .read: "Items you mark as read will appear here."
        case .pinned: "Pin important references for quick access."
        case .archived: "Archived items will appear here."
        }
    }
}

private struct AddReadingItemSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ReadingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var title = ""
    @State private var description = ""
    @State private var tags = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    TextField("https://example.com/article", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Title", text: $title)
                }
                Section("Details") {
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Tags, separated by commas", text: $tags)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Add Reading Item")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(isSaving || !isValid)
                }
            }
            .alert("Could Not Add Item", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var normalizedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let components = URLComponents(string: normalizedURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false else { return false }
        return true
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let input = ReadingItemInput(
            url: normalizedURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        )
        do {
            _ = try await store.create(input, using: auth)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReadingDetailSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ReadingStore.self) private var store
    @Environment(LLMSettingsStore.self) private var modelStore
    @Environment(\.openURL) private var openURL

    @State private var item: ReadingItem
    @State private var confirmSummarize = false
    @State private var consentModel: LLMModelConfiguration?
    @State private var showAIConsent = false

    private let aiConsentStore = AIConsentStore()

    init(initialItem: ReadingItem) {
        _item = State(initialValue: initialItem)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title).font(.title3.bold())
                            if item.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text("\(item.host) · \(item.status.label) · \(item.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !item.description.isEmpty {
                        detailSection(title: "Description", text: item.description)
                    }
                    if !item.summary.isEmpty {
                        detailSection(title: "Summary", text: item.summary)
                    }
                    if !item.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Points").font(.headline)
                            ForEach(Array(item.keyPoints.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Color.accentColor).frame(width: 5, height: 5).padding(.top, 7)
                                    Text(point).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !item.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(item.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                        }
                    }

                    Button {
                        if let url = URL(string: item.url) { openURL(url) }
                    } label: {
                        Label("Open Original Article", systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        requestSummary()
                    } label: {
                        Label(
                            item.summary.isEmpty ? "Fetch & Summarize" : "Regenerate Summary",
                            systemImage: "wand.and.stars"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        store.mutatingItemIDs.contains(item.id)
                            || modelStore.isLoadingModels
                            || defaultModel == nil
                    )
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let updated = try? await store.togglePin(item, using: auth) {
                                item = updated
                            }
                        }
                    } label: {
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                    }
                    .disabled(item.status == .archived || store.mutatingItemIDs.contains(item.id))

                    Menu {
                        if item.status == .unread {
                            Button("Mark as Read", systemImage: "checkmark.circle") {
                                updateStatus(.read)
                            }
                        } else if item.status == .read {
                            Button("Mark as Unread", systemImage: "circle") {
                                updateStatus(.unread)
                            }
                        }
                        if item.status != .archived {
                            Button("Archive", systemImage: "archivebox") {
                                updateStatus(.archived)
                            }
                        } else {
                            Button("Restore as Unread", systemImage: "arrow.uturn.backward") {
                                updateStatus(.unread)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .alert("Fetch and summarize?", isPresented: $confirmSummarize) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    Task {
                        if let updated = try? await store.summarize(item, using: auth) {
                            item = updated
                        }
                    }
                }
            } message: {
                Text("The server will fetch the URL and overwrite any existing extracted content, summary, and key points.")
            }
            .alert(
                "Allow AI Data Sharing?",
                isPresented: $showAIConsent,
                presenting: consentModel
            ) { model in
                Button("Not Now", role: .cancel) {
                    consentModel = nil
                }
                Button("Allow and Summarize") {
                    guard let userID = auth.user?.id else { return }
                    aiConsentStore.authorize(userID: userID, modelID: model.id)
                    consentModel = nil
                    summarize()
                }
            } message: { model in
                Text(
                    """
                    To generate a summary, the article content will be sent to this AI model:

                    \(model.baseURL)
                    """
                )
            }
            .task(id: auth.user?.id) {
                await modelStore.loadModelsForPresentation(using: auth)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var defaultModel: LLMModelConfiguration? {
        modelStore.models.first(where: \.isDefault) ?? modelStore.models.first
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func updateStatus(_ status: ReadingStatus) {
        Task {
            if let updated = try? await store.updateStatus(item, status: status, using: auth) {
                item = updated
            }
        }
    }

    private func requestSummary() {
        guard let userID = auth.user?.id, let model = defaultModel else { return }
        if aiConsentStore.isAuthorized(userID: userID, modelID: model.id) {
            confirmSummarize = true
        } else {
            consentModel = model
            showAIConsent = true
        }
    }

    private func summarize() {
        Task {
            if let updated = try? await store.summarize(item, using: auth) {
                item = updated
            }
        }
    }
}
