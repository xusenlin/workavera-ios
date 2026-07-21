import Foundation
import Observation

@MainActor
@Observable
final class SavedMemoriesStore {
    private(set) var memories: [SavedChatMemory] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var mutatingIDs: Set<String> = []

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        memories = []
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        mutatingIDs = []
        cachedUserID = nil
    }

    func loadForPresentation(using auth: AuthStore) async {
        guard prepareCache(for: auth), !isLoading else { return }
        await CachedPageLoader.load(
            hasPresentedContent: hasLoaded,
            cache: { await refresh(using: auth, strategy: .cacheOnly, reportError: false) },
            network: { await refresh(using: auth) }
        )
    }

    func refresh(
        using auth: AuthStore,
        strategy: DataLoadStrategy = .networkOnly,
        reportError: Bool = true
    ) async {
        guard prepareCache(for: auth) else { return }
        loadSequence += 1
        let sequence = loadSequence
        isLoading = true
        defer {
            if sequence == loadSequence { isLoading = false }
        }

        do {
            let loaded = try await auth.loadSavedMemories(strategy: strategy)
            guard sequence == loadSequence else { return }
            memories = loaded
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

    func upsert(_ memory: SavedChatMemory) {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
        memories.sort { $0.updatedAt > $1.updatedAt }
        errorMessage = nil
    }

    func toggle(_ memory: SavedChatMemory, active: Bool, using auth: AuthStore) async {
        guard !mutatingIDs.contains(memory.id) else { return }
        mutatingIDs.insert(memory.id)
        defer { mutatingIDs.remove(memory.id) }
        do {
            upsert(try await auth.setSavedMemoryActive(id: memory.id, active: active))
            await refresh(using: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ memory: SavedChatMemory, using auth: AuthStore) async -> Bool {
        guard !mutatingIDs.contains(memory.id) else { return false }
        mutatingIDs.insert(memory.id)
        defer { mutatingIDs.remove(memory.id) }
        do {
            try await auth.deleteSavedMemory(id: memory.id)
            memories.removeAll { $0.id == memory.id }
            await refresh(using: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAll(using auth: AuthStore) async -> (deleted: Int, failed: Int) {
        let ids = memories.map(\.id)
        var deleted = 0
        for id in ids {
            do {
                try await auth.deleteSavedMemory(id: id)
                memories.removeAll { $0.id == id }
                deleted += 1
            } catch {
                // Continue so a partial server failure does not hide successful deletions.
            }
        }
        let failed = ids.count - deleted
        if failed == 0 {
            await refresh(using: auth)
        } else {
            errorMessage = "Deleted \(deleted) memories, but \(failed) could not be removed."
        }
        return (deleted, failed)
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
