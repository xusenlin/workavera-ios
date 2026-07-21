import Foundation
import Observation

@MainActor
@Observable
final class ContactsStore {
    private(set) var contacts: [Contact] = []
    private(set) var favoriteRecordIDs: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var mutatingContactIDs: Set<String> = []

    private var cachedUserID: String?
    private var loadSequence = 0

    func reset() {
        loadSequence += 1
        contacts = []
        favoriteRecordIDs = [:]
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        mutatingContactIDs = []
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
            let snapshot = try await auth.loadContacts(strategy: strategy)
            guard sequence == loadSequence else { return }
            contacts = snapshot.contacts
            favoriteRecordIDs = snapshot.favoriteRecordIDs
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

    func toggleFavorite(contactID: String, using auth: AuthStore) async {
        guard contactID != auth.user?.id else { return }
        guard !mutatingContactIDs.contains(contactID) else { return }
        guard let index = contacts.firstIndex(where: { $0.id == contactID }) else { return }

        let wasFavorite = contacts[index].isFavorite
        let previousRecordID = favoriteRecordIDs[contactID]
        contacts[index].isFavorite.toggle()
        mutatingContactIDs.insert(contactID)
        defer { mutatingContactIDs.remove(contactID) }

        do {
            if let previousRecordID {
                try await auth.deleteContactFavorite(id: previousRecordID)
                favoriteRecordIDs.removeValue(forKey: contactID)
            } else {
                let record = try await auth.createContactFavorite(contactID: contactID)
                favoriteRecordIDs[contactID] = record.id
            }
            await refresh(using: auth)
        } catch {
            if let currentIndex = contacts.firstIndex(where: { $0.id == contactID }) {
                contacts[currentIndex].isFavorite = wasFavorite
            }
            if let previousRecordID {
                favoriteRecordIDs[contactID] = previousRecordID
            } else {
                favoriteRecordIDs.removeValue(forKey: contactID)
            }
            errorMessage = error.localizedDescription
        }
    }

    func contact(id: String) -> Contact? {
        contacts.first { $0.id == id }
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
