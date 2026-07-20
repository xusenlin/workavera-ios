import Foundation
import Observation

@MainActor
@Observable
final class DashboardStore {
    private(set) var summary: DashboardSummary?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        summary = nil
        isLoading = false
        errorMessage = nil
        cachedUserID = nil
    }

    func loadIfNeeded(using auth: AuthStore) async {
        guard prepareCache(for: auth), summary == nil, !isLoading else { return }
        await refresh(using: auth)
    }

    func refresh(using auth: AuthStore) async {
        guard prepareCache(for: auth) else { return }
        loadSequence += 1
        let sequence = loadSequence
        isLoading = true
        defer {
            if sequence == loadSequence { isLoading = false }
        }

        do {
            let loaded = try await auth.loadDashboardSummary()
            guard sequence == loadSequence else { return }
            summary = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == loadSequence else { return }
            errorMessage = error.localizedDescription
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
