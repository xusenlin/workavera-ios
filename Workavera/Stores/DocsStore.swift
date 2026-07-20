import Foundation
import Observation

@MainActor
@Observable
final class DocsStore {
    static let pageSize = 15

    var query = ""
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

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        query = ""
        view = .myDocuments
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
        cachedUserID = nil
    }

    func loadIfNeeded(using auth: AuthStore) async {
        guard prepareCache(for: auth), !hasLoaded, !isLoading else { return }
        await refresh(using: auth)
    }

    func refresh(using auth: AuthStore, page requestedPage: Int? = nil) async {
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
                query: query
            )
            guard sequence == loadSequence else { return }
            documents = snapshot.documents
            folders = snapshot.folders
            projects = snapshot.projects
            page = max(0, snapshot.page - 1)
            totalPages = max(1, snapshot.totalPages)
            totalItems = snapshot.totalItems
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
            hasLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    func selectView(_ newView: DocsViewFilter, using auth: AuthStore) async {
        guard view != newView else { return }
        view = newView
        page = 0
        documents = []
        await refresh(using: auth, page: 0)
    }

    func reloadSearch(using auth: AuthStore) async {
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
        guard force || documentCache[id] == nil else { return }
        guard !loadingDocumentIDs.contains(id) else { return }
        loadingDocumentIDs.insert(id)
        defer { loadingDocumentIDs.remove(id) }

        do {
            let pinned = documents.first(where: { $0.id == id })?.pinned
                ?? documentCache[id]?.pinned
                ?? false
            documentCache[id] = try await auth.loadDocument(id: id, pinned: pinned)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
        return true
    }
}
