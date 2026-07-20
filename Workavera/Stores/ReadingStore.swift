import Foundation
import Observation

@MainActor
@Observable
final class ReadingStore {
    static let pageSize = 6

    private(set) var items: [ReadingItem] = []
    private(set) var filter: ReadingListFilter = .active
    private(set) var query = ""
    private(set) var page = 0
    private(set) var totalPages = 1
    private(set) var totalItems = 0
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var mutatingItemIDs: Set<String> = []
    private(set) var isMarkingAllRead = false

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        items = []
        filter = .active
        query = ""
        page = 0
        totalPages = 1
        totalItems = 0
        unreadCount = 0
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        mutatingItemIDs = []
        isMarkingAllRead = false
        cachedUserID = nil
    }

    func loadIfNeeded(using auth: AuthStore) async {
        guard prepareCache(for: auth), !hasLoaded, !isLoading else { return }
        await refresh(using: auth)
    }

    func refresh(using auth: AuthStore, page requestedPage: Int? = nil) async {
        guard prepareCache(for: auth) else { return }
        let targetPage = min(max(0, requestedPage ?? page), totalPages - 1)
        loadSequence += 1
        let sequence = loadSequence
        isLoading = true
        defer {
            if sequence == loadSequence { isLoading = false }
        }

        do {
            let result = try await auth.loadReadingPage(
                filter: filter,
                page: targetPage + 1,
                pageSize: Self.pageSize,
                query: query
            )
            guard sequence == loadSequence else { return }
            items = result.items
            page = max(0, result.page - 1)
            totalPages = max(1, result.totalPages)
            totalItems = result.totalItems
            unreadCount = result.unreadCount
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == loadSequence else { return }
            hasLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    func selectFilter(_ newFilter: ReadingListFilter, using auth: AuthStore) async {
        guard filter != newFilter else { return }
        filter = newFilter
        page = 0
        await refresh(using: auth, page: 0)
    }

    func search(_ newQuery: String, using auth: AuthStore) async {
        let normalized = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != normalized else { return }
        query = normalized
        page = 0
        await refresh(using: auth, page: 0)
    }

    func loadPage(_ newPage: Int, using auth: AuthStore) async {
        await refresh(using: auth, page: min(max(0, newPage), totalPages - 1))
    }

    func create(_ input: ReadingItemInput, using auth: AuthStore) async throws -> ReadingItem {
        do {
            let item = try await auth.createReadingItem(input: input)
            filter = .active
            query = ""
            page = 0
            await refresh(using: auth, page: 0)
            errorMessage = nil
            return item
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func updateStatus(
        _ item: ReadingItem,
        status: ReadingStatus,
        using auth: AuthStore
    ) async throws -> ReadingItem {
        guard !mutatingItemIDs.contains(item.id) else { return item }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            let updated = try await auth.updateReadingStatus(id: item.id, status: status)
            await refresh(using: auth)
            errorMessage = nil
            return updated
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func togglePin(_ item: ReadingItem, using auth: AuthStore) async throws -> ReadingItem {
        guard !mutatingItemIDs.contains(item.id) else { return item }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            try await auth.setReadingPinned(id: item.id, pinned: !item.pinned)
            var updated = item
            updated.pinned.toggle()
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
            await refresh(using: auth)
            errorMessage = nil
            return updated
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ item: ReadingItem, using auth: AuthStore) async -> Bool {
        guard !mutatingItemIDs.contains(item.id) else { return false }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            try await auth.deleteReadingItem(id: item.id)
            await refresh(using: auth)
            if items.isEmpty, page > 0, totalItems > 0 {
                await refresh(using: auth, page: page - 1)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func summarize(_ item: ReadingItem, using auth: AuthStore) async throws -> ReadingItem {
        guard !mutatingItemIDs.contains(item.id) else { return item }
        mutatingItemIDs.insert(item.id)
        defer { mutatingItemIDs.remove(item.id) }
        do {
            let response = try await auth.summarizeReadingItem(id: item.id)
            var updated = item
            updated.contentText = response.contentText
            updated.summary = response.summary
            updated.keyPoints = response.keyPoints
            updated.updatedAt = .now
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
            errorMessage = nil
            return updated
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func markAllRead(using auth: AuthStore) async {
        guard !isMarkingAllRead else { return }
        isMarkingAllRead = true
        defer { isMarkingAllRead = false }
        do {
            _ = try await auth.markAllReadingItemsRead()
            await refresh(using: auth)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func item(id: String) -> ReadingItem? {
        items.first { $0.id == id }
    }

    func clearError() {
        errorMessage = nil
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
}
