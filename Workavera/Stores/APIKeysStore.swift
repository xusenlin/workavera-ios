import Foundation
import Observation

@MainActor
@Observable
final class APIKeysStore {
    private(set) var keys: [WorkaveraAPIKey] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var revokingKeyIDs: Set<String> = []

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        keys = []
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        revokingKeyIDs = []
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
            let loaded = try await auth.loadAPIKeys(strategy: strategy)
            guard sequence == loadSequence else { return }
            keys = loaded
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

    func revoke(_ key: WorkaveraAPIKey, using auth: AuthStore) async -> Bool {
        guard !revokingKeyIDs.contains(key.id) else { return false }
        revokingKeyIDs.insert(key.id)
        defer { revokingKeyIDs.remove(key.id) }
        do {
            try await auth.revokeAPIKey(id: key.id)
            keys.removeAll { $0.id == key.id }
            await refresh(using: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
