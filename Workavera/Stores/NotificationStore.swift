import Foundation
import Observation

@MainActor
@Observable
final class NotificationStore {
    private(set) var items: [AppNotification] = []
    private(set) var unreadCount = 0
    private(set) var page = 0
    private(set) var totalPages = 1
    private(set) var totalItems = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var respondingShareIDs: Set<String> = []
    private(set) var managingNotificationIDs: Set<String> = []
    private(set) var isRealtimeConnected = false

    let pageSize = 20
    private var refreshSequence = 0

    func reset() {
        refreshSequence += 1
        items = []
        unreadCount = 0
        page = 0
        totalPages = 1
        totalItems = 0
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        respondingShareIDs = []
        managingNotificationIDs = []
        isRealtimeConnected = false
    }

    func refresh(using auth: AuthStore, page requestedPage: Int? = nil) async {
        let targetPage = max(0, requestedPage ?? page)
        refreshSequence += 1
        let sequence = refreshSequence
        isLoading = true
        defer {
            if sequence == refreshSequence {
                isLoading = false
            }
        }

        do {
            async let pageRequest = auth.loadNotifications(page: targetPage + 1, pageSize: pageSize)
            async let countRequest = auth.loadUnreadNotificationCount()
            let (loadedPage, loadedCount) = try await (pageRequest, countRequest)
            guard sequence == refreshSequence else { return }

            items = loadedPage.items
            page = max(0, loadedPage.page - 1)
            totalPages = max(1, loadedPage.totalPages)
            totalItems = loadedPage.totalItems
            unreadCount = loadedCount
            hasLoaded = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == refreshSequence else { return }
            hasLoaded = true
            errorMessage = error.localizedDescription
        }

    }

    func loadPage(_ page: Int, using auth: AuthStore) async {
        await refresh(using: auth, page: min(max(0, page), totalPages - 1))
    }

    func listenForRealtimeEvents(using auth: AuthStore) async {
        guard let userID = auth.user?.id else { return }
        var retryDelay: UInt64 = 1

        while !Task.isCancelled, auth.user?.id == userID {
            do {
                let events = try auth.notificationRealtimeEvents()
                isRealtimeConnected = true
                for try await event in events {
                    try Task.checkCancellation()
                    guard auth.user?.id == userID else { return }
                    applyRealtimeEvent(event)
                    await refresh(using: auth)
                    retryDelay = 1
                }
                isRealtimeConnected = false
            } catch is CancellationError {
                isRealtimeConnected = false
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
        isRealtimeConnected = false
    }

    func markRead(_ notification: AppNotification, using auth: AuthStore) async {
        guard !notification.isRead else { return }
        let previousItems = items
        let previousCount = unreadCount
        updateReadState(id: notification.id, readAt: .now)
        unreadCount = max(0, unreadCount - 1)

        do {
            try await auth.markNotificationRead(id: notification.id)
            errorMessage = nil
        } catch {
            items = previousItems
            unreadCount = previousCount
            errorMessage = error.localizedDescription
        }
    }

    func markAllRead(using auth: AuthStore) async {
        guard unreadCount > 0 else { return }
        let previousItems = items
        let previousCount = unreadCount
        let readAt = Date.now
        for index in items.indices where !items[index].isRead {
            items[index].readAt = readAt
        }
        unreadCount = 0

        do {
            try await auth.markAllNotificationsRead()
            errorMessage = nil
        } catch {
            items = previousItems
            unreadCount = previousCount
            errorMessage = error.localizedDescription
        }
    }

    func respondToModelShare(
        _ notification: AppNotification,
        decision: ModelShareDecision,
        using auth: AuthStore
    ) async {
        guard notification.type == .modelShare,
              notification.data.shareStatus ?? .pending == .pending,
              !respondingShareIDs.contains(notification.id) else { return }

        respondingShareIDs.insert(notification.id)
        defer { respondingShareIDs.remove(notification.id) }

        do {
            let status = try await auth.respondToModelShare(
                notificationID: notification.id,
                decision: decision
            )
            if let index = items.firstIndex(where: { $0.id == notification.id }) {
                if !items[index].isRead {
                    unreadCount = max(0, unreadCount - 1)
                }
                items[index].readAt = .now
                items[index].data.shareStatus = status
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isRespondingToShare(id: String) -> Bool {
        respondingShareIDs.contains(id)
    }

    func archive(_ notification: AppNotification, using auth: AuthStore) async {
        guard !managingNotificationIDs.contains(notification.id),
              !respondingShareIDs.contains(notification.id) else { return }
        managingNotificationIDs.insert(notification.id)
        defer { managingNotificationIDs.remove(notification.id) }

        do {
            _ = try await auth.archiveNotification(id: notification.id)
            let targetPage = items.count == 1 ? max(0, page - 1) : page
            removeFromActiveList(notification)
            await refresh(using: auth, page: targetPage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notification: AppNotification, using auth: AuthStore) async {
        guard !managingNotificationIDs.contains(notification.id),
              !respondingShareIDs.contains(notification.id) else { return }
        managingNotificationIDs.insert(notification.id)
        defer { managingNotificationIDs.remove(notification.id) }

        do {
            try await auth.deleteNotification(id: notification.id)
            let targetPage = items.count == 1 ? max(0, page - 1) : page
            removeFromActiveList(notification)
            await refresh(using: auth, page: targetPage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isManaging(id: String) -> Bool {
        managingNotificationIDs.contains(id) || respondingShareIDs.contains(id)
    }

    func clearError() {
        errorMessage = nil
    }

    private func updateReadState(id: String, readAt: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].readAt = readAt
    }

    private func removeFromActiveList(_ notification: AppNotification) {
        items.removeAll { $0.id == notification.id }
        totalItems = max(0, totalItems - 1)
        if !notification.isRead {
            unreadCount = max(0, unreadCount - 1)
        }
    }

    private func applyRealtimeEvent(_ event: NotificationRealtimeEvent) {
        let previous = items.first { $0.id == event.record.id }

        switch event.action {
        case .create:
            guard event.record.status == .active, previous == nil else { return }
            totalItems += 1
            if !event.record.isRead { unreadCount += 1 }
            if page == 0 {
                items.append(event.record)
                sortAndTrimCurrentPage()
            }

        case .update:
            if let index = items.firstIndex(where: { $0.id == event.record.id }) {
                let wasUnread = !items[index].isRead
                if event.record.status == .active {
                    items[index] = event.record
                    if wasUnread != !event.record.isRead {
                        unreadCount += event.record.isRead ? -1 : 1
                        unreadCount = max(0, unreadCount)
                    }
                    sortAndTrimCurrentPage()
                } else {
                    let removed = items.remove(at: index)
                    totalItems = max(0, totalItems - 1)
                    if !removed.isRead { unreadCount = max(0, unreadCount - 1) }
                }
            }

        case .delete:
            guard let previous else { return }
            items.removeAll { $0.id == previous.id }
            totalItems = max(0, totalItems - 1)
            if !previous.isRead { unreadCount = max(0, unreadCount - 1) }

        case .unknown:
            break
        }
    }

    private func sortAndTrimCurrentPage() {
        items.sort {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.createdAt > $1.createdAt
        }
        if items.count > pageSize {
            items.removeLast(items.count - pageSize)
        }
    }
}
