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

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                conversationPane(usesNavigationLinks: true)
            }
        }
        .background(Color(.systemGroupedBackground))
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

                    chatSearchField

                    conversationList(usesNavigationLinks: usesNavigationLinks)
                }
                .padding(.vertical, 12)
            }
            .refreshable { await store.refresh(using: auth) }
            .safeAreaInset(edge: .bottom) {
                if store.hasLoaded, store.totalItems > 0 {
                    VStack(spacing: 0) {
                        Divider()
                        PaginationBar(
                            pageCount: store.totalPages,
                            page: activePageBinding,
                            alwaysVisible: true
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(.bar)
                }
            }
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

    private var chatSearchField: some View {
        WorkspaceSearchField(
            text: $searchInput,
            prompt: "Search conversations",
            onSubmit: { Task { await store.search(searchInput, using: auth) } },
            onClear: { Task { await store.search("", using: auth) } }
        )
        .padding(.horizontal, 12)
    }

    private func createConversation() {
        searchInput = ""
        Task { _ = try? await store.create(using: auth) }
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
                NavigationLink {
                    ChatConversationDetailView(conversationID: conversation.id)
                        .onAppear { store.select(conversation.id) }
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

    private var conversation: ChatConversation? {
        store.conversations.first { $0.id == conversationID }
    }

    private var messages: [ChatMessage] {
        store.messages(for: conversationID)
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
                VStack(spacing: 0) {
                    messageHistory
                    ChatComposer(
                        draft: $draft,
                        selectedModelID: $selectedModelID,
                        models: modelStore.models,
                        contextInfo: contextInfo,
                        isLoading: isLoadingMessages,
                        isGenerating: isGenerating,
                        send: submit,
                        stop: { Task { await store.stopRun(conversationID: conversationID, using: auth) } }
                    )
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(messages) { message in
                            ChatMessageView(
                                message: message,
                                conversationID: conversationID,
                                runActive: message.metadata?.runID == store.activeRunIDs[conversationID]
                            )
                            .id(message.id)
                        }

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
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: messageScrollSignature) { _, _ in
                    guard let lastID = messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var messageScrollSignature: String {
        let last = messages.last
        let textLength = last?.parts.reduce(0) { $0 + ($1.text?.count ?? 0) } ?? 0
        return "\(messages.count):\(last?.id ?? ""):\(last?.parts.count ?? 0):\(textLength)"
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
        guard !content.isEmpty, !selectedModelID.isEmpty, !isGenerating else { return }
        draft = ""
        Task {
            await store.sendMessage(
                content,
                conversationID: conversationID,
                modelConfigID: selectedModelID,
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

private struct ChatComposer: View {
    @Binding var draft: String
    @Binding var selectedModelID: String

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
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Fenced code block with a language tag, copy button, monospaced content,
/// and a theme-aware gray surface. Horizontally scrollable for long lines.
private struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(languageLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                    }
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .markdownMargin(bottom: 12)
    }

    private var languageLabel: String {
        let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return language.isEmpty ? "code" : language.lowercased()
    }

    private func copy() {
        UIPasteboard.general.string = configuration.content
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}

/// Lightweight, dependency-free syntax colorizer. It doesn't parse any single
/// language precisely; it applies one uniform color scheme to the elements
/// common across languages — comments, strings, numbers, and keywords — which
/// is enough for readable chat code blocks.
private struct WorkspaceCodeHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        CodeColoring.segments(of: code).reduce(Text("")) { partial, segment in
            let piece = Text(segment.text)
            return partial + (segment.color.map { piece.foregroundColor($0) } ?? piece)
        }
    }
}

private enum CodeColoring {
    struct Segment {
        let text: String
        let color: Color?
    }

    private static let keywords = [
        "func", "function", "def", "fn", "return", "let", "var", "const", "val",
        "class", "struct", "enum", "interface", "protocol", "extension", "import",
        "export", "from", "package", "namespace", "if", "else", "elif", "for",
        "while", "do", "switch", "case", "break", "continue", "default", "guard",
        "defer", "try", "catch", "throw", "throws", "finally", "async", "await",
        "yield", "public", "private", "protected", "internal", "static", "final",
        "abstract", "override", "new", "self", "this", "super", "nil", "null",
        "true", "false", "void", "in", "is", "as", "typeof", "instanceof",
        "lambda", "where", "pub", "impl", "trait", "match", "mut", "use",
    ].joined(separator: "|")

    private static let regex: NSRegularExpression? = {
        let pattern = #"(?<comment>//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/)|(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(?<number>\b0x[0-9a-fA-F]+\b|\b\d[\d_]*\.?\d*\b)|(?<keyword>\b(?:\#(keywords))\b)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    static func segments(of code: String) -> [Segment] {
        guard let regex else { return [Segment(text: code, color: nil)] }
        let ns = code as NSString
        var segments: [Segment] = []
        var cursor = 0

        regex.enumerateMatches(in: code, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let range = match.range
            if range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                segments.append(Segment(text: plain, color: nil))
            }
            segments.append(Segment(text: ns.substring(with: range), color: color(for: match)))
            cursor = range.location + range.length
        }

        if cursor < ns.length {
            segments.append(Segment(text: ns.substring(from: cursor), color: nil))
        }
        return segments
    }

    private static func color(for match: NSTextCheckingResult) -> Color? {
        if match.range(withName: "comment").location != NSNotFound { return SyntaxColor.comment }
        if match.range(withName: "string").location != NSNotFound { return SyntaxColor.string }
        if match.range(withName: "number").location != NSNotFound { return SyntaxColor.number }
        if match.range(withName: "keyword").location != NSNotFound { return SyntaxColor.keyword }
        return nil
    }
}

/// Xcode-like token colors that adapt to light/dark appearance.
private enum SyntaxColor {
    static let keyword = dynamic(light: (0.61, 0.12, 0.55), dark: (0.94, 0.47, 0.71))
    static let string = dynamic(light: (0.77, 0.20, 0.18), dark: (0.98, 0.60, 0.54))
    static let number = dynamic(light: (0.11, 0.35, 0.80), dark: (0.60, 0.80, 1.00))
    static let comment = dynamic(light: (0.42, 0.48, 0.44), dark: (0.50, 0.58, 0.55))

    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

private struct ChatMessageView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store

    let message: ChatMessage
    let conversationID: String
    let runActive: Bool

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(isUser ? "You" : "Assistant")
                    .fontWeight(.medium)
                if !isUser, let modelName = message.metadata?.model?.name {
                    Text("·")
                    Text(modelName)
                }
                if let date = message.metadata?.createdDate {
                    Text("·")
                    Text(date, format: .relative(presentation: .named))
                }
                if message.metadata?.status == .streaming {
                    Text("STREAMING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if isUser {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                        if part.type == "text", let text = part.text {
                            Text(text)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.body)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 620, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                        AssistantMessagePartView(
                            part: part,
                            approvalData: approvalData(for: part),
                            conversationID: conversationID,
                            runActive: runActive,
                            messageStatus: message.metadata?.status
                        )
                    }

                    if let error = message.metadata?.error {
                        Label(error.message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let usage = message.metadata?.usage,
                   usage.inputTokens > 0 || usage.outputTokens > 0 {
                    Text("↑ \(usage.inputTokens) in   ↓ \(usage.outputTokens) out")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func approvalData(for toolPart: ChatMessagePart) -> JSONValue? {
        guard toolPart.type == "dynamic-tool", let toolCallID = toolPart.toolCallID else { return nil }
        return message.parts.first(where: { part in
            guard part.type == "data-approval",
                  let object = part.data?.objectValue else { return false }
            return object["toolCallId"]?.stringValue == toolCallID
        })?.data
    }
}

private struct AssistantMessagePartView: View {
    let part: ChatMessagePart
    let approvalData: JSONValue?
    let conversationID: String
    let runActive: Bool
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
                        .textSelection(.enabled)
                } else {
                    Markdown(text)
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            CodeBlockView(configuration: configuration)
                        }
                        .markdownCodeSyntaxHighlighter(WorkspaceCodeHighlighter())
                        .textSelection(.enabled)
                }
            }
        case "reasoning":
            if let text = part.text, !text.isEmpty {
                ReasoningDisclosure(text: text, isStreaming: isStreaming)
            }
        case "dynamic-tool":
            ChatToolCard(
                part: part,
                approvalData: approvalData,
                conversationID: conversationID,
                runActive: runActive,
                messageStatus: messageStatus
            )
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

private struct ChatToolCard: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store

    let part: ChatMessagePart
    let approvalData: JSONValue?
    let conversationID: String
    let runActive: Bool
    let messageStatus: ChatMessageStatus?

    @State private var expanded = false

    private var approvalObject: [String: JSONValue]? { approvalData?.objectValue }
    private var approvalID: String? { approvalObject?["approvalId"]?.stringValue }
    private var awaitingApproval: Bool {
        part.state == "approval-requested"
            && runActive
            && messageStatus != .error
            && messageStatus != .cancelled
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = approvalObject?["summary"]?.stringValue {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let input = part.input {
                    JSONSection(title: "Input", value: input)
                }
                if let output = part.output {
                    JSONSection(title: "Output", value: output)
                }
                if let errorText = part.errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                    .textSelection(.enabled)
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
