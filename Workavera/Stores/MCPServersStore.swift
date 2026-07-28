import Foundation
import Observation

@MainActor
@Observable
final class MCPServersStore {
    private(set) var servers: [MCPServer] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var mutatingServerIDs: Set<String> = []

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        servers = []
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        mutatingServerIDs = []
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
            let loaded = try await auth.loadMCPServers(strategy: strategy)
            guard sequence == loadSequence else { return }
            servers = loaded
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

    func setEnabled(_ enabled: Bool, serverID: String, using auth: AuthStore) async -> Bool {
        var update = MCPServerUpdate()
        update.enabled = enabled
        return await mutate(serverID: serverID, using: auth) {
            try await auth.updateMCPServer(id: serverID, input: update)
        }
    }

    func delete(_ server: MCPServer, using auth: AuthStore) async -> Bool {
        guard !mutatingServerIDs.contains(server.id) else { return false }
        mutatingServerIDs.insert(server.id)
        defer { mutatingServerIDs.remove(server.id) }
        do {
            try await auth.deleteMCPServer(id: server.id)
            servers.removeAll { $0.id == server.id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Replaces a server in place after a mutation so detail views that hold
    /// the value keep working; the caller decides whether a full reload is
    /// also needed.
    func replace(_ server: MCPServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func mutate(
        serverID: String,
        using auth: AuthStore,
        operation: () async throws -> MCPServer
    ) async -> Bool {
        guard !mutatingServerIDs.contains(serverID) else { return false }
        mutatingServerIDs.insert(serverID)
        defer { mutatingServerIDs.remove(serverID) }
        do {
            replace(try await operation())
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
