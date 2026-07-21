import Foundation
import Observation

@MainActor
@Observable
final class DashboardStore {
    private(set) var summary: DashboardSummary?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var isRealtimeConnected = false

    private var cachedUserID: String?
    private var loadSequence = 0
    private var isListening = false

    func reset() {
        loadSequence += 1
        summary = nil
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        isRealtimeConnected = false
        cachedUserID = nil
        isListening = false
    }

    func loadForPresentation(using auth: AuthStore) async {
        guard prepareCache(for: auth), !isLoading else { return }
        await CachedPageLoader.load(
            hasPresentedContent: summary != nil,
            cache: { await hydrateFromCache(using: auth) },
            network: { await refresh(using: auth) }
        )
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

    func clearError() {
        errorMessage = nil
    }

    func listenForRealtimeUpdates(using auth: AuthStore) async {
        guard !isListening, let userID = auth.user?.id else { return }
        isListening = true
        defer {
            isListening = false
            isRealtimeConnected = false
        }
        var retryDelay: UInt64 = 1

        while !Task.isCancelled, auth.user?.id == userID {
            do {
                let signals = try auth.dashboardRealtimeSignals()
                isRealtimeConnected = true
                for try await _ in signals {
                    try Task.checkCancellation()
                    guard auth.user?.id == userID else { return }
                    await refresh(using: auth)
                    retryDelay = 1
                }
                isRealtimeConnected = false
            } catch is CancellationError {
                return
            } catch {
                isRealtimeConnected = false
            }

            do {
                try await Task.sleep(for: .seconds(retryDelay))
            } catch {
                return
            }
            retryDelay = min(retryDelay * 2, 30)
        }
    }

    private func hydrateFromCache(using auth: AuthStore) async {
        do {
            summary = try await auth.loadDashboardSummary(strategy: .cacheOnly)
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            // A cache miss is expected on the first launch. The network refresh below
            // owns any user-visible error.
        }
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
