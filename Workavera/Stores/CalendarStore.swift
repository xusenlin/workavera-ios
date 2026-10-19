import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class CalendarStore {
    private(set) var events: [AppEvent] = []
    private(set) var tasks: [CalendarTaskDeadline] = []
    private(set) var timezone = TimeZone.current.identifier
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isRealtimeConnected = false
    private(set) var errorMessage: String?
    private(set) var mutatingEventIDs: Set<String> = []

    private var cachedUserID: String?
    private var loadSequence = 0
    private var isListening = false

    func reset() {
        loadSequence += 1
        events = []
        tasks = []
        timezone = TimeZone.current.identifier
        isLoading = false
        hasLoaded = false
        isRealtimeConnected = false
        errorMessage = nil
        mutatingEventIDs = []
        cachedUserID = nil
        isListening = false
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
            let snapshot = try await auth.loadCalendarSnapshot(strategy: strategy)
            guard sequence == loadSequence else { return }
            events = snapshot.events.sorted { $0.startAt < $1.startAt }
            tasks = snapshot.tasks.sorted { $0.dueDate < $1.dueDate }
            timezone = snapshot.timezone
            hasLoaded = true
            errorMessage = nil
            if strategy == .networkOnly { publishWidgetSnapshot() }
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

    func create(_ input: CalendarEventInput, using auth: AuthStore) async throws -> AppEvent {
        do {
            let event = try await auth.createCalendarEvent(input: input)
            apply(event)
            await refresh(using: auth)
            return event
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func update(
        _ event: AppEvent,
        input: CalendarEventInput,
        using auth: AuthStore
    ) async throws -> AppEvent {
        guard !mutatingEventIDs.contains(event.id) else { return event }
        mutatingEventIDs.insert(event.id)
        defer { mutatingEventIDs.remove(event.id) }
        do {
            let updated = try await auth.updateCalendarEvent(id: event.id, input: input)
            apply(updated)
            await refresh(using: auth)
            return updated
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ event: AppEvent, using auth: AuthStore) async -> Bool {
        guard !mutatingEventIDs.contains(event.id) else { return false }
        mutatingEventIDs.insert(event.id)
        defer { mutatingEventIDs.remove(event.id) }
        do {
            try await auth.deleteCalendarEvent(id: event.id)
            events.removeAll { $0.id == event.id }
            await refresh(using: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
                let signals = try auth.calendarRealtimeSignals()
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

    func clearError() {
        errorMessage = nil
    }

    private func apply(_ event: AppEvent) {
        var event = event
        event.timezone = timezone
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        events.sort { $0.startAt < $1.startAt }
    }

    /// Hands fresh agenda data to the widget, reloading it only when something changed.
    private func publishWidgetSnapshot() {
        let snapshot = AgendaWidgetSnapshot(events: events, tasks: tasks, timezone: timezone)
        let changed = !snapshot.hasSameItems(as: AgendaWidgetStore.loadSnapshot())
        AgendaWidgetStore.saveSnapshot(snapshot)
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: AgendaWidgetStore.widgetKind)
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
