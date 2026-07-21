import Foundation
import Observation

@MainActor
@Observable
final class ChatStore {
    static let pageSize = 20
    static let archivedPageSize = 10
    /// Minimum interval between UI refreshes while a response streams in.
    private static let streamFlushInterval: Duration = .milliseconds(80)

    private(set) var conversations: [ChatConversation] = []
    private(set) var selectedConversationID: String?
    private(set) var query = ""
    private(set) var page = 0
    private(set) var totalPages = 1
    private(set) var totalItems = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    private(set) var archivedConversations: [ChatConversation] = []
    private(set) var archivedPage = 0
    private(set) var archivedTotalPages = 1
    private(set) var archivedTotalItems = 0
    private(set) var isLoadingArchived = false
    private(set) var hasLoadedArchived = false
    private(set) var archivedErrorMessage: String?

    private(set) var mutatingConversationIDs: Set<String> = []
    private(set) var isCreating = false

    private(set) var messagesByConversationID: [String: [ChatMessage]] = [:]
    private(set) var loadingMessageConversationIDs: Set<String> = []
    private(set) var activeRunIDs: [String: String] = [:]
    private(set) var messageErrorMessages: [String: String] = [:]
    private(set) var submittingApprovalIDs: Set<String> = []

    private var cachedUserID: String?
    private var loadSequence = 0
    private var archivedLoadSequence = 0
    private var streamTasks: [String: Task<Void, Never>] = [:]

    var selectedConversation: ChatConversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    func messages(for conversationID: String) -> [ChatMessage] {
        messagesByConversationID[conversationID] ?? []
    }

    func isGenerating(_ conversationID: String) -> Bool {
        activeRunIDs[conversationID] != nil
    }

    func reset() {
        for task in streamTasks.values { task.cancel() }
        streamTasks = [:]
        loadSequence += 1
        archivedLoadSequence += 1
        conversations = []
        selectedConversationID = nil
        query = ""
        page = 0
        totalPages = 1
        totalItems = 0
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        archivedConversations = []
        archivedPage = 0
        archivedTotalPages = 1
        archivedTotalItems = 0
        isLoadingArchived = false
        hasLoadedArchived = false
        archivedErrorMessage = nil
        mutatingConversationIDs = []
        isCreating = false
        messagesByConversationID = [:]
        loadingMessageConversationIDs = []
        activeRunIDs = [:]
        messageErrorMessages = [:]
        submittingApprovalIDs = []
        cachedUserID = nil
    }

    func loadForPresentation(using auth: AuthStore) async {
        guard prepareCache(for: auth), !isLoading else { return }
        await CachedPageLoader.load(
            hasPresentedContent: hasLoaded,
            cache: {
                await refresh(using: auth, strategy: .cacheOnly, reportError: false)
            },
            network: { await refresh(using: auth) }
        )
    }

    func refresh(
        using auth: AuthStore,
        page requestedPage: Int? = nil,
        strategy: DataLoadStrategy = .networkOnly,
        reportError: Bool = true
    ) async {
        guard prepareCache(for: auth) else { return }
        let targetPage = min(max(0, requestedPage ?? page), totalPages - 1)
        loadSequence += 1
        let sequence = loadSequence
        isLoading = true
        defer {
            if sequence == loadSequence { isLoading = false }
        }

        do {
            let result = try await auth.loadChatConversations(
                status: .active,
                page: targetPage + 1,
                pageSize: Self.pageSize,
                query: query,
                strategy: strategy
            )
            guard sequence == loadSequence else { return }
            conversations = result.items
            page = max(0, result.page - 1)
            totalPages = max(1, result.totalPages)
            totalItems = result.totalItems
            reconcileSelection()
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == loadSequence else { return }
            if reportError {
                hasLoaded = true
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadPage(_ newPage: Int, using auth: AuthStore) async {
        await refresh(using: auth, page: min(max(0, newPage), totalPages - 1))
    }

    func search(_ newQuery: String, using auth: AuthStore) async {
        let normalized = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != normalized else { return }
        query = normalized
        page = 0
        totalPages = 1
        await refresh(using: auth, page: 0)
    }

    func select(_ conversationID: String?) {
        guard conversationID == nil || conversations.contains(where: { $0.id == conversationID }) else {
            return
        }
        selectedConversationID = conversationID
    }

    func loadMessages(
        for conversationID: String,
        using auth: AuthStore,
        force: Bool = false,
        recoverActiveRun: Bool = true
    ) async {
        guard prepareCache(for: auth),
              force || messagesByConversationID[conversationID] == nil,
              !loadingMessageConversationIDs.contains(conversationID) else { return }
        loadingMessageConversationIDs.insert(conversationID)
        defer { loadingMessageConversationIDs.remove(conversationID) }

        do {
            let loaded = try await auth.loadChatMessages(conversationID: conversationID)
            messageErrorMessages[conversationID] = nil
            if recoverActiveRun,
               let last = loaded.last,
               last.role == .assistant,
               last.metadata?.status == .streaming,
               let runID = last.metadata?.runID {
                messagesByConversationID[conversationID] = Array(loaded.dropLast())
                resumeRun(conversationID: conversationID, runID: runID, using: auth)
            } else {
                messagesByConversationID[conversationID] = loaded
                activeRunIDs[conversationID] = nil
                if !recoverActiveRun, loaded.last?.metadata?.status == .streaming {
                    messageErrorMessages[conversationID] =
                        "The response is still running, but its stream could not be reconnected."
                }
            }
        } catch is CancellationError {
            return
        } catch {
            messageErrorMessages[conversationID] = error.localizedDescription
        }
    }

    func sendMessage(
        _ text: String,
        conversationID: String,
        modelConfigID: String,
        using auth: AuthStore
    ) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              !modelConfigID.isEmpty,
              activeRunIDs[conversationID] == nil else { return }

        let runID = UUID().uuidString.lowercased()
        let clientMessageID = UUID().uuidString.lowercased()
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let userMessage = ChatMessage(
            id: clientMessageID,
            role: .user,
            metadata: ChatMessageMetadata(
                conversationID: conversationID,
                status: .complete,
                createdAt: createdAt
            ),
            parts: [ChatMessagePart(type: "text", text: content, state: "done")]
        )
        let request = ChatStreamRequest(
            runID: runID,
            conversationID: conversationID,
            modelConfigID: modelConfigID,
            message: ChatMessage(
                id: clientMessageID,
                role: .user,
                parts: [ChatMessagePart(type: "text", text: content)]
            )
        )

        do {
            let stream = try auth.startChatStream(request: request)
            messageErrorMessages[conversationID] = nil
            activeRunIDs[conversationID] = runID
            var messages = messagesByConversationID[conversationID] ?? []
            messages.append(userMessage)
            let reducer = ChatStreamReducer(messageID: "stream-\(runID)", runID: runID)
            messages.append(reducer.message)
            messagesByConversationID[conversationID] = messages
            consume(
                stream,
                reducer: reducer,
                conversationID: conversationID,
                runID: runID,
                using: auth
            )

            if let conversation = conversations.first(where: { $0.id == conversationID }),
               conversation.title == "New conversation" {
                try? await rename(
                    conversation,
                    title: String(content.prefix(16)),
                    using: auth
                )
            }
        } catch {
            activeRunIDs[conversationID] = nil
            messageErrorMessages[conversationID] = error.localizedDescription
        }
    }

    func stopRun(conversationID: String, using auth: AuthStore) async {
        guard let runID = activeRunIDs[conversationID] else { return }
        do {
            try await auth.stopChatRun(runID: runID)
        } catch {
            messageErrorMessages[conversationID] = error.localizedDescription
        }
    }

    func respondToApproval(
        conversationID: String,
        approvalID: String,
        approved: Bool,
        using auth: AuthStore
    ) async {
        guard let runID = activeRunIDs[conversationID],
              !submittingApprovalIDs.contains(approvalID) else { return }
        submittingApprovalIDs.insert(approvalID)
        defer { submittingApprovalIDs.remove(approvalID) }
        do {
            try await auth.respondToChatApproval(
                runID: runID,
                approvalID: approvalID,
                approved: approved
            )
            messageErrorMessages[conversationID] = nil
        } catch {
            messageErrorMessages[conversationID] = error.localizedDescription
        }
    }

    @discardableResult
    func create(using auth: AuthStore) async throws -> ChatConversation {
        guard !isCreating else {
            throw APIError.http(
                statusCode: 409,
                message: "A conversation is already being created.",
                fieldMessages: [:]
            )
        }
        isCreating = true
        defer { isCreating = false }

        do {
            let created = try await auth.createChatConversation()
            query = ""
            page = 0
            conversations.removeAll { $0.id == created.id }
            conversations.insert(created, at: 0)
            totalItems += 1
            totalPages = max(1, Int(ceil(Double(totalItems) / Double(Self.pageSize))))
            selectedConversationID = created.id
            hasLoaded = true
            errorMessage = nil
            await refresh(using: auth, page: 0)
            selectedConversationID = conversations.contains(where: { $0.id == created.id })
                ? created.id
                : selectedConversationID
            return created
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func rename(
        _ conversation: ChatConversation,
        title: String,
        using auth: AuthStore
    ) async throws {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != conversation.title else { return }
        guard normalized.count <= 200 else {
            throw APIError.http(
                statusCode: 400,
                message: "Conversation titles cannot exceed 200 characters.",
                fieldMessages: [:]
            )
        }
        try await mutate(conversation, using: auth) {
            try await auth.updateChatConversation(
                id: conversation.id,
                update: ChatConversationUpdate(title: normalized)
            )
        }
    }

    func togglePin(_ conversation: ChatConversation, using auth: AuthStore) async throws {
        try await mutate(conversation, using: auth) {
            try await auth.updateChatConversation(
                id: conversation.id,
                update: ChatConversationUpdate(pinned: !conversation.pinned)
            )
        }
        conversations.sort(by: Self.activeSort)
    }

    func archive(_ conversation: ChatConversation, using auth: AuthStore) async throws {
        guard !mutatingConversationIDs.contains(conversation.id) else { return }
        mutatingConversationIDs.insert(conversation.id)
        defer { mutatingConversationIDs.remove(conversation.id) }

        do {
            let archived = try await auth.updateChatConversation(
                id: conversation.id,
                update: ChatConversationUpdate(status: .archived)
            )
            removeActiveConversation(id: conversation.id)
            if hasLoadedArchived {
                archivedConversations.removeAll { $0.id == archived.id }
                archivedConversations.insert(archived, at: 0)
                archivedTotalItems += 1
                archivedTotalPages = Self.pageCount(
                    totalItems: archivedTotalItems,
                    pageSize: Self.archivedPageSize
                )
            }
            errorMessage = nil
            await fillActivePageIfNeeded(using: auth)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ conversation: ChatConversation, using auth: AuthStore) async -> Bool {
        guard !mutatingConversationIDs.contains(conversation.id) else { return false }
        mutatingConversationIDs.insert(conversation.id)
        defer { mutatingConversationIDs.remove(conversation.id) }

        do {
            try await auth.deleteChatConversation(id: conversation.id)
            streamTasks[conversation.id]?.cancel()
            streamTasks[conversation.id] = nil
            messagesByConversationID[conversation.id] = nil
            activeRunIDs[conversation.id] = nil
            messageErrorMessages[conversation.id] = nil
            if conversation.status == .archived {
                removeArchivedConversation(id: conversation.id)
                await fillArchivedPageIfNeeded(using: auth)
            } else {
                removeActiveConversation(id: conversation.id)
                await fillActivePageIfNeeded(using: auth)
            }
            errorMessage = nil
            archivedErrorMessage = nil
            return true
        } catch {
            if conversation.status == .archived {
                archivedErrorMessage = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func loadArchived(
        using auth: AuthStore,
        page requestedPage: Int? = nil,
        reportError: Bool = true
    ) async {
        guard prepareCache(for: auth) else { return }
        let targetPage = min(
            max(0, requestedPage ?? archivedPage),
            archivedTotalPages - 1
        )
        archivedLoadSequence += 1
        let sequence = archivedLoadSequence
        isLoadingArchived = true
        defer {
            if sequence == archivedLoadSequence { isLoadingArchived = false }
        }

        do {
            let result = try await auth.loadChatConversations(
                status: .archived,
                page: targetPage + 1,
                pageSize: Self.archivedPageSize
            )
            guard sequence == archivedLoadSequence else { return }
            archivedConversations = result.items
            archivedPage = max(0, result.page - 1)
            archivedTotalPages = max(1, result.totalPages)
            archivedTotalItems = result.totalItems
            hasLoadedArchived = true
            archivedErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == archivedLoadSequence else { return }
            if reportError {
                hasLoadedArchived = true
                archivedErrorMessage = error.localizedDescription
            }
        }
    }

    func loadArchivedPage(_ newPage: Int, using auth: AuthStore) async {
        await loadArchived(
            using: auth,
            page: min(max(0, newPage), archivedTotalPages - 1)
        )
    }

    func unarchive(_ conversation: ChatConversation, using auth: AuthStore) async throws {
        guard !mutatingConversationIDs.contains(conversation.id) else { return }
        mutatingConversationIDs.insert(conversation.id)
        defer { mutatingConversationIDs.remove(conversation.id) }

        do {
            let active = try await auth.updateChatConversation(
                id: conversation.id,
                update: ChatConversationUpdate(status: .active)
            )
            removeArchivedConversation(id: conversation.id)
            conversations.removeAll { $0.id == active.id }
            conversations.insert(active, at: 0)
            conversations.sort(by: Self.activeSort)
            totalItems += 1
            totalPages = Self.pageCount(totalItems: totalItems, pageSize: Self.pageSize)
            hasLoaded = true
            selectedConversationID = selectedConversationID ?? active.id
            archivedErrorMessage = nil
            await fillArchivedPageIfNeeded(using: auth)
        } catch {
            archivedErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearArchivedError() {
        archivedErrorMessage = nil
    }

    private func mutate(
        _ conversation: ChatConversation,
        using auth: AuthStore,
        operation: () async throws -> ChatConversation
    ) async throws {
        guard !mutatingConversationIDs.contains(conversation.id) else { return }
        mutatingConversationIDs.insert(conversation.id)
        defer { mutatingConversationIDs.remove(conversation.id) }
        do {
            let updated = try await operation()
            replace(updated)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func replace(_ conversation: ChatConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        if let index = archivedConversations.firstIndex(where: { $0.id == conversation.id }) {
            archivedConversations[index] = conversation
        }
    }

    private func removeActiveConversation(id: String) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        conversations.removeAll { $0.id == id }
        totalItems = max(0, totalItems - 1)
        totalPages = Self.pageCount(totalItems: totalItems, pageSize: Self.pageSize)
        if selectedConversationID == id {
            selectedConversationID = conversations.first?.id
        }
    }

    private func removeArchivedConversation(id: String) {
        guard archivedConversations.contains(where: { $0.id == id }) else { return }
        archivedConversations.removeAll { $0.id == id }
        archivedTotalItems = max(0, archivedTotalItems - 1)
        archivedTotalPages = Self.pageCount(
            totalItems: archivedTotalItems,
            pageSize: Self.archivedPageSize
        )
    }

    private func fillActivePageIfNeeded(using auth: AuthStore) async {
        if conversations.isEmpty, page > 0 {
            await refresh(using: auth, page: page - 1)
        } else {
            await refresh(using: auth, page: page)
        }
    }

    private func fillArchivedPageIfNeeded(using auth: AuthStore) async {
        if archivedConversations.isEmpty, archivedPage > 0 {
            await loadArchived(using: auth, page: archivedPage - 1)
        } else {
            await loadArchived(using: auth, page: archivedPage)
        }
    }

    private func reconcileSelection() {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return
        }
        selectedConversationID = conversations.first?.id
    }

    @discardableResult
    private func prepareCache(for auth: AuthStore) -> Bool {
        guard let userID = auth.user?.id else {
            if cachedUserID != nil { reset() }
            return false
        }
        guard cachedUserID != userID else { return true }
        reset()
        cachedUserID = userID
        return true
    }

    private static func pageCount(totalItems: Int, pageSize: Int) -> Int {
        max(1, Int(ceil(Double(totalItems) / Double(pageSize))))
    }

    private func resumeRun(
        conversationID: String,
        runID: String,
        using auth: AuthStore
    ) {
        guard streamTasks[conversationID] == nil else { return }
        do {
            let stream = try auth.resumeChatStream(runID: runID)
            activeRunIDs[conversationID] = runID
            consume(
                stream,
                reducer: ChatStreamReducer(messageID: "stream-\(runID)", runID: runID),
                conversationID: conversationID,
                runID: runID,
                using: auth
            )
        } catch {
            activeRunIDs[conversationID] = nil
            messageErrorMessages[conversationID] = error.localizedDescription
        }
    }

    private func consume(
        _ stream: AsyncThrowingStream<ChatStreamChunk, Error>,
        reducer initialReducer: ChatStreamReducer,
        conversationID: String,
        runID: String,
        using auth: AuthStore
    ) {
        guard streamTasks[conversationID] == nil else { return }
        streamTasks[conversationID] = Task { [weak self] in
            guard let self else { return }
            var reducer = initialReducer
            do {
                var lastFlush: ContinuousClock.Instant?
                for try await chunk in stream {
                    try Task.checkCancellation()
                    guard self.activeRunIDs[conversationID] == runID else { return }
                    reducer.apply(chunk)
                    // Throttle UI updates: coalesce bursts of tokens into at most
                    // one refresh per interval, but always render the first chunk
                    // immediately so the user sees the response start.
                    let now = ContinuousClock.now
                    if let lastFlush, now - lastFlush < Self.streamFlushInterval {
                        continue
                    }
                    lastFlush = now
                    self.upsertStreamMessage(
                        reducer.message,
                        conversationID: conversationID,
                        runID: runID
                    )
                }
                // Flush whatever the throttle may have skipped at the tail end.
                self.upsertStreamMessage(
                    reducer.message,
                    conversationID: conversationID,
                    runID: runID
                )
                self.messageErrorMessages[conversationID] = nil
            } catch is CancellationError {
                return
            } catch {
                var failedMessage = reducer.message
                if failedMessage.metadata?.status == .streaming {
                    failedMessage.metadata?.status = .error
                }
                self.upsertStreamMessage(
                    failedMessage,
                    conversationID: conversationID,
                    runID: runID
                )
                self.messageErrorMessages[conversationID] = error.localizedDescription
            }

            guard self.activeRunIDs[conversationID] == runID else { return }
            self.activeRunIDs[conversationID] = nil
            self.streamTasks[conversationID] = nil
            await self.loadMessages(
                for: conversationID,
                using: auth,
                force: true,
                recoverActiveRun: false
            )
            await self.refresh(using: auth)
        }
    }

    private func upsertStreamMessage(
        _ message: ChatMessage,
        conversationID: String,
        runID: String
    ) {
        var messages = messagesByConversationID[conversationID] ?? []
        if let index = messages.firstIndex(where: {
            $0.metadata?.runID == runID || $0.id == "stream-\(runID)"
        }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        messagesByConversationID[conversationID] = messages
    }

    private static func activeSort(lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.createdAt > rhs.createdAt
    }
}
