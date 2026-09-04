import Foundation
import Observation

@MainActor
@Observable
final class BoardStore {
    static let projectsPerPage = 4
    static let archivedTasksPerPage = 10
    private static let selectionCachePrefix = "workavera.board.selection:"

    private(set) var projects: [BoardProject] = []
    private(set) var selectedProjectID: String?
    private(set) var selectedStateID: String?
    private(set) var page = 0
    private(set) var totalPages = 1
    private(set) var totalItems = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var updatingTaskIDs: Set<String> = []
    private(set) var isRealtimeConnected = false

    /// Public preview links, keyed by project. An id present in
    /// `resolvedShareIDs` but absent here is known not to be shared, which is
    /// what keeps the header icon from re-asking on every appearance. Share
    /// state is never cached to disk: a stale link would be shown as live long
    /// after it was revoked.
    private(set) var shares: [String: BoardProjectShare] = [:]
    private(set) var resolvedShareIDs: Set<String> = []

    /// Archived tasks of one project, paged separately from the board itself.
    private(set) var archivedTasks: [ArchivedBoardTask] = []
    private(set) var archivedProjectID: String?
    private(set) var archivedPage = 0
    private(set) var archivedTotalPages = 1
    private(set) var archivedTotalItems = 0
    private(set) var isLoadingArchived = false
    private(set) var hasLoadedArchived = false
    private(set) var archivedErrorMessage: String?
    private(set) var restoringTaskIDs: Set<String> = []

    private let defaults: UserDefaults
    private var loadSequence = 0
    private var archivedLoadSequence = 0
    private var cachedIdentity: String?
    private var selectionCacheKey: String?
    private var selectedProjectPage: Int?
    private var isListening = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func reset() {
        loadSequence += 1
        projects = []
        selectedProjectID = nil
        selectedStateID = nil
        page = 0
        totalPages = 1
        totalItems = 0
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        updatingTaskIDs = []
        isRealtimeConnected = false
        shares = [:]
        resolvedShareIDs = []
        resetArchived()
        cachedIdentity = nil
        selectionCacheKey = nil
        selectedProjectPage = nil
        isListening = false
    }

    func loadForPresentation(using auth: AuthStore) async {
        guard prepareCache(for: auth) else { return }
        guard !isLoading else { return }
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
                pageSize: Self.projectsPerPage,
                strategy: strategy
            )
            guard sequence == loadSequence else { return }
            projects = snapshot.projects
            page = max(0, snapshot.page - 1)
            totalPages = max(1, snapshot.totalPages)
            totalItems = snapshot.totalItems
            hasLoaded = true
            errorMessage = nil
            reconcileSelection(onLoadedPage: targetPage)
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

    func loadPage(_ page: Int, using auth: AuthStore) async {
        await refresh(using: auth, page: min(max(0, page), totalPages - 1))
    }

    func selectProject(_ project: BoardProject) {
        guard selectedProjectID != project.id else { return }
        selectedProjectID = project.id
        selectedStateID = nil
        persistSelection(page: page)
    }

    func selectState(_ stateID: String?) {
        guard selectedStateID != stateID else { return }
        selectedStateID = stateID
        persistSelection(page: page)
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
            await refresh(using: auth)
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
            await refresh(using: auth)
            return true
        } catch {
            projects[projectIndex].states[stateIndex].tasks[taskIndex].priority = previousPriority
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateDueDate(
        of task: BoardTask,
        to dueDate: Date?,
        using auth: AuthStore
    ) async -> Bool {
        guard BoardTask.isValidSpan(start: task.startDate, due: dueDate),
              task.dueDate != dueDate,
              !updatingTaskIDs.contains(task.id),
              let projectIndex = projects.firstIndex(where: { $0.id == task.projectID }),
              let stateIndex = projects[projectIndex].states.firstIndex(where: { $0.id == task.stateID }),
              let taskIndex = projects[projectIndex].states[stateIndex].tasks.firstIndex(where: { $0.id == task.id }) else {
            return false
        }

        let previousDueDate = projects[projectIndex].states[stateIndex].tasks[taskIndex].dueDate
        projects[projectIndex].states[stateIndex].tasks[taskIndex].dueDate = dueDate
        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }

        do {
            try await auth.updateBoardTaskDueDate(id: task.id, dueDate: dueDate)
            await refresh(using: auth)
            return true
        } catch {
            projects[projectIndex].states[stateIndex].tasks[taskIndex].dueDate = previousDueDate
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateStartDate(
        of task: BoardTask,
        to startDate: Date?,
        using auth: AuthStore
    ) async -> Bool {
        guard BoardTask.isValidSpan(start: startDate, due: task.dueDate),
              task.startDate != startDate,
              !updatingTaskIDs.contains(task.id),
              let projectIndex = projects.firstIndex(where: { $0.id == task.projectID }),
              let stateIndex = projects[projectIndex].states.firstIndex(where: { $0.id == task.stateID }),
              let taskIndex = projects[projectIndex].states[stateIndex].tasks.firstIndex(where: { $0.id == task.id }) else {
            return false
        }

        let previousStartDate = projects[projectIndex].states[stateIndex].tasks[taskIndex].startDate
        projects[projectIndex].states[stateIndex].tasks[taskIndex].startDate = startDate
        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }

        do {
            try await auth.updateBoardTaskStartDate(id: task.id, startDate: startDate)
            await refresh(using: auth)
            return true
        } catch {
            projects[projectIndex].states[stateIndex].tasks[taskIndex].startDate = previousStartDate
            errorMessage = error.localizedDescription
            return false
        }
    }

    func archiveTask(_ task: BoardTask, using auth: AuthStore) async -> Bool {
        guard !updatingTaskIDs.contains(task.id),
              let projectIndex = projects.firstIndex(where: { $0.id == task.projectID }),
              projects[projectIndex].states.last?.id == task.stateID,
              let stateIndex = projects[projectIndex].states.firstIndex(where: { $0.id == task.stateID }),
              let taskIndex = projects[projectIndex].states[stateIndex].tasks.firstIndex(where: { $0.id == task.id })
        else {
            return false
        }

        let previousProjects = projects
        projects[projectIndex].states[stateIndex].tasks.remove(at: taskIndex)
        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }

        do {
            try await auth.archiveBoardTask(id: task.id)
            await refresh(using: auth)
            return true
        } catch {
            projects = previousProjects
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Loads one page of a project's archived tasks. Switching projects starts
    /// the list over rather than paging into the previous project's results.
    func loadArchivedTasks(
        for projectID: String,
        page requestedPage: Int? = nil,
        using auth: AuthStore
    ) async {
        if archivedProjectID != projectID {
            resetArchived()
            archivedProjectID = projectID
        }
        let targetPage = max(0, requestedPage ?? archivedPage)
        archivedLoadSequence += 1
        let sequence = archivedLoadSequence
        isLoadingArchived = true
        defer {
            if sequence == archivedLoadSequence { isLoadingArchived = false }
        }

        do {
            let snapshot = try await auth.loadArchivedBoardTasks(
                projectID: projectID,
                page: targetPage + 1,
                pageSize: Self.archivedTasksPerPage
            )
            guard sequence == archivedLoadSequence, archivedProjectID == projectID else { return }
            archivedTasks = snapshot.tasks
            archivedPage = max(0, snapshot.page - 1)
            archivedTotalPages = max(1, snapshot.totalPages)
            archivedTotalItems = snapshot.totalItems
            hasLoadedArchived = true
            archivedErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == archivedLoadSequence else { return }
            hasLoadedArchived = true
            archivedErrorMessage = error.localizedDescription
        }
    }

    /// Restores an archived task to the state it was archived from, then
    /// reloads both the archived list and the board it reappears on.
    func restoreTask(_ task: ArchivedBoardTask, using auth: AuthStore) async -> Bool {
        guard !restoringTaskIDs.contains(task.id), let projectID = archivedProjectID else {
            return false
        }
        restoringTaskIDs.insert(task.id)
        defer { restoringTaskIDs.remove(task.id) }

        do {
            try await auth.restoreBoardTask(id: task.id)
            // Step back a page when the last remaining entry on it was restored.
            let nextPage = archivedTasks.count == 1 ? max(0, archivedPage - 1) : archivedPage
            await loadArchivedTasks(for: projectID, page: nextPage, using: auth)
            await refresh(using: auth)
            return true
        } catch {
            archivedErrorMessage = error.localizedDescription
            return false
        }
    }

    func resetArchived() {
        archivedLoadSequence += 1
        archivedTasks = []
        archivedProjectID = nil
        archivedPage = 0
        archivedTotalPages = 1
        archivedTotalItems = 0
        isLoadingArchived = false
        hasLoadedArchived = false
        archivedErrorMessage = nil
        restoringTaskIDs = []
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Project public links

    /// Only the owner may publish; the server enforces it and the button is
    /// shown only for owned projects, so a failure here is a real failure.
    func loadShare(projectID: String, using auth: AuthStore) async throws {
        applyShare(try await auth.loadBoardProjectShare(projectID: projectID), for: projectID)
    }

    func publishShare(
        projectID: String,
        expires: String,
        using auth: AuthStore
    ) async throws -> BoardProjectShare {
        let share = try await auth.publishBoardProject(projectID: projectID, expires: expires)
        applyShare(share, for: projectID)
        return share
    }

    func revokeShare(projectID: String, using auth: AuthStore) async throws {
        try await auth.unpublishBoardProject(projectID: projectID)
        applyShare(nil, for: projectID)
    }

    private func applyShare(_ share: BoardProjectShare?, for projectID: String) {
        shares[projectID] = share
        resolvedShareIDs.insert(projectID)
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
                let signals = try auth.boardRealtimeSignals()
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

    @discardableResult
    private func prepareCache(for auth: AuthStore) -> Bool {
        guard let userID = auth.user?.id else {
            if cachedIdentity != nil { reset() }
            return false
        }
        let identity = auth.serverAddress + ":" + userID
        guard cachedIdentity != identity else { return true }
        reset()
        cachedIdentity = identity
        selectionCacheKey = Self.selectionCachePrefix + identity
        restoreSelection()
        return true
    }

    private func restoreSelection() {
        guard let selectionCacheKey,
              let data = defaults.data(forKey: selectionCacheKey),
              let selection = try? JSONDecoder().decode(BoardSelection.self, from: data)
        else { return }
        selectedProjectID = selection.projectID
        selectedStateID = selection.stateID
        page = max(0, selection.page)
        selectedProjectPage = page
    }

    private func persistSelection(page: Int) {
        guard let selectionCacheKey, let selectedProjectID else { return }
        let normalizedPage = max(0, page)
        selectedProjectPage = normalizedPage
        let selection = BoardSelection(
            projectID: selectedProjectID,
            page: normalizedPage,
            stateID: selectedStateID
        )
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionCacheKey)
    }

    private func reconcileSelection(onLoadedPage loadedPage: Int) {
        guard let selectedProjectID,
              let selectionCacheKey,
              selectedProjectPage == loadedPage,
              !projects.contains(where: { $0.id == selectedProjectID })
        else { return }

        self.selectedProjectID = projects.first?.id
        self.selectedStateID = nil
        if self.selectedProjectID == nil {
            selectedProjectPage = nil
            defaults.removeObject(forKey: selectionCacheKey)
        } else {
            persistSelection(page: page)
        }
    }
}

private struct BoardSelection: Codable {
    let projectID: String
    let page: Int
    var stateID: String?
}
