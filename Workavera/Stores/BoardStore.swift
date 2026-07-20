import Foundation
import Observation

@MainActor
@Observable
final class BoardStore {
    static let projectsPerPage = 4

    private(set) var projects: [BoardProject] = []
    private(set) var page = 0
    private(set) var totalPages = 1
    private(set) var totalItems = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var updatingTaskIDs: Set<String> = []

    private var loadSequence = 0
    private var cachedUserID: String?

    func reset() {
        loadSequence += 1
        projects = []
        page = 0
        totalPages = 1
        totalItems = 0
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        updatingTaskIDs = []
        cachedUserID = nil
    }

    func loadIfNeeded(using auth: AuthStore) async {
        guard prepareCache(for: auth) else { return }
        guard !hasLoaded, !isLoading else { return }
        await refresh(using: auth)
    }

    func refresh(using auth: AuthStore, page requestedPage: Int? = nil) async {
        guard prepareCache(for: auth) else { return }
        let targetPage = max(0, requestedPage ?? page)
        loadSequence += 1
        let sequence = loadSequence
        isLoading = true
        defer {
            if sequence == loadSequence { isLoading = false }
        }

        do {
            let snapshot = try await auth.loadBoardPage(
                page: targetPage + 1,
                pageSize: Self.projectsPerPage
            )
            guard sequence == loadSequence else { return }
            projects = snapshot.projects
            page = max(0, snapshot.page - 1)
            totalPages = max(1, snapshot.totalPages)
            totalItems = snapshot.totalItems
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

    func loadPage(_ page: Int, using auth: AuthStore) async {
        await refresh(using: auth, page: min(max(0, page), totalPages - 1))
    }

    func moveTask(_ task: BoardTask, to stateID: String, using auth: AuthStore) async -> Bool {
        guard task.stateID != stateID,
              !updatingTaskIDs.contains(task.id),
              let projectIndex = projects.firstIndex(where: { $0.id == task.projectID }),
              let fromStateIndex = projects[projectIndex].states.firstIndex(where: { $0.id == task.stateID }),
              let taskIndex = projects[projectIndex].states[fromStateIndex].tasks.firstIndex(where: { $0.id == task.id }),
              let toStateIndex = projects[projectIndex].states.firstIndex(where: { $0.id == stateID }) else {
            return false
        }

        let previousProjects = projects
        let nextRank = (projects[projectIndex].states[toStateIndex].tasks.map(\.rank).max() ?? 0) + 1024
        var moved = projects[projectIndex].states[fromStateIndex].tasks.remove(at: taskIndex)
        moved.stateID = stateID
        moved.rank = nextRank
        projects[projectIndex].states[toStateIndex].tasks.append(moved)
        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }

        do {
            try await auth.moveBoardTask(id: task.id, stateID: stateID, rank: nextRank)
            errorMessage = nil
            return true
        } catch {
            projects = previousProjects
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updatePriority(
        of task: BoardTask,
        to priority: TaskPriority,
        using auth: AuthStore
    ) async -> Bool {
        guard task.priority != priority,
              !updatingTaskIDs.contains(task.id),
              let projectIndex = projects.firstIndex(where: { $0.id == task.projectID }),
              let stateIndex = projects[projectIndex].states.firstIndex(where: { $0.id == task.stateID }),
              let taskIndex = projects[projectIndex].states[stateIndex].tasks.firstIndex(where: { $0.id == task.id }) else {
            return false
        }

        let previousPriority = projects[projectIndex].states[stateIndex].tasks[taskIndex].priority
        projects[projectIndex].states[stateIndex].tasks[taskIndex].priority = priority
        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }

        do {
            try await auth.updateBoardTaskPriority(id: task.id, priority: priority)
            errorMessage = nil
            return true
        } catch {
            projects[projectIndex].states[stateIndex].tasks[taskIndex].priority = previousPriority
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
