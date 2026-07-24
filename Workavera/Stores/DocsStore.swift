import Foundation
import Observation

@MainActor
@Observable
final class DocsStore {
    static let pageSize = 15
    private static let selectionCachePrefix = "workavera.docs.selection:"

    private(set) var query = ""
    private(set) var view: DocsViewFilter = .myDocuments
    private(set) var documents: [DocumentSummary] = []
    private(set) var folders: [DocumentFolder] = []
    private(set) var projects: [DocumentProject] = []
    private(set) var page = 0
    private(set) var totalPages = 1
    private(set) var totalItems = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var documentCache: [String: WorkspaceDocument] = [:]
    private(set) var loadingDocumentIDs: Set<String> = []
    private(set) var pinningDocumentIDs: Set<String> = []
    private(set) var mutatingDocumentIDs: Set<String> = []

    private let defaults: UserDefaults
    private var cachedUserID: String?
    private var loadSequence = 0
    private var selectionCacheKey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func reset() {
        loadSequence += 1
        query = ""
        view = .myDocuments
        selectionCacheKey = nil
        documents = []
        folders = []
        projects = []
        page = 0
        totalPages = 1
        totalItems = 0
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        documentCache = [:]
        loadingDocumentIDs = []
        pinningDocumentIDs = []
        mutatingDocumentIDs = []
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
        reportError: Bool = true,
        reconcile: Bool = true
    ) async {
        guard prepareCache(for: auth) else { return }
        let targetPage = view.usesPagination ? max(0, requestedPage ?? page) : 0
        loadSequence += 1
        let sequence = loadSequence
        isLoading = true
        defer {
            if sequence == loadSequence { isLoading = false }
        }

        do {
            let snapshot = try await auth.loadDocsPage(
                view: view,
                page: targetPage + 1,
                pageSize: Self.pageSize,
                query: query,
                strategy: strategy
            )
            guard sequence == loadSequence else { return }
            documents = snapshot.documents
            folders = snapshot.folders
            projects = snapshot.projects
            page = max(0, snapshot.page - 1)
            totalPages = max(1, snapshot.totalPages)
            totalItems = snapshot.totalItems

            // A persisted folder/project selection may point at something that
            // was deleted; fall back to My Documents and reload once.
            if reconcile, !isCurrentViewAvailable {
                view = .myDocuments
                page = 0
                persistSelection()
                await refresh(
                    using: auth,
                    page: 0,
                    strategy: strategy,
                    reportError: reportError,
                    reconcile: false
                )
                return
            }

            hasLoaded = true
            errorMessage = nil

            for summary in documents {
                if var cached = documentCache[summary.id] {
                    cached.pinned = summary.pinned
                    documentCache[summary.id] = cached
                }
            }
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

    func selectView(_ newView: DocsViewFilter, using auth: AuthStore) async {
        guard view != newView else { return }
        let previousView = view
        let previousPage = page
        view = newView
        page = 0
        await refresh(using: auth, page: 0)
        if errorMessage != nil {
            view = previousView
            page = previousPage
        } else {
            persistSelection()
        }
    }

    func search(_ newQuery: String, using auth: AuthStore) async {
        let normalized = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != normalized else { return }
        query = normalized
        page = 0
        await refresh(using: auth, page: 0)
    }

    func loadPage(_ newPage: Int, using auth: AuthStore) async {
        guard view.usesPagination else { return }
        await refresh(
            using: auth,
            page: min(max(0, newPage), totalPages - 1)
        )
    }

    func loadDocument(id: String, using auth: AuthStore, force: Bool = false) async {
        guard !loadingDocumentIDs.contains(id) else { return }
        loadingDocumentIDs.insert(id)
        defer { loadingDocumentIDs.remove(id) }

        if !force, documentCache[id] == nil {
            await fetchDocument(
                id: id,
                using: auth,
                strategy: .cacheOnly,
                reportError: false
            )
        }
        guard !Task.isCancelled else { return }
        await fetchDocument(id: id, using: auth, strategy: .networkOnly, reportError: true)
    }

    func togglePin(id: String, using auth: AuthStore) async {
        guard !pinningDocumentIDs.contains(id) else { return }
        let currentPinned = documents.first(where: { $0.id == id })?.pinned
            ?? documentCache[id]?.pinned
            ?? false
        let previousDocuments = documents
        let previousCache = documentCache
        setPinned(id: id, pinned: !currentPinned)
        pinningDocumentIDs.insert(id)
        defer { pinningDocumentIDs.remove(id) }

        do {
            try await auth.setDocumentPinned(id: id, pinned: !currentPinned)
            await refresh(using: auth)
        } catch {
            documents = previousDocuments
            documentCache = previousCache
            errorMessage = error.localizedDescription
        }
    }

    func setArchived(id: String, archived: Bool, using auth: AuthStore) async {
        guard !mutatingDocumentIDs.contains(id) else { return }
        mutatingDocumentIDs.insert(id)
        defer { mutatingDocumentIDs.remove(id) }

        do {
            try await auth.setDocumentArchived(id: id, archived: archived)
            documentCache.removeValue(forKey: id)
            await refresh(using: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func delete(id: String, using auth: AuthStore) async -> Bool {
        guard !mutatingDocumentIDs.contains(id) else { return false }
        mutatingDocumentIDs.insert(id)
        defer { mutatingDocumentIDs.remove(id) }

        do {
            try await auth.deleteDocument(id: id)
            documentCache.removeValue(forKey: id)
            await refresh(using: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func locationName(for document: DocumentSummary) -> String {
        if let projectID = document.projectID {
            return projects.first(where: { $0.id == projectID })?.name ?? "Project"
        }
        if let folderID = document.folderID {
            return folders.first(where: { $0.id == folderID })?.name ?? "Folder"
        }
        return "My documents"
    }

    func locationName(for document: WorkspaceDocument) -> String {
        if let projectID = document.projectID {
            return projects.first(where: { $0.id == projectID })?.name ?? "Project"
        }
        if let folderID = document.folderID {
            return folders.first(where: { $0.id == folderID })?.name ?? "Folder"
        }
        return "My documents"
    }

    func label(for filter: DocsViewFilter? = nil) -> String {
        switch filter ?? view {
        case .recent: "Recent"
        case .pinned: "Pinned"
        case .myDocuments: "My documents"
        case .folder(let id): folders.first(where: { $0.id == id })?.name ?? "Folder"
        case .project(let id): projects.first(where: { $0.id == id })?.name ?? "Project"
        case .archived: "Archived"
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func fetchDocument(
        id: String,
        using auth: AuthStore,
        strategy: DataLoadStrategy,
        reportError: Bool
    ) async {
        do {
            let pinned = documents.first(where: { $0.id == id })?.pinned
                ?? documentCache[id]?.pinned
                ?? false
            documentCache[id] = try await auth.loadDocument(
                id: id,
                pinned: pinned,
                strategy: strategy
            )
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if reportError {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setPinned(id: String, pinned: Bool) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].pinned = pinned
            if view == .pinned, !pinned {
                documents.remove(at: index)
                totalItems = max(0, totalItems - 1)
            }
        }
        if var cached = documentCache[id] {
            cached.pinned = pinned
            documentCache[id] = cached
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
        selectionCacheKey = Self.selectionCachePrefix + userID
        restoreSelection()
        return true
    }

    private func restoreSelection() {
        guard let selectionCacheKey,
              let data = defaults.data(forKey: selectionCacheKey),
              let saved = try? JSONDecoder().decode(DocsViewFilter.self, from: data)
        else { return }
        view = saved
    }

    private func persistSelection() {
        guard let selectionCacheKey,
              let data = try? JSONEncoder().encode(view) else { return }
        defaults.set(data, forKey: selectionCacheKey)
    }

    /// A restored folder/project selection may point at something that was
    /// since deleted; everything else is always valid.
    private var isCurrentViewAvailable: Bool {
        switch view {
        case .folder(let id): folders.contains { $0.id == id }
        case .project(let id): projects.contains { $0.id == id }
        default: true
        }
    }
}
