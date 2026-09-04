import MarkdownUI
import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showArchived = false
    @State private var searchInput = ""
    @State private var renameTarget: ChatConversation?
    @State private var renameDraft = ""
    @State private var deleteTarget: ChatConversation?
    @State private var navigationConversationID: String?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
                    .searchable(
                        text: $searchInput,
                        placement: .toolbar,
                        prompt: "Search conversations"
                    )
            } else {
                conversationPane(usesNavigationLinks: true)
                    .searchable(
                        text: $searchInput,
                        prompt: "Search conversations"
                    )
            }
        }
        .background(Color(.systemGroupedBackground))
        .onSubmit(of: .search) {
            Task { await store.search(searchInput, using: auth) }
        }
        .onChange(of: searchInput) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.isEmpty, !store.query.isEmpty {
                Task { await store.search("", using: auth) }
            }
        }
        .navigationDestination(item: $navigationConversationID) { id in
            ChatConversationDetailView(conversationID: id)
                .onAppear { store.select(id) }
        }
        .onChange(of: navigationConversationID) { oldValue, newValue in
            // Refresh the list only when returning from a conversation.
            if oldValue != nil, newValue == nil {
                Task { await store.refresh(using: auth) }
            }
        }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showArchived = true } label: {
                    Image(systemName: "archivebox")
                }
                .accessibilityLabel("Archived conversations")

                Button {
                    createConversation()
                } label: {
                    if store.isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .disabled(store.isCreating)
                .accessibilityLabel("New conversation")
            }
        }
        .task(id: auth.user?.id) {
            await store.loadForPresentation(using: auth)
            searchInput = store.query
        }
        .sheet(isPresented: $showArchived) {
            ArchivedConversationsView()
        }
        .alert("Rename conversation", isPresented: renamePresented) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                guard let conversation = renameTarget else { return }
                Task {
                    do {
                        try await store.rename(conversation, title: renameDraft, using: auth)
                        renameTarget = nil
                    } catch {
                        // ChatStore exposes the request error inline.
                    }
                }
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Use a short title that makes this conversation easy to find.")
        }
        .alert("Delete conversation?", isPresented: deletePresented) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                guard let conversation = deleteTarget else { return }
                Task {
                    if await store.delete(conversation, using: auth) {
                        deleteTarget = nil
                    }
                }
            }
        } message: {
            Text("This permanently deletes \(deleteTarget?.title ?? "the conversation") and all of its messages.")
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            conversationPane(usesNavigationLinks: false)
                .frame(minWidth: 270, idealWidth: 310, maxWidth: 340)
            Divider()
            if let conversation = store.selectedConversation {
                ChatConversationDetailView(conversationID: conversation.id)
            } else {
                ChatConversationEmptyView {
                    createConversation()
                }
            }
        }
    }

    private func conversationPane(usesNavigationLinks: Bool) -> some View {
        CachedContentView(
            isLoading: store.isLoading,
            hasLoaded: store.hasLoaded,
            loadingTitle: "Loading conversations…"
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = store.errorMessage {
                        InlineErrorBanner(message: error) {
                            Task { await store.refresh(using: auth) }
                        }
                        .padding(.horizontal, 12)
                    }

                    conversationList(usesNavigationLinks: usesNavigationLinks)

                    conversationPagination
                }
                .padding(.vertical, 12)
            }
            .refreshable { await store.refresh(using: auth) }
        }
    }

    @ViewBuilder
    private func conversationList(usesNavigationLinks: Bool) -> some View {
        if store.conversations.isEmpty {
            ContentUnavailableView {
                Label(
                    store.query.isEmpty ? "No Conversations" : "No Matches",
                    systemImage: store.query.isEmpty
                        ? "bubble.left.and.bubble.right"
                        : "magnifyingglass"
                )
            } description: {
                Text(
                    store.query.isEmpty
                        ? "Create a conversation to start working with your assistant."
                        : "No conversations match “\(store.query)”."
                )
            } actions: {
                if store.query.isEmpty {
                    Button("New Conversation") {
                        createConversation()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isCreating)
                } else {
                    Button("Clear Search") {
                        clearSearch()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(store.conversations) { conversation in
                    conversationRow(
                        conversation,
                        usesNavigationLink: usesNavigationLinks
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var conversationPagination: some View {
        if store.hasLoaded, store.totalItems > 0 {
            ListPaginationFooter(
                pageCount: store.totalPages,
                page: activePageBinding
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func createConversation() {
        searchInput = ""
        Task {
            guard let created = try? await store.create(using: auth) else { return }
            // Compact layout navigates into the new conversation; the regular
            // split view already shows it via the selected conversation.
            if horizontalSizeClass != .regular {
                navigationConversationID = created.id
            }
        }
    }

    private func clearSearch() {
        searchInput = ""
        Task { await store.search("", using: auth) }
    }

    private func conversationRow(
        _ conversation: ChatConversation,
        usesNavigationLink: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if usesNavigationLink {
                Button {
                    navigationConversationID = conversation.id
                } label: {
                    ChatConversationRow(
                        conversation: conversation,
                        isSelected: false,
                        isGenerating: store.isGenerating(conversation.id)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button { store.select(conversation.id) } label: {
                    ChatConversationRow(
                        conversation: conversation,
                        isSelected: store.selectedConversationID == conversation.id,
                        isGenerating: store.isGenerating(conversation.id)
                    )
                }
                .buttonStyle(.plain)
            }

            if store.mutatingConversationIDs.contains(conversation.id) {
                ProgressView().controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                conversationMenu(conversation)
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    store.selectedConversationID == conversation.id && !usesNavigationLink
                        ? Color.accentColor.opacity(0.55)
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    private func conversationMenu(_ conversation: ChatConversation) -> some View {
        Menu {
            Button {
                Task { try? await store.togglePin(conversation, using: auth) }
            } label: {
                Label(
                    conversation.pinned ? "Unpin" : "Pin",
                    systemImage: conversation.pinned ? "pin.slash" : "pin"
                )
            }

            Button {
                renameDraft = conversation.title
                renameTarget = conversation
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                Task { try? await store.archive(conversation, using: auth) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                deleteTarget = conversation
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Conversation actions")
    }

    private var activePageBinding: Binding<Int> {
        Binding(
            get: { store.page },
            set: { newPage in Task { await store.loadPage(newPage, using: auth) } }
        )
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }
}

private struct ChatConversationRow: View {
    let conversation: ChatConversation
    let isSelected: Bool
    let isGenerating: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    Color.accentColor.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if conversation.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    if isGenerating {
                        ProgressView().controlSize(.mini)
                        Text("Responding")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(conversation.activityDate, format: .relative(presentation: .named))
                        Text("·")
                        Text(conversation.messageSummary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(conversation.title), \(conversation.messageSummary)")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ArchivedConversationCard: View {
    let conversation: ChatConversation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(conversation.activityDate, format: .relative(presentation: .named))
                    Text("·")
                    Text(conversation.messageSummary)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ChatConversationEmptyView: View {
    let create: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Select a Conversation", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Choose a conversation from the list, or create a new one.")
        } actions: {
            Button("New Conversation", action: create)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ChatConversationDetailView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store
    @Environment(LLMSettingsStore.self) private var modelStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let conversationID: String

    @State private var renameDraft = ""
    @State private var showRename = false
    @State private var showDelete = false
    @State private var draft = ""
    @State private var selectedModelID = ""
    @State private var pendingAIConsent: PendingAIConsent?
    @State private var showAIConsent = false
    @FocusState private var composerFocused: Bool

    private let aiConsentStore = AIConsentStore()

    private var conversation: ChatConversation? {
        store.conversations.first { $0.id == conversationID }
    }

    private var messages: [ChatMessage] {
        store.messages(for: conversationID)
    }

    private var historyEntries: [ChatHistoryEntry] {
        store.historyEntries(for: conversationID)
    }

    private var contextInfo: ChatContextInfo? {
        guard let model = modelStore.models.first(where: { $0.id == selectedModelID }) else { return nil }
        return ChatContextInfo.derive(
            messages: messages,
            conversation: conversation,
            maxTokens: model.maxContextTokens
        )
    }

    private var isLoadingMessages: Bool {
        store.loadingMessageConversationIDs.contains(conversationID)
    }

    private var isGenerating: Bool {
        store.isGenerating(conversationID)
    }

    var body: some View {
        Group {
            if let conversation {
                // The composer lives in a bottom safe-area inset: the system
                // rides it on top of the keyboard and animates the message
                // list's insets natively, instead of resizing the scroll
                // view's frame (which caused jumps and blank flashes).
                messageHistory
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        ChatComposer(
                            draft: $draft,
                            selectedModelID: $selectedModelID,
                            composerFocused: $composerFocused,
                            models: modelStore.models,
                            contextInfo: contextInfo,
                            isLoading: isLoadingMessages,
                            isGenerating: isGenerating,
                            send: submit,
                            stop: { Task { await store.stopRun(conversationID: conversationID, using: auth) } }
                        )
                        .background(Color(.systemBackground))
                    }
                .navigationTitle(conversation.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        detailMenu(conversation)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Conversation Unavailable",
                    systemImage: "bubble.left",
                    description: Text("It may have been archived or deleted.")
                )
            }
        }
        .task(id: conversationID) {
            await modelStore.loadModelsForPresentation(using: auth)
            chooseInitialModel()
            await store.loadMessages(for: conversationID, using: auth)
        }
        .onChange(of: modelStore.models) { _, _ in
            chooseInitialModel()
        }
        .alert("Rename conversation", isPresented: $showRename) {
            TextField("Title", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let conversation else { return }
                Task { try? await store.rename(conversation, title: renameDraft, using: auth) }
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete conversation?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let conversation else { return }
                Task {
                    if await store.delete(conversation, using: auth) {
                        leaveDetailIfNeeded()
                    }
                }
            }
        } message: {
            Text("This permanently deletes the conversation and all of its messages.")
        }
        .alert(
            "Allow AI Data Sharing?",
            isPresented: $showAIConsent,
            presenting: pendingAIConsent
        ) { pending in
            Button("Not Now", role: .cancel) {
                pendingAIConsent = nil
            }
            Button("Allow and Send") {
                aiConsentStore.authorize(
                    userID: pending.userID,
                    modelID: pending.modelID
                )
                send(pending.content, modelID: pending.modelID)
                pendingAIConsent = nil
            }
        } message: { pending in
            Text(
                """
                To generate a response, your message and relevant conversation or workspace content will be sent to this AI model:

                \(pending.modelAddress)
                """
            )
        }
    }

    @ViewBuilder
    private var messageHistory: some View {
        if isLoadingMessages, messages.isEmpty {
            ProgressView("Loading messages…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
            ContentUnavailableView {
                Label("No Messages Yet", systemImage: "sparkles")
            } description: {
                Text("Send a message below to start the conversation.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ChatHistoryList(
                entries: historyEntries,
                conversationID: conversationID,
                auth: auth,
                store: store
            )
            .overlay(alignment: .top) {
                if let error = store.messageErrorMessages[conversationID] {
                    InlineErrorBanner(message: error) {
                        Task {
                            await store.loadMessages(
                                for: conversationID,
                                using: auth,
                                force: true
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func chooseInitialModel() {
        guard selectedModelID.isEmpty || !modelStore.models.contains(where: { $0.id == selectedModelID }) else {
            return
        }
        selectedModelID = conversation?.modelConfigID.flatMap { conversationModelID in
            modelStore.models.first(where: { $0.id == conversationModelID })?.id
        } ?? modelStore.models.first(where: \.isDefault)?.id
            ?? modelStore.models.first?.id
            ?? ""
    }

    private func submit() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              !selectedModelID.isEmpty,
              !isGenerating,
              let userID = auth.user?.id,
              let model = modelStore.models.first(where: { $0.id == selectedModelID }) else { return }

        if !aiConsentStore.isAuthorized(userID: userID, modelID: model.id) {
            pendingAIConsent = PendingAIConsent(
                content: content,
                userID: userID,
                modelID: model.id,
                modelAddress: model.baseURL
            )
            showAIConsent = true
            return
        }

        send(content, modelID: model.id)
    }

    private func send(_ content: String, modelID: String) {
        draft = ""
        Task {
            await store.sendMessage(
                content,
                conversationID: conversationID,
                modelConfigID: modelID,
                using: auth
            )
        }
    }

    private func detailMenu(_ conversation: ChatConversation) -> some View {
        Menu {
            Button {
                Task { try? await store.togglePin(conversation, using: auth) }
            } label: {
                Label(
                    conversation.pinned ? "Unpin" : "Pin",
                    systemImage: conversation.pinned ? "pin.slash" : "pin"
                )
            }
            Button {
                renameDraft = conversation.title
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                Task {
                    do {
                        try await store.archive(conversation, using: auth)
                        leaveDetailIfNeeded()
                    } catch {
                        // ChatStore exposes the request error in the conversation pane.
                    }
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) { showDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(store.mutatingConversationIDs.contains(conversation.id))
        .accessibilityLabel("Conversation actions")
    }

    private func leaveDetailIfNeeded() {
        if horizontalSizeClass != .regular {
            dismiss()
        }
    }
}

private struct PendingAIConsent {
    let content: String
    let userID: String
    let modelID: String
    let modelAddress: String
}

private struct ChatComposer: View {
    @Binding var draft: String
    @Binding var selectedModelID: String
    @FocusState.Binding var composerFocused: Bool

    let models: [LLMModelConfiguration]
    let contextInfo: ChatContextInfo?
    let isLoading: Bool
    let isGenerating: Bool
    let send: () -> Void
    let stop: () -> Void

    private var canSend: Bool {
        !isLoading
            && !isGenerating
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModelID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                models.isEmpty ? "Configure a model to start chatting" : "Send a message…",
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($composerFocused)
            .disabled(isLoading || isGenerating || models.isEmpty)

            HStack(spacing: 10) {
                Menu {
                    Picker("Model", selection: $selectedModelID) {
                        ForEach(models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                        Text(selectedModelName)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .disabled(models.isEmpty || isGenerating)

                if let contextInfo, contextInfo.maxTokens > 0, contextInfo.usedTokens > 0 {
                    ContextGauge(info: contextInfo)
                }

                Spacer()

                if isGenerating {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                            .background(Color.red, in: Circle())
                    }
                    .accessibilityLabel("Stop response")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                            .background(
                                canSend ? Color.accentColor : Color(.tertiarySystemFill),
                                in: Circle()
                            )
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send message")
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var selectedModelName: String {
        models.first(where: { $0.id == selectedModelID })?.name
            ?? (models.isEmpty ? "No model" : "Select model")
    }
}

/// Snapshot of how much of the model's context window the conversation
/// currently occupies, plus accumulated usage, rendered by ``ContextGauge``.
private struct ChatContextInfo: Equatable {
    var usedTokens: Int
    var maxTokens: Int
    var estimated: Bool
    var usage: ChatTokenUsage?
    var totalInputTokens: Int
    var totalOutputTokens: Int

    var usedFraction: Double {
        guard maxTokens > 0 else { return 0 }
        return min(Double(usedTokens) / Double(maxTokens), 1)
    }

    var percentText: String {
        guard maxTokens > 0 else { return "—" }
        let percent = Double(usedTokens) / Double(maxTokens) * 100
        let value = percent >= 10
            ? String(Int(percent.rounded()))
            : String(format: "%.1f", percent)
        return "\(estimated ? "~" : "")\(value)%"
    }

    /// Derives occupancy from the newest assistant message that reported
    /// usage, falling back to the conversation's persisted snapshot.
    static func derive(
        messages: [ChatMessage],
        conversation: ChatConversation?,
        maxTokens: Int
    ) -> ChatContextInfo {
        let totalInput = conversation?.inputTokens ?? 0
        let totalOutput = conversation?.outputTokens ?? 0

        for message in messages.reversed() {
            guard message.role == .assistant, let metadata = message.metadata else { continue }
            guard metadata.usage != nil || metadata.contextTokens != nil else { continue }
            let usage = metadata.contextUsage ?? metadata.usage
            let used = metadata.contextTokens
                ?? usage.map { $0.inputTokens + $0.outputTokens }
                ?? 0
            return ChatContextInfo(
                usedTokens: used,
                maxTokens: maxTokens,
                estimated: metadata.contextTokensEstimated == true,
                usage: usage,
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput
            )
        }

        return ChatContextInfo(
            usedTokens: conversation?.contextTokens ?? 0,
            maxTokens: maxTokens,
            estimated: false,
            usage: nil,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput
        )
    }
}

private struct ContextGauge: View {
    let info: ChatContextInfo

    @State private var showDetails = false

    var body: some View {
        Button { showDetails = true } label: {
            HStack(spacing: 5) {
                Text(info.percentText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ring
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context usage \(info.percentText)")
        .popover(isPresented: $showDetails) {
            ContextDetails(info: info)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: info.usedFraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
    }

    private var ringColor: Color {
        switch info.usedFraction {
        case ..<0.75: .accentColor
        case ..<0.9: .orange
        default: .red
        }
    }
}

private struct ContextDetails: View {
    let info: ChatContextInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(info.percentText)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(windowText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: info.usedFraction)
                    .tint(.accentColor)
            }

            if let usage = info.usage {
                Divider()
                VStack(spacing: 5) {
                    detailRow("Cache hit", value: LLMTokenFormat.display(usage.cacheReadTokens))
                    detailRow("Cache write", value: LLMTokenFormat.display(usage.cacheCreationTokens))
                }
            }

            if info.maxTokens > 0 {
                Divider()
                detailRow(
                    "Compacts at",
                    value: "\(LLMTokenFormat.display(Int(Double(info.maxTokens) * 0.75))) (75%)"
                )
            }

            Divider()
            VStack(spacing: 5) {
                detailRow("Total input", value: LLMTokenFormat.display(info.totalInputTokens))
                detailRow("Total output", value: LLMTokenFormat.display(info.totalOutputTokens))
            }
        }
        .padding(14)
        .frame(width: 240)
    }

    private var windowText: String {
        guard info.maxTokens > 0 else { return LLMTokenFormat.display(info.usedTokens) }
        return "\(LLMTokenFormat.display(info.usedTokens)) / \(LLMTokenFormat.display(info.maxTokens))"
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

/// Collapsible reasoning ("thinking") section styled after the web app: a
/// brain glyph and a muted label, with a chevron that follows the text color
/// instead of the accent tint.
/// A pasted log or file is easily thousands of lines, and a self-sizing row
/// has to lay out every one of them just to measure itself. Capping the
/// collapsed height caps that work too, so the cost of a long message is the
/// same as a short one until the reader asks for the rest.
private struct UserMessageBubble: View {
    let parts: [ChatMessagePart]

    @State private var expanded = false

    private static let collapsedLineLimit = 12
    /// Deliberately a character/line count rather than a measurement — asking
    /// for the real height is the work this exists to avoid.
    private static let longMessageCharacters = 500

    private var isLong: Bool {
        var characters = 0
        var lines = 0
        for text in parts.compactMap(\.text) {
            characters += text.count
            lines += 1 + text.reduce(into: 0) { count, character in
                if character.isNewline { count += 1 }
            }
            if characters > Self.longMessageCharacters || lines > Self.collapsedLineLimit {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if let text = part.text {
                    Text(text)
                }
            }
            .lineLimit(expanded || !isLong ? nil : Self.collapsedLineLimit)

            if isLong {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Show Less" : "Show More")
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 620, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ReasoningDisclosure: View {
    let text: String
    let isStreaming: Bool

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                    Text(isStreaming ? "Thinking…" : "Thought")
                        .font(.subheadline)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ChatHistoryEntryView: View {
    let entry: ChatHistoryEntry
    let conversationID: String

    @ViewBuilder
    var body: some View {
        switch entry.kind {
        case .header:
            HStack(spacing: 5) {
                if entry.role == .user {
                    Spacer(minLength: 0)
                }
                Text(entry.role == .user ? "You" : "Assistant")
                    .fontWeight(.medium)
                if entry.role == .assistant, let modelName = entry.metadata?.model?.name {
                    Text("·")
                    Text(modelName)
                }
                if let date = entry.metadata?.createdDate {
                    Text("·")
                    Text(date, format: .relative(presentation: .named))
                }
                if entry.metadata?.status == .streaming {
                    Text("STREAMING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .phaseAnimator([0.4, 1.0]) { badge, phase in
                            badge.opacity(phase)
                        } animation: { _ in
                            .easeInOut(duration: 0.8)
                        }
                }
                if entry.role == .assistant {
                    Spacer(minLength: 0)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)

        case let .userContent(parts):
            UserMessageBubble(parts: parts)

        case .waiting:
            TypingDotsView()
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .assistantPart(part, approvalData):
            AssistantMessagePartView(
                part: part,
                approvalData: approvalData,
                conversationID: conversationID,
                messageRunID: entry.metadata?.runID,
                messageStatus: entry.metadata?.status
            )
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .error(error):
            Label(error.message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .usage(usage):
            Text("↑ \(usage.inputTokens) in   ↓ \(usage.outputTokens) out")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Three staggered pulsing dots shown while the assistant's first token is
/// still on its way, so the wait never looks frozen.
struct TypingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1 : 0.55)
                    .opacity(animating ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: animating
                    )
            }
        }
        .padding(.vertical, 4)
        .onAppear { animating = true }
    }
}

struct AssistantMessagePartView: View {
    let part: ChatMessagePart
    let approvalData: JSONValue?
    let conversationID: String
    let messageRunID: String?
    let messageStatus: ChatMessageStatus?

    /// While the response is still streaming, render plain text to avoid
    /// re-parsing the whole Markdown document on every token; swap to the
    /// full Markdown renderer once the message settles.
    private var isStreaming: Bool {
        messageStatus == .streaming || messageStatus == .pending
    }

    var body: some View {
        switch part.type {
        case "text":
            if let text = part.text, !text.isEmpty {
                if isStreaming {
                    Text(text)
                        .font(.body)
                } else {
                    Markdown(text)
                        .workspaceMarkdownCodeStyle()
                }
            }
        case "reasoning":
            if let text = part.text, !text.isEmpty {
                ReasoningDisclosure(text: text, isStreaming: isStreaming)
            }
        case "dynamic-tool":
            if part.toolName == "system_memory_upsert" || part.toolName == "system_memory_forget" {
                MemoryToolCard(part: part)
            } else if part.toolName?.hasPrefix("docs_") == true {
                DocsToolCard(part: part)
            } else if part.toolName == "contacts_search" {
                ContactsToolCard(part: part)
            } else if part.toolName?.hasPrefix("board_") == true && part.toolName != "board_delete_task" {
                BoardToolCard(part: part)
            } else if part.toolName?.hasPrefix("calendar_") == true && part.toolName != "calendar_delete_event" {
                CalendarToolCard(part: part)
            } else if part.toolName?.hasPrefix("reading_") == true {
                ReadingToolCard(part: part)
            } else {
                ChatToolCard(
                    part: part,
                    approvalData: approvalData,
                    conversationID: conversationID,
                    messageRunID: messageRunID,
                    messageStatus: messageStatus
                )
            }
        case "source-url":
            if let urlString = part.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(part.title?.isEmpty == false ? part.title! : urlString, systemImage: "link")
                        .font(.caption)
                }
            }
        case "source-document":
            Label(part.title ?? part.filename ?? "Source document", systemImage: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "data-compaction":
            ChatCompactionStatus(data: part.data)
        case "step-start", "data-approval":
            EmptyView()
        default:
            EmptyView()
        }
    }
}

private struct ChatCompactionStatus: View {
    let data: JSONValue?

    var body: some View {
        let state = data?.objectValue?["state"]?.stringValue
        Label {
            Text(label(for: state))
        } icon: {
            if state == "started" {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: state == "failed" ? "exclamationmark.triangle" : "rectangle.compress.vertical")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func label(for state: String?) -> String {
        switch state {
        case "started": "Compacting context…"
        case "failed": "Context compaction failed — continued with full history"
        default: "Older messages were compacted into a summary"
        }
    }
}

/// Purpose-built card for the `system_memory_upsert` / `system_memory_forget`
/// tools. Unlike the generic tool card it renders the memory itself — category,
/// origin and content — instead of raw JSON, and always stays expanded because
/// the content is the point of the tool call.
private struct MemoryToolCard: View {
    let part: ChatMessagePart

    private var isForget: Bool { part.toolName == "system_memory_forget" }
    private var isWorking: Bool {
        part.state == "input-streaming" || part.state == "input-available"
    }
    private var isError: Bool { part.state == "output-error" }
    private var isRemoval: Bool {
        isForget || payload?.action == .forgotten
    }

    /// Prefer the settled result; fall back to the input while the call is
    /// still running so the card can preview what is being saved.
    private var payload: MemoryToolPayload? {
        if part.state == "output-available", let result = MemoryToolPayload(output: part.output) {
            return result
        }
        return MemoryToolPayload(input: part.input)
    }

    /// Monochrome by default to match the app accent; red only for failures
    /// and removals, where the color carries meaning.
    private var tint: Color {
        if isError || isRemoval { return .red }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                statusAccessory
            }
            if let input = part.input {
                ToolParametersPanel(value: input)
            }
            if let content = payload?.content, !content.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint.opacity(0.6))
                        .frame(width: 3)
                    Text(content)
                        .font(.callout)
                        .foregroundStyle(isRemoval || payload?.action == .undone ? .secondary : .primary)
                        .strikethrough(payload?.action == .forgotten)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if isError, let errorText = part.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        )
    }

    private var title: String {
        if isError { return "Memory action failed" }
        if isWorking { return isForget ? "Forgetting memory…" : "Saving memory…" }
        switch payload?.action {
        case .forgotten: return "Memory forgotten"
        case .undone: return "Memory change undone"
        case .unchanged: return "Already remembered"
        case .updated: return "Memory updated"
        case .created:
            return payload?.origin == .automatic ? "Remembered automatically" : "Memory saved"
        default:
            return isForget ? "Memory forgotten" : "Memory saved"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let category = payload?.category { parts.append(category.label) }
        if let origin = payload?.origin, !isRemoval { parts.append(origin.label) }
        return parts.isEmpty ? "Memory" : parts.joined(separator: " · ")
    }

    private var iconName: String {
        if isError { return "exclamationmark.triangle.fill" }
        if isRemoval { return "trash.fill" }
        if payload?.action == .undone { return "arrow.uturn.backward" }
        if let category = payload?.category { return category.icon }
        return "brain"
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if isWorking {
            ProgressView().controlSize(.mini)
        } else if isError {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

/// Purpose-built card for the `docs_*` assistant tools. Collapsed by default:
/// the header shows the operation and a one-line outcome, while expanding
/// reveals the affected documents (title, location, revision, excerpt) instead
/// of the raw JSON the generic tool card would show.
private struct DocsToolCard: View {
    let part: ChatMessagePart

    @State private var expanded = false

    private var toolName: String { part.toolName ?? "" }
    private var isWorking: Bool {
        part.state == "input-streaming" || part.state == "input-available"
    }
    private var isError: Bool { part.state == "output-error" }
    private var tint: Color { isError ? .red : .accentColor }

    private var payload: DocsToolPayload? {
        guard part.state == "output-available" else { return nil }
        return DocsToolPayload(toolName: toolName, output: part.output)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            expandedContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: meta.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.label)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        )
    }

    private var meta: (label: String, icon: String, working: String) {
        switch toolName {
        case "docs_search": ("Search Documents", "magnifyingglass", "Searching…")
        case "docs_get": ("Read Document", "doc.text", "Loading…")
        case "docs_upsert": ("Save Document", "square.and.pencil", "Saving…")
        case "docs_move": ("Move Documents", "folder", "Moving…")
        case "docs_replace": ("Replace Text", "text.magnifyingglass", "Replacing…")
        case "docs_write_chunk": ("Write Document", "square.and.pencil", "Writing…")
        case "docs_ensure_folder": ("Document Folder", "folder.badge.plus", "Resolving…")
        case "docs_list_folders": ("Document Folders", "folder", "Loading…")
        default: ("Document Tool", "doc", "Working…")
        }
    }

    private var subtitle: String {
        if isWorking { return meta.working }
        if isError { return "Failed" }
        guard let payload else { return "Completed" }
        switch toolName {
        case "docs_search":
            let count = payload.documents.count
            return count == 1 ? "1 document" : "\(count) documents"
        case "docs_get":
            return payload.documents.first?.title ?? "Completed"
        case "docs_upsert":
            guard let doc = payload.documents.first else { return "Completed" }
            let revision = doc.revision.map { " · R\($0)" } ?? ""
            if payload.isCreation { return "Created" + revision }
            return (payload.changed == false ? "No changes" : "Saved") + revision
        case "docs_replace":
            let matches = payload.matches.map { $0 == 1 ? "1 match" : "\($0) matches" } ?? "Done"
            return matches + (payload.documents.first?.revision.map { " · R\($0)" } ?? "")
        case "docs_move":
            return "Moved \(payload.moveSucceeded) of \(payload.moveTotal)"
        case "docs_write_chunk":
            var parts: [String] = []
            if let length = payload.chunkContentLength { parts.append("Wrote \(length) characters") }
            if let revision = payload.chunkRevision { parts.append("R\(revision)") }
            return parts.isEmpty ? "Completed" : parts.joined(separator: " · ")
        case "docs_ensure_folder":
            let name = payload.folders.first?.name ?? "Folder"
            return payload.folderWasCreated ? "Created \u{201C}\(name)\u{201D}" : "Using \u{201C}\(name)\u{201D}"
        case "docs_list_folders":
            let count = payload.folders.count
            return count == 1 ? "1 folder" : "\(count) folders"
        default:
            return "Completed"
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let input = part.input {
                ToolParametersPanel(value: input)
            }
            if isWorking, let inputSummary {
                Label(inputSummary, systemImage: meta.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let payload {
                switch toolName {
                case "docs_search":
                    documentList(payload.documents)
                case "docs_get", "docs_upsert", "docs_replace":
                    if let doc = payload.documents.first {
                        documentDetail(doc, payload: payload)
                    }
                case "docs_move":
                    moveResultsList(payload)
                case "docs_write_chunk":
                    chunkDetail(payload)
                case "docs_ensure_folder", "docs_list_folders":
                    folderList(payload.folders)
                default:
                    EmptyView()
                }
            }
            if isError, let errorText = part.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// While the call runs, preview what it is operating on from the input.
    private var inputSummary: String? {
        let input = part.input?.objectValue
        switch toolName {
        case "docs_search": return input?["query"]?.stringValue
        case "docs_upsert": return input?["title"]?.stringValue
        case "docs_replace": return input?["find"]?.stringValue
        default: return nil
        }
    }

    private static let searchRowLimit = 4
    private static let moveRowLimit = 5

    @ViewBuilder
    private func documentList(_ documents: [DocsToolPayload.Document]) -> some View {
        if documents.isEmpty {
            Text("No matching documents")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(documents.prefix(Self.searchRowLimit)) { doc in
                documentRow(doc)
            }
            if documents.count > Self.searchRowLimit {
                Text("+\(documents.count - Self.searchRowLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func documentRow(_ doc: DocsToolPayload.Document) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: doc.kind == .html ? "chevron.left.forwardslash.chevron.right" : "doc.text")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let excerpt = doc.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(documentMetaLine(doc))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func documentDetail(_ doc: DocsToolPayload.Document, payload: DocsToolPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(doc.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                statusBadge(payload)
            }
            Text(documentMetaLine(doc))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let excerpt = doc.excerpt, !excerpt.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 3)
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ payload: DocsToolPayload) -> some View {
        let text: String? = switch toolName {
        case "docs_upsert":
            payload.isCreation ? "Created" : (payload.changed == false ? "No changes" : "Saved")
        case "docs_replace":
            payload.matches.map { $0 == 1 ? "1 match" : "\($0) matches" }
        default:
            nil
        }
        if let text {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
    }

    private func documentMetaLine(_ doc: DocsToolPayload.Document) -> String {
        var parts: [String] = []
        if let location = doc.location { parts.append(location) }
        if let revision = doc.revision { parts.append("R\(revision)") }
        if let date = doc.updatedDate {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func chunkDetail(_ payload: DocsToolPayload) -> some View {
        // The written text itself comes from the tool input; the output only
        // carries the resulting revision and total content length.
        if let content = part.input?.objectValue?["content"]?.stringValue, !content.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Text(chunkMetaLine(payload))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func chunkMetaLine(_ payload: DocsToolPayload) -> String {
        var parts: [String] = []
        if let revision = payload.chunkRevision { parts.append("R\(revision)") }
        if let length = payload.chunkContentLength { parts.append("\(length) characters") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func moveResultsList(_ payload: DocsToolPayload) -> some View {
        ForEach(payload.moveResults.prefix(Self.moveRowLimit)) { result in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(result.ok ? .green : .red)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title ?? "Document")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let error = result.error, !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let destination = result.destination {
                    Label(destination, systemImage: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        if payload.moveResults.count > Self.moveRowLimit {
            Text("+\(payload.moveResults.count - Self.moveRowLimit) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func folderList(_ folders: [DocsToolPayload.Folder]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Purpose-built card for the read-only `contacts_search` tool. Collapsed by
/// default; expanding shows the matched contacts with avatar, title and
/// presence dot instead of the raw JSON the generic tool card would show.
private struct ContactsToolCard: View {
    @Environment(AuthStore.self) private var auth

    let part: ChatMessagePart

    @State private var expanded = false

    private static let rowLimit = 4

    private var isWorking: Bool {
        part.state == "input-streaming" || part.state == "input-available"
    }
    private var isError: Bool { part.state == "output-error" }
    private var tint: Color { isError ? .red : .accentColor }

    private var payload: ContactsToolPayload? {
        guard part.state == "output-available" else { return nil }
        return ContactsToolPayload(output: part.output)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            expandedContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search Contacts")
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        )
    }

    private var subtitle: String {
        if isWorking { return "Searching…" }
        if isError { return "Failed" }
        guard let payload else { return "Completed" }
        if payload.contacts.isEmpty { return "No contacts found" }
        return payload.contacts.count == 1 ? "1 contact" : "\(payload.contacts.count) contacts"
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let input = part.input {
                ToolParametersPanel(value: input)
            }
            if isWorking, let query = part.input?.objectValue?["query"]?.stringValue, !query.isEmpty {
                Label(query, systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let payload {
                if payload.contacts.isEmpty, !isError {
                    Text("No contacts found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(payload.contacts.prefix(Self.rowLimit)) { contact in
                    contactRow(contact)
                }
                if payload.contacts.count > Self.rowLimit {
                    Text("+\(payload.contacts.count - Self.rowLimit) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if isError, let errorText = part.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func contactRow(_ contact: ContactsToolPayload.Contact) -> some View {
        HStack(spacing: 8) {
            AvatarView(
                url: avatarURL(for: contact),
                name: contact.name,
                size: 24
            )
            Text(contact.name.isEmpty ? "Unknown" : contact.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if let title = contact.title {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let status = contact.status {
                StatusDot(status: status, size: 7)
            }
        }
    }

    private func avatarURL(for contact: ContactsToolPayload.Contact) -> URL? {
        guard let avatar = contact.avatar else { return nil }
        return auth.fileURL(
            collectionId: contact.collectionID ?? "users",
            recordId: contact.id,
            fileName: avatar
        )
    }
}

/// Purpose-built card for the `board_*` assistant tools (projects, tasks,
/// templates and mutations). Collapsed by default. `board_delete_task` is
/// approval-gated and stays on the generic tool card, which renders the
/// approve/reject flow.
private struct BoardToolCard: View {
    @Environment(AuthStore.self) private var auth

    let part: ChatMessagePart

    @State private var expanded = false

    private static let rowLimit = 4

    private var toolName: String { part.toolName ?? "" }
    private var isWorking: Bool {
        part.state == "input-streaming" || part.state == "input-available"
    }
    private var isError: Bool { part.state == "output-error" }
    private var tint: Color { isError ? .red : .accentColor }

    private var payload: BoardToolPayload? {
        guard part.state == "output-available" else { return nil }
        return BoardToolPayload(toolName: toolName, output: part.output)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            expandedContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: meta.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.label)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        )
    }

    private var meta: (label: String, icon: String, working: String) {
        switch toolName {
        case "board_search_projects": ("Search Projects", "square.3.layers.3d", "Searching…")
        case "board_get_project": ("Project Details", "square.3.layers.3d", "Loading…")
        case "board_search_tasks": ("Search Tasks", "checklist", "Searching…")
        case "board_list_templates": ("Project Templates", "rectangle.grid.2x2", "Loading…")
        case "board_create_project": ("Create Project", "plus", "Creating…")
        case "board_update_project": ("Update Project", "pencil", "Updating…")
        case "board_upsert_state": ("Upsert States", "square.stack.3d.up", "Saving…")
        case "board_upsert_label": ("Upsert Labels", "tag", "Saving…")
        case "board_upsert_member": ("Upsert Members", "person.2", "Saving…")
        case "board_create_task": ("Create Tasks", "plus", "Creating…")
        case "board_update_task": ("Update Tasks", "pencil", "Updating…")
        default: ("Board Tool", "square.3.layers.3d", "Working…")
        }
    }

    private var subtitle: String {
        if isWorking { return meta.working }
        if isError { return "Failed" }
        guard let payload else { return "Completed" }
        switch toolName {
        case "board_search_projects":
            return payload.projects.count == 1 ? "1 project" : "\(payload.projects.count) projects"
        case "board_get_project":
            return payload.projects.first?.name ?? "Completed"
        case "board_search_tasks":
            return payload.tasks.count == 1 ? "1 task" : "\(payload.tasks.count) tasks"
        case "board_list_templates":
            return payload.templates.count == 1 ? "1 template" : "\(payload.templates.count) templates"
        default:
            if payload.isBatchMutation {
                return "\(payload.mutationSucceeded) of \(payload.mutationTotal) succeeded"
            }
            return payload.mutationItems.first?.detail ?? "Completed"
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let input = part.input {
                ToolParametersPanel(value: input)
            }
            if isWorking, let query = part.input?.objectValue?["query"]?.stringValue, !query.isEmpty {
                Label(query, systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let payload {
                switch toolName {
                case "board_search_projects", "board_get_project":
                    projectList(payload.projects)
                case "board_search_tasks":
                    taskList(payload.tasks)
                case "board_list_templates":
                    templateList(payload.templates)
                default:
                    mutationList(payload)
                }
            }
            if isError, let errorText = part.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Projects

    @ViewBuilder
    private func projectList(_ projects: [BoardToolPayload.Project]) -> some View {
        if projects.isEmpty {
            Text("No matching projects")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(projects.prefix(Self.rowLimit)) { project in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if project.archived {
                        Text("Archived")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    if let role = project.role {
                        Text(role.capitalized)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    Spacer(minLength: 8)
                    Text(project.taskCount == 1 ? "1 task" : "\(project.taskCount) tasks")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let description = project.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !project.states.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(project.states) { state in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(state.color.map(Color.init(hex:)) ?? .gray)
                                        .frame(width: 6, height: 6)
                                    Text(state.name)
                                    if let count = state.taskCount {
                                        Text("\(count)")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        if projects.count > Self.rowLimit {
            Text("+\(projects.count - Self.rowLimit) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Tasks

    @ViewBuilder
    private func taskList(_ tasks: [BoardToolPayload.Task]) -> some View {
        if tasks.isEmpty {
            Text("No matching tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(tasks.prefix(Self.rowLimit)) { task in
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                    if let description = task.description {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let stateName = task.stateName {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(task.stateColor.map(Color.init(hex:)) ?? .gray)
                                    .frame(width: 6, height: 6)
                                Text(stateName)
                            }
                        }
                        if let priority = task.priority, priority != .none {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(priority.color)
                                    .frame(width: 6, height: 6)
                                Text(priority.label)
                            }
                        }
                        if let startDate = task.startDate {
                            Text(startDate)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        if let dueDate = task.dueDate {
                            Text(dueDate)
                                .foregroundStyle(task.isOverdue ? Color.red : Color(.tertiaryLabel))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    if let projectName = task.projectName {
                        Text(projectName)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if !task.assignees.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(task.assignees.prefix(3)) { assignee in
                            AvatarView(url: avatarURL(for: assignee), name: assignee.name, size: 20)
                                .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                        }
                    }
                }
            }
        }
        if tasks.count > Self.rowLimit {
            Text("+\(tasks.count - Self.rowLimit) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Templates

    @ViewBuilder
    private func templateList(_ templates: [BoardToolPayload.Template]) -> some View {
        if templates.isEmpty {
            Text("No templates available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(templates.prefix(Self.rowLimit)) { template in
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let description = template.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(template.stateCount) states · \(template.labelCount) labels")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        if templates.count > Self.rowLimit {
            Text("+\(templates.count - Self.rowLimit) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Mutations

    private func mutationList(_ payload: BoardToolPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(payload.mutationItems.prefix(Self.rowLimit)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(item.ok ? .green : .red)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Record \(item.index + 1)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let error = item.error {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if payload.mutationItems.count > Self.rowLimit {
                Text("+\(payload.mutationItems.count - Self.rowLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func avatarURL(for participant: BoardToolPayload.Participant) -> URL? {
        guard let avatar = participant.avatar else { return nil }
        return auth.fileURL(
            collectionId: participant.collectionID ?? "users",
            recordId: participant.id,
            fileName: avatar
        )
    }
}

/// Purpose-built card for `calendar_get_schedule`, `calendar_create_event`
/// and `calendar_update_event`. Collapsed by default. `calendar_delete_event`
/// is approval-gated and stays on the generic tool card.
private struct CalendarToolCard: View {
    let part: ChatMessagePart

    @State private var expanded = false

    private static let dayRowLimit = 3
    private static let mutationRowLimit = 4

    private var toolName: String { part.toolName ?? "" }
    private var isWorking: Bool {
        part.state == "input-streaming" || part.state == "input-available"
    }
    private var isError: Bool { part.state == "output-error" }
    private var tint: Color { isError ? .red : .accentColor }

    private var payload: CalendarToolPayload? {
        guard part.state == "output-available" else { return nil }
        return CalendarToolPayload(toolName: toolName, output: part.output)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            expandedContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: meta.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.label)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        )
    }

    private var meta: (label: String, icon: String, working: String) {
        switch toolName {
        case "calendar_get_schedule": ("Schedule", "calendar", "Loading…")
        case "calendar_search_events": ("Event Search", "magnifyingglass", "Searching…")
        case "calendar_create_event": ("Create Events", "calendar.badge.plus", "Creating…")
        case "calendar_update_event": ("Update Events", "pencil", "Updating…")
        default: ("Calendar Tool", "calendar", "Working…")
        }
    }

    private var subtitle: String {
        if isWorking { return meta.working }
        if isError { return "Failed" }
        guard let payload else { return "Completed" }
        if toolName == "calendar_get_schedule" {
            let total = payload.days.reduce(0) { $0 + $1.events.count + $1.tasks.count }
            if total == 0 { return "Nothing scheduled" }
            return total == 1 ? "1 item" : "\(total) items"
        }
        if payload.isSearch {
            if payload.matches.isEmpty { return "No matching events" }
            return payload.matches.count == 1 ? "1 event" : "\(payload.matches.count) events"
        }
        if payload.isBatchMutation {
            return "\(payload.mutationSucceeded) of \(payload.mutationTotal) succeeded"
        }
        return payload.mutationItems.first?.action?.capitalized ?? "Completed"
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let input = part.input {
                ToolParametersPanel(value: input)
            }
            if let payload {
                if toolName == "calendar_get_schedule" {
                    scheduleView(payload)
                } else if payload.isSearch {
                    searchView(payload)
                } else {
                    mutationList(payload)
                }
            }
            if isError, let errorText = part.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Schedule

    @ViewBuilder
    private func scheduleView(_ payload: CalendarToolPayload) -> some View {
        if payload.days.allSatisfy({ $0.events.isEmpty && $0.tasks.isEmpty }) {
            Text("Nothing scheduled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(payload.days) { day in
            if !day.events.isEmpty || !day.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    dayHeader(day.date)
                    ForEach(day.events.prefix(Self.dayRowLimit)) { event in
                        eventRow(event)
                    }
                    if day.events.count > Self.dayRowLimit {
                        Text("+\(day.events.count - Self.dayRowLimit) more events")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(day.tasks.prefix(Self.dayRowLimit)) { task in
                        taskRow(task)
                    }
                    if day.tasks.count > Self.dayRowLimit {
                        Text("+\(day.tasks.count - Self.dayRowLimit) more tasks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchView(_ payload: CalendarToolPayload) -> some View {
        if payload.matches.isEmpty {
            Text("No matching events")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(payload.matches.prefix(Self.dayRowLimit)) { event in
                    eventRow(event, showDate: true)
                }
                if payload.matches.count > Self.dayRowLimit {
                    Text("+\(payload.matches.count - Self.dayRowLimit) more events")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !payload.searchComplete {
                    // The backend caps matches, so say the list is partial
                    // rather than let it read as every match.
                    Text("Showing the first matches. Narrow the search to see the rest.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func dayHeader(_ date: String) -> some View {
        HStack(spacing: 6) {
            Text(Self.dayFormatter.date(from: date).map {
                $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            } ?? date)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if isToday(date) {
                Text("Today")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }

    /// showDate is set for search results: those are a flat list rather than
    /// rows grouped under a day header, so each row carries its own date.
    private func eventRow(_ event: CalendarToolPayload.Event, showDate: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(event.color?.color ?? Color.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let recurrence = event.recurrence, recurrence != .none {
                        Text(recurrence.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                if showDate, let start = event.start {
                    let repeats = event.recurrence.map { $0 != .none } ?? false
                    Text(start.formatted(.dateTime.month(.abbreviated).day().year())
                        + (repeats ? " onwards" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(event.allDay ? "All day" : timeRange(event))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let location = event.location {
                    Label(location, systemImage: "mappin")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func taskRow(_ task: CalendarToolPayload.ScheduleTask) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(task.completed ? .green : Color(.tertiaryLabel))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(task.completed ? .secondary : .primary)
                    .strikethrough(task.completed)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let priority = task.priority, priority != .none {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(priority.color)
                                .frame(width: 6, height: 6)
                            Text(priority.label)
                        }
                    }
                    if let dueDate = task.dueDate {
                        Text("Due \(dueDate)")
                    }
                    if let projectName = task.projectName {
                        Text(projectName)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Mutations

    private func mutationList(_ payload: CalendarToolPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(payload.mutationItems.prefix(Self.mutationRowLimit)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(item.ok ? .green : .red)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? "Event \(item.index + 1)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if let action = item.action {
                            Text(action.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let error = item.error {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if payload.mutationItems.count > Self.mutationRowLimit {
                Text("+\(payload.mutationItems.count - Self.mutationRowLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Date helpers

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func isToday(_ date: String) -> Bool {
        guard let day = Self.dayFormatter.date(from: date) else { return false }
        return Calendar.current.isDateInToday(day)
    }

    private func timeRange(_ event: CalendarToolPayload.Event) -> String {
        let start = event.start?.formatted(date: .omitted, time: .shortened) ?? ""
        let end = event.end?.formatted(date: .omitted, time: .shortened) ?? ""
        guard !start.isEmpty, !end.isEmpty else { return start + end }
        return "\(start) – \(end)"
    }
}

/// Purpose-built card for the `reading_*` assistant tools. Collapsed by
/// default; search shows the matched items with status dots and tags, item
/// tools show the summary and key points instead of raw JSON.
private struct ReadingToolCard: View {
    let part: ChatMessagePart

    @State private var expanded = false

    private static let rowLimit = 4

    private var toolName: String { part.toolName ?? "" }
    private var isWorking: Bool {
        part.state == "input-streaming" || part.state == "input-available"
    }
    private var isError: Bool { part.state == "output-error" }
    private var tint: Color { isError ? .red : .accentColor }

    private var payload: ReadingToolPayload? {
        guard part.state == "output-available" else { return nil }
        return ReadingToolPayload(toolName: toolName, output: part.output)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            expandedContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: meta.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.label)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35))
        )
    }

    private var meta: (label: String, icon: String, working: String) {
        switch toolName {
        case "reading_search": ("Reading List", "book", "Searching…")
        case "reading_upsert": ("Save Reading Items", "pencil", "Saving…")
        case "reading_get": ("Reading Item", "doc.text", "Loading…")
        case "reading_summarize": ("Summarize Reading", "sparkles", "Summarizing…")
        default: ("Reading Tool", "book", "Working…")
        }
    }

    private var subtitle: String {
        if isWorking { return meta.working }
        if isError { return "Failed" }
        guard let payload else { return "Completed" }
        if payload.plainText != nil { return "Failed" }
        switch toolName {
        case "reading_search":
            if payload.items.isEmpty { return "No items found" }
            return payload.items.count == 1 ? "1 item" : "\(payload.items.count) items"
        case "reading_get":
            return payload.items.first?.title ?? "Completed"
        case "reading_summarize":
            return payload.items.isEmpty ? "Completed" : "Summary ready"
        default:
            return "\(payload.mutationSucceeded) of \(payload.mutationTotal) succeeded"
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let input = part.input {
                ToolParametersPanel(value: input)
            }
            if isWorking, let query = part.input?.objectValue?["query"]?.stringValue, !query.isEmpty {
                Label(query, systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let payload {
                if let plainText = payload.plainText {
                    Text(plainText)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    switch toolName {
                    case "reading_search":
                        searchList(payload.items)
                    case "reading_get", "reading_summarize":
                        if let item = payload.items.first {
                            itemDetail(item)
                        }
                    default:
                        mutationList(payload)
                    }
                }
            }
            if isError, let errorText = part.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchList(_ items: [ReadingToolPayload.Item]) -> some View {
        if items.isEmpty {
            Text("No reading items found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(items.prefix(Self.rowLimit)) { item in
            itemRow(item)
        }
        if items.count > Self.rowLimit {
            Text("+\(items.count - Self.rowLimit) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func itemRow(_ item: ReadingToolPayload.Item) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.status?.dotColor ?? .gray)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                if let preview = item.summary ?? item.description {
                    Text(preview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                metaLine(item)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Item detail

    private func itemDetail(_ item: ReadingToolPayload.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(item.status?.dotColor ?? .gray)
                    .frame(width: 7, height: 7)
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
            }
            metaLine(item)
            if let description = item.description, item.summary == nil {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let summary = item.summary {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Summary", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(item.keyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(point)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func metaLine(_ item: ReadingToolPayload.Item) -> some View {
        HStack(spacing: 6) {
            if let host = item.host {
                Label(host, systemImage: "link")
            }
            if let status = item.status {
                Text(status.label)
            }
            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: " "))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    // MARK: - Mutations

    private func mutationList(_ payload: ReadingToolPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(payload.mutationItems.prefix(Self.rowLimit)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(item.ok ? .green : .red)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? "Item \(item.index + 1)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if let error = item.error {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if payload.mutationItems.count > Self.rowLimit {
                Text("+\(payload.mutationItems.count - Self.rowLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension ReadingStatus {
    var dotColor: Color {
        switch self {
        case .unread: Color(hex: "#3b82f6")
        case .read: Color(hex: "#22c55e")
        case .archived: Color(hex: "#64748b")
        }
    }
}

enum ChatApprovalAvailability {
    /// Approval availability is derived from the message and ChatStore at
    /// render time. The collection-view bridge deliberately owns none of this
    /// state, so cell reuse and list optimizations cannot make it stale.
    static func isAwaitingDecision(
        partState: String?,
        messageRunID: String?,
        activeRunID: String?,
        messageStatus: ChatMessageStatus?
    ) -> Bool {
        partState == "approval-requested"
            && messageRunID != nil
            && messageRunID == activeRunID
            && messageStatus != .error
            && messageStatus != .cancelled
    }
}

private struct ChatToolCard: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store

    let part: ChatMessagePart
    let approvalData: JSONValue?
    let conversationID: String
    let messageRunID: String?
    let messageStatus: ChatMessageStatus?

    /// nil until the user taps the card, so the derived value below can keep
    /// following the approval state until then.
    @State private var manualExpanded: Bool?

    private var approvalObject: [String: JSONValue]? { approvalData?.objectValue }
    private var approvalID: String? { approvalObject?["approvalId"]?.stringValue }
    private var awaitingApproval: Bool {
        ChatApprovalAvailability.isAwaitingDecision(
            partState: part.state,
            messageRunID: messageRunID,
            activeRunID: store.activeRunIDs[conversationID],
            messageStatus: messageStatus
        )
    }

    /// The approve and reject buttons live in the collapsed region, so a card
    /// that still needs a decision has to start expanded or the run silently
    /// stalls with no visible way to act. Derived rather than a stored initial
    /// value so a card that only becomes actionable later also expands.
    private var needsAttention: Bool {
        awaitingApproval || part.state == "approval-responded"
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { manualExpanded ?? needsAttention },
            set: { manualExpanded = $0 }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: expansion) {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = approvalObject?["summary"]?.stringValue {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let input = part.input {
                    ToolParametersPanel(value: input)
                }
                if let output = part.output {
                    JSONSection(title: "Output", value: output)
                }
                if let errorText = part.errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if approvalObject != nil {
                    approvalOutcome
                }
                if awaitingApproval, let approvalID {
                    HStack {
                        Spacer()
                        Button("Reject") {
                            respond(approvalID: approvalID, approved: false)
                        }
                        .buttonStyle(.bordered)
                        Button(confirmationLabel) {
                            respond(approvalID: approvalID, approved: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(confirmationIsDestructive ? .red : .accentColor)
                    }
                    .disabled(store.submittingApprovalIDs.contains(approvalID))
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: toolIcon)
                    .foregroundStyle(toolColor)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(approvalObject?["title"]?.stringValue ?? displayToolName)
                        .font(.subheadline.weight(.medium))
                    Text(stateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(confirmationIsDestructive ? Color.red.opacity(0.25) : Color(.separator).opacity(0.35))
        )
    }

    private var displayToolName: String {
        (part.toolName ?? "Workspace tool")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var isWorking: Bool {
        ["input-streaming", "input-available", "approval-responded"].contains(part.state)
    }

    private var stateLabel: String {
        switch part.state {
        case "input-streaming": "Preparing…"
        case "input-available": "Running…"
        case "approval-requested": awaitingApproval ? "Awaiting approval" : "Approval expired"
        case "approval-responded": part.approval?.approved == false ? "Rejected" : "Applying…"
        case "output-available": "Completed"
        case "output-error": "Failed"
        default: part.state ?? "Tool call"
        }
    }

    private var toolIcon: String {
        if awaitingApproval { return confirmationIsDestructive ? "exclamationmark.triangle.fill" : "checkmark.shield.fill" }
        switch part.state {
        case "output-available": return "checkmark.circle.fill"
        case "output-error": return "xmark.circle.fill"
        default: return "wrench.and.screwdriver.fill"
        }
    }

    private var toolColor: Color {
        switch part.state {
        case "output-available": .green
        case "output-error": .red
        default: confirmationIsDestructive ? .red : .accentColor
        }
    }

    private var confirmationLabel: String {
        approvalObject?["presentation"]?.objectValue?["confirmLabel"]?.stringValue ?? "Approve"
    }

    private func presentationText(_ key: String) -> String? {
        approvalObject?["presentation"]?.objectValue?[key]?.stringValue
    }

    /// The tool's own result, when it reports one. Approval-gated tools answer
    /// with `{ok, action, reason}`, which is how a denial and a business
    /// failure are told apart from a plain success.
    private var resultObject: [String: JSONValue]? { part.output?.objectValue }

    private var isDenied: Bool {
        if part.approval?.approved == false { return true }
        return resultObject?["action"]?.stringValue == "denied"
            || resultObject?["reason"]?.stringValue == "user_denied"
    }

    private var isBusinessFailure: Bool {
        part.state == "output-available" && resultObject?["ok"]?.boolValue == false && !isDenied
    }

    private var isFailed: Bool { part.state == "output-error" || isBusinessFailure }

    private var isCompleted: Bool {
        part.state == "output-available" && !isDenied && !isBusinessFailure
    }

    /// Mirrors the web card: once a decision is made the card explains what
    /// happened in the tool's own words, rather than leaving the user to read
    /// the raw result JSON.
    @ViewBuilder
    private var approvalOutcome: some View {
        if part.state == "approval-responded", part.approval?.approved == true,
           !isCompleted, !isFailed {
            Label(
                presentationText("pendingMessage") ?? "Applying approved action…",
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if isDenied {
            Label(
                presentationText("deniedMessage") ?? "Action cancelled.",
                systemImage: "xmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if isCompleted {
            Label(
                presentationText("successMessage") ?? "Action completed.",
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.green)
        } else if isFailed, part.errorText == nil {
            // An explicit errorText is already rendered above; this covers a
            // tool that failed while reporting ok=false without one.
            Text(presentationText("failureMessage") ?? "The approved action could not be completed.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var confirmationIsDestructive: Bool {
        approvalObject?["presentation"]?.objectValue?["confirmVariant"]?.stringValue == "destructive"
    }

    private func respond(approvalID: String, approved: Bool) {
        Task {
            await store.respondToApproval(
                conversationID: conversationID,
                approvalID: approvalID,
                approved: approved,
                using: auth
            )
        }
    }
}

private struct ToolParametersPanel: View {
    let value: JSONValue

    @State private var expanded = false
    @State private var copied = false

    private var summary: String {
        ToolParameterFormatter.summary(value)
    }

    @ViewBuilder
    var body: some View {
        if !summary.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                if expanded {
                    let preview = ToolParameterFormatter.preview(value)
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Text(preview.text)
                                .font(.system(.caption2, design: .monospaced))
                                .fixedSize(horizontal: true, vertical: true)
                                .padding(8)
                        }
                        .frame(height: previewHeight(for: preview.text))

                        if preview.truncated {
                            Text(
                                "Preview limited to 12,000 characters, 10 array items, and 4 levels. Copy to inspect the complete parameters."
                            )
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) {
                                Divider()
                            }
                        }
                    }
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 6)
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Parameters")
                        .font(.system(size: 10, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Button {
                        UIPasteboard.general.string = ToolParameterFormatter.fullText(value)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Copy full parameters")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func previewHeight(for text: String) -> CGFloat {
        let lines = text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        return min(max(CGFloat(lines) * 15 + 16, 32), 320)
    }
}

private struct JSONSection: View {
    let title: String
    let value: JSONValue

    /// Above this length the payload is truncated in the UI to avoid the
    /// stutter of laying out a very large monospaced Text; the full value is
    /// always available via the copy button.
    private static let previewLimit = 600

    private var fullText: String { value.prettyPrinted }
    private var isTruncated: Bool { fullText.count > Self.previewLimit }

    private var displayText: String {
        guard isTruncated else { return fullText }
        return String(fullText.prefix(Self.previewLimit))
            + "\n… (\(fullText.count - Self.previewLimit) more characters)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = fullText
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy \(title)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayText)
                    .font(.system(.caption2, design: .monospaced))
            }
            .padding(8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ArchivedConversationsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var deleteTarget: ChatConversation?

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoadingArchived, !store.hasLoadedArchived {
                    ProgressView("Loading archived conversations…")
                } else if store.archivedConversations.isEmpty {
                    ContentUnavailableView(
                        "No Archived Conversations",
                        systemImage: "archivebox",
                        description: Text("Archived conversations will appear here.")
                    )
                } else {
                    ScrollView {
                        if let error = store.archivedErrorMessage {
                            InlineErrorBanner(message: error) {
                                Task { await store.loadArchived(using: auth) }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(store.archivedConversations) { conversation in
                                HStack(spacing: 10) {
                                    ArchivedConversationCard(conversation: conversation)
                                    if store.mutatingConversationIDs.contains(conversation.id) {
                                        ProgressView().controlSize(.small)
                                            .frame(width: 30, height: 30)
                                    } else {
                                        Menu {
                                            Button {
                                                Task { try? await store.unarchive(conversation, using: auth) }
                                            } label: {
                                                Label("Restore", systemImage: "arrow.uturn.backward")
                                            }
                                            Button(role: .destructive) {
                                                deleteTarget = conversation
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .frame(width: 30, height: 30)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(
                                    Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .contextMenu {
                                    Button {
                                        Task { try? await store.unarchive(conversation, using: auth) }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    Button(role: .destructive) {
                                        deleteTarget = conversation
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .refreshable { await store.loadArchived(using: auth) }
                }
            }
            .navigationTitle("Archived")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.hasLoadedArchived, store.archivedTotalItems > 0 {
                    VStack(spacing: 0) {
                        Divider()
                        PaginationBar(
                            pageCount: store.archivedTotalPages,
                            page: archivedPageBinding,
                            alwaysVisible: true
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(.bar)
                }
            }
            .task { await store.loadArchived(using: auth) }
            .alert("Delete archived conversation?", isPresented: deletePresented) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) {
                    guard let conversation = deleteTarget else { return }
                    Task {
                        if await store.delete(conversation, using: auth) {
                            deleteTarget = nil
                        }
                    }
                }
            } message: {
                Text("This permanently deletes \(deleteTarget?.title ?? "the conversation") and all of its messages.")
            }
        }
    }

    private var archivedPageBinding: Binding<Int> {
        Binding(
            get: { store.archivedPage },
            set: { newPage in Task { await store.loadArchivedPage(newPage, using: auth) } }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }
}
