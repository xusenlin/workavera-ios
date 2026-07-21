import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    enum Phase: Equatable {
        case restoring
        case recoveryFailed
        case loggedOut
        case loggedIn
    }

    private(set) var phase: Phase = .restoring
    private(set) var user: User?
    private(set) var token: String?
    private(set) var preferences: UserPreferences?
    private(set) var recoveryMessage: String?
    private(set) var preferencesMessage: String?

    var serverAddress: String {
        didSet { defaults.set(serverAddress, forKey: Self.serverKey) }
    }

    var allowInsecureHTTP: Bool {
        didSet { defaults.set(allowInsecureHTTP, forKey: Self.insecureHTTPKey) }
    }

    private(set) var lastLoginEmail: String {
        didSet { defaults.set(lastLoginEmail, forKey: Self.lastEmailKey) }
    }

    private(set) var fallbackAppearance: AppAppearance {
        didSet { defaults.set(fallbackAppearance.rawValue, forKey: AppAppearance.storageKey) }
    }

    private let defaults: UserDefaults
    private let tokenStore: any TokenStoring
    private let session: URLSession
    private let responseCache: APIResponseCache
    private var latestStatusRequestID: UUID?
    private var latestPreferencesRequestID: UUID?

    private static let serverKey = "workavera.serverAddress"
    private static let insecureHTTPKey = "workavera.allowInsecureHTTP"
    private static let lastEmailKey = "workavera.lastLoginEmail"
    private static let legacyTokenAccount = "workavera.authToken"
    private static let tokenAccountPrefix = "workavera.authToken.server:"
    private static let preferencesCachePrefix = "workavera.preferences.cache:"

    init(
        defaults: UserDefaults = .standard,
        tokenStore: any TokenStoring = KeychainTokenStore(),
        session: URLSession = .shared,
        responseCache: APIResponseCache = .shared
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.session = session
        self.responseCache = responseCache
        serverAddress = defaults.string(forKey: Self.serverKey) ?? "http://127.0.0.1:8090"
        allowInsecureHTTP = defaults.bool(forKey: Self.insecureHTTPKey)
        lastLoginEmail = defaults.string(forKey: Self.lastEmailKey) ?? ""
        let appearance = defaults.string(forKey: AppAppearance.storageKey) ?? AppAppearance.system.rawValue
        fallbackAppearance = AppAppearance(rawValue: appearance) ?? .system
    }

    var appearance: AppAppearance {
        preferences?.theme ?? fallbackAppearance
    }

    var memoryEnabled: Bool {
        preferences?.memoryEnabled ?? false
    }

    var memoryAutoCapture: Bool {
        preferences?.memoryAutoCapture ?? false
    }

    var avatarURL: URL? {
        guard let user, let client = try? makeClient() else { return nil }
        return client.fileURL(
            collectionId: user.collectionId,
            recordId: user.id,
            fileName: user.avatar
        )
    }

    func updateServerSettings(address: String, allowInsecureHTTP: Bool) throws {
        let configuration = try ServerConfiguration(
            address: address,
            allowInsecureHTTP: allowInsecureHTTP
        )
        serverAddress = configuration.normalizedAddress
        self.allowInsecureHTTP = allowInsecureHTTP
    }

    func restoreSession() async {
        phase = .restoring
        recoveryMessage = nil

        let account = tokenAccount
        let savedToken: String
        do {
            if let scopedToken = try tokenStore.read(account: account) {
                savedToken = scopedToken
            } else if let legacyToken = try tokenStore.read(account: Self.legacyTokenAccount) {
                try tokenStore.save(legacyToken, account: account)
                try tokenStore.delete(account: Self.legacyTokenAccount)
                savedToken = legacyToken
            } else {
                phase = .loggedOut
                return
            }
        } catch {
            failRecovery(error)
            return
        }

        do {
            let auth = try await makeClient().authRefresh(token: savedToken)
            try apply(auth)
            if preferences == nil { await loadPreferences() }
        } catch let error as APIError where error.isAuthenticationFailure {
            try? tokenStore.delete(account: account)
            clearSession()
            phase = .loggedOut
        } catch {
            failRecovery(error)
        }
    }

    func login(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = try await makeClient().authWithPassword(
            identity: normalizedEmail,
            password: password
        )
        try apply(auth)
        lastLoginEmail = normalizedEmail
        if preferences == nil { await loadPreferences() }
    }

    func logout() {
        try? tokenStore.delete(account: tokenAccount)
        try? tokenStore.delete(account: Self.legacyTokenAccount)
        clearSession()
        phase = .loggedOut
    }

    func updateStatus(_ status: UserStatus) async throws {
        guard let user, let token else { return }
        let requestID = UUID()
        latestStatusRequestID = requestID
        let updated = try await makeClient().updateStatus(
            id: user.id,
            status: status,
            token: token
        )
        guard latestStatusRequestID == requestID else { return }
        self.user = updated
    }

    func updateProfile(_ profile: ProfileUpdate, avatar: AvatarUpload?) async throws {
        guard let user, let token else { return }
        self.user = try await makeClient().updateProfile(
            id: user.id,
            profile: profile,
            avatar: avatar,
            token: token
        )
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user, let token else { return }
        _ = try await makeClient().changePassword(
            id: user.id,
            currentPassword: currentPassword,
            newPassword: newPassword,
            token: token
        )

        do {
            let auth = try await makeClient().authWithPassword(
                identity: user.email,
                password: newPassword
            )
            try apply(auth)
        } catch {
            logout()
            throw APIError.http(
                statusCode: 401,
                message: "Your password was updated. Sign in again with your new password.",
                fieldMessages: [:]
            )
        }
    }

    func updateAppearance(_ appearance: AppAppearance) async throws {
        guard let preferences, let token else {
            fallbackAppearance = appearance
            throw APIError.http(
                statusCode: 409,
                message: "Preferences are not available yet. Try again after reconnecting.",
                fieldMessages: [:]
            )
        }
        fallbackAppearance = appearance
        self.preferences = try await makeClient().updatePreferences(
            id: preferences.id,
            theme: appearance,
            token: token
        )
        cachePreferences()
        preferencesMessage = nil
    }

    func updateMemoryEnabled(_ enabled: Bool) async throws {
        guard let preferences, let token else { return }
        self.preferences = try await makeClient().updatePreferences(
            id: preferences.id,
            memoryEnabled: enabled,
            token: token
        )
        cachePreferences()
        preferencesMessage = nil
    }

    func updateMemoryAutoCapture(_ enabled: Bool) async throws {
        guard let preferences, let token else { return }
        self.preferences = try await makeClient().updatePreferences(
            id: preferences.id,
            memoryAutoCapture: enabled,
            token: token
        )
        cachePreferences()
        preferencesMessage = nil
    }

    func reloadPreferences() async {
        await loadPreferences()
    }

    func loadContacts(strategy: DataLoadStrategy = .networkOnly) async throws -> ContactsSnapshot {
        guard let user, let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getContacts(ownerID: user.id, token: token)
        }
    }

    func createContactFavorite(contactID: String) async throws -> ContactFavoriteRecord {
        guard let user, let token else { throw sessionUnavailableError }
        return try await makeClient().createContactFavorite(
            ownerID: user.id,
            contactID: contactID,
            token: token
        )
    }

    func deleteContactFavorite(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().deleteContactFavorite(id: id, token: token)
    }

    func loadReadingPage(
        filter: ReadingListFilter,
        page: Int,
        pageSize: Int,
        query: String,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> ReadingPage {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getReadingPage(
                filter: filter,
                page: page,
                pageSize: pageSize,
                query: query,
                token: token
            )
        }
    }

    func createReadingItem(input: ReadingItemInput) async throws -> ReadingItem {
        guard let user, let token else { throw sessionUnavailableError }
        return try await makeClient().createReadingItem(
            ownerID: user.id,
            input: input,
            token: token
        )
    }

    func updateReadingStatus(id: String, status: ReadingStatus) async throws -> ReadingItem {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().updateReadingStatus(id: id, status: status, token: token)
    }

    func setReadingPinned(id: String, pinned: Bool) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().setReadingPinned(id: id, pinned: pinned, token: token)
    }

    func deleteReadingItem(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().deleteReadingItem(id: id, token: token)
    }

    func summarizeReadingItem(id: String) async throws -> ReadingSummaryResponse {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().summarizeReadingItem(id: id, token: token)
    }

    func markAllReadingItemsRead() async throws -> Int {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().markAllReadingItemsRead(token: token)
    }

    func loadNotifications(
        page: Int,
        pageSize: Int,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> NotificationPage {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getNotifications(page: page, pageSize: pageSize, token: token)
        }
    }

    func loadUnreadNotificationCount(strategy: DataLoadStrategy = .networkOnly) async throws -> Int {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getUnreadNotificationCount(token: token)
        }
    }

    func markNotificationRead(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().markNotificationRead(id: id, token: token)
    }

    func markAllNotificationsRead() async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().markAllNotificationsRead(token: token)
    }

    func respondToModelShare(
        notificationID: String,
        decision: ModelShareDecision
    ) async throws -> ModelShareStatus {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().respondToModelShare(
            notificationID: notificationID,
            decision: decision,
            token: token
        )
    }

    func archiveNotification(id: String) async throws -> AppNotification {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().archiveNotification(id: id, token: token)
    }

    func deleteNotification(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().deleteNotification(id: id, token: token)
    }

    func notificationRealtimeEvents() throws -> AsyncThrowingStream<NotificationRealtimeEvent, Error> {
        guard let token else { throw sessionUnavailableError }
        return try makeClient().notificationRealtimeEvents(token: token)
    }

    func loadDashboardSummary(strategy: DataLoadStrategy = .networkOnly) async throws -> DashboardSummary {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getDashboardSummary(token: token)
        }
    }

    func loadDocsPage(
        view: DocsViewFilter,
        page: Int,
        pageSize: Int,
        query: String,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> DocsPage {
        guard let user, let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getDocsPage(
                userID: user.id,
                view: view,
                page: page,
                pageSize: pageSize,
                query: query,
                token: token
            )
        }
    }

    func loadDocument(
        id: String,
        pinned: Bool,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> WorkspaceDocument {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getDocument(id: id, pinned: pinned, token: token)
        }
    }

    func loadDocumentVersions(
        id: String,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> [DocumentVersion] {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getDocumentVersions(id: id, token: token)
        }
    }

    func loadDocumentVersion(
        id: String,
        revision: Int,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> DocumentVersion {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getDocumentVersion(id: id, revision: revision, token: token)
        }
    }

    func setDocumentPinned(id: String, pinned: Bool) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().setDocumentPinned(id: id, pinned: pinned, token: token)
    }

    func loadAPIKeys(strategy: DataLoadStrategy = .networkOnly) async throws -> [WorkaveraAPIKey] {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getAPIKeys(token: token)
        }
    }

    func createAPIKey(
        name: String,
        expiration: APIKeyExpiration,
        allowsDestructiveActions: Bool
    ) async throws -> CreatedWorkaveraAPIKey {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().createAPIKey(
            name: name,
            expiration: expiration,
            allowsDestructiveActions: allowsDestructiveActions,
            token: token
        )
    }

    func revokeAPIKey(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().revokeAPIKey(id: id, token: token)
    }

    func loadLLMModels(strategy: DataLoadStrategy = .networkOnly) async throws -> [LLMModelConfiguration] {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getLLMModels(token: token)
        }
    }

    func createLLMModel(input: LLMModelInput) async throws -> LLMModelConfiguration {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().createLLMModel(input: input, token: token)
    }

    func updateLLMModel(id: String, input: LLMModelInput) async throws -> LLMModelConfiguration {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().updateLLMModel(id: id, input: input, token: token)
    }

    func deleteLLMModel(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().deleteLLMModel(id: id, token: token)
    }

    func setDefaultLLMModel(id: String) async throws -> LLMModelConfiguration {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().setDefaultLLMModel(id: id, token: token)
    }

    func loadLLMShareTargets(strategy: DataLoadStrategy = .networkOnly) async throws -> [LLMShareTarget] {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getLLMShareTargets(token: token)
        }
    }

    func shareLLMModel(id: String, userIDs: [String]) async throws -> Int {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().shareLLMModel(id: id, userIDs: userIDs, token: token)
    }

    func loadSavedMemories(strategy: DataLoadStrategy = .networkOnly) async throws -> [SavedChatMemory] {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getSavedMemories(token: token)
        }
    }

    func createSavedMemory(
        category: MemoryCategory,
        content: String
    ) async throws -> SavedChatMemory {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().createSavedMemory(
            category: category,
            content: content,
            token: token
        )
    }

    func updateSavedMemory(
        id: String,
        category: MemoryCategory,
        content: String
    ) async throws -> SavedChatMemory {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().updateSavedMemory(
            id: id,
            category: category,
            content: content,
            token: token
        )
    }

    func setSavedMemoryActive(id: String, active: Bool) async throws -> SavedChatMemory {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().setSavedMemoryActive(
            id: id,
            active: active,
            token: token
        )
    }

    func deleteSavedMemory(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().deleteSavedMemory(id: id, token: token)
    }

    func loadCalendarSnapshot(strategy: DataLoadStrategy = .networkOnly) async throws -> CalendarSnapshot {
        guard let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getCalendarSnapshot(token: token)
        }
    }

    func createCalendarEvent(input: CalendarEventInput) async throws -> AppEvent {
        guard let user, let token else { throw sessionUnavailableError }
        return try await makeClient().createCalendarEvent(
            ownerID: user.id,
            input: input,
            token: token
        )
    }

    func updateCalendarEvent(id: String, input: CalendarEventInput) async throws -> AppEvent {
        guard let token else { throw sessionUnavailableError }
        return try await makeClient().updateCalendarEvent(id: id, input: input, token: token)
    }

    func deleteCalendarEvent(id: String) async throws {
        guard let token else { throw sessionUnavailableError }
        try await makeClient().deleteCalendarEvent(id: id, token: token)
    }

    func calendarRealtimeSignals() throws -> AsyncThrowingStream<CalendarRealtimeSignal, Error> {
        guard let token else { throw sessionUnavailableError }
        return try makeClient().calendarRealtimeSignals(token: token)
    }

    func boardRealtimeSignals() throws -> AsyncThrowingStream<CalendarRealtimeSignal, Error> {
        guard let token else { throw sessionUnavailableError }
        return try makeClient().boardRealtimeSignals(token: token)
    }

    func dashboardRealtimeSignals() throws -> AsyncThrowingStream<CalendarRealtimeSignal, Error> {
        guard let token else { throw sessionUnavailableError }
        return try makeClient().dashboardRealtimeSignals(token: token)
    }

    func loadBoardPage(
        page: Int,
        pageSize: Int,
        strategy: DataLoadStrategy = .networkOnly
    ) async throws -> BoardPage {
        guard let user, let token else { throw sessionUnavailableError }
        return try await load(strategy: strategy) { client in
            try await client.getBoardPage(
                userID: user.id,
                page: page,
                pageSize: pageSize,
                token: token
            )
        }
    }

    func moveBoardTask(id: String, stateID: String, rank: Double) async throws {
        guard let token else { throw sessionUnavailableError }
        _ = try await makeClient().moveBoardTask(
            id: id,
            stateID: stateID,
            rank: rank,
            token: token
        )
    }

    func updateBoardTaskPriority(id: String, priority: TaskPriority) async throws {
        guard let token else { throw sessionUnavailableError }
        _ = try await makeClient().updateBoardTaskPriority(
            id: id,
            priority: priority,
            token: token
        )
    }

    func updateBoardTaskDueDate(id: String, dueDate: Date?) async throws {
        guard let token else { throw sessionUnavailableError }
        _ = try await makeClient().updateBoardTaskDueDate(
            id: id,
            dueDate: dueDate,
            token: token
        )
    }

    private func load<Value>(
        strategy: DataLoadStrategy,
        operation: (PocketBaseClient) async throws -> Value
    ) async throws -> Value {
        switch strategy {
        case .cacheOnly:
            return try await operation(makeClient(loadStrategy: .cacheOnly))
        case .networkOnly:
            return try await loadFromNetwork(operation: operation)
        }
    }

    private func loadFromNetwork<Value>(
        operation: (PocketBaseClient) async throws -> Value
    ) async throws -> Value {
        do {
            try Task.checkCancellation()
            return try await operation(makeClient())
        } catch is CancellationError {
            // Navigation transitions can cancel the first URLSession request even
            // while the replacement page task remains alive. Retry once only when
            // the parent task itself is still active.
            try Task.checkCancellation()
            return try await operation(makeClient())
        }
    }

    private func makeClient(loadStrategy: DataLoadStrategy = .networkOnly) throws -> PocketBaseClient {
        try PocketBaseClient(
            baseURLString: serverAddress,
            allowInsecureHTTP: allowInsecureHTTP,
            session: session,
            responseCache: responseCache,
            cacheNamespace: user.map { serverAddress + "|" + $0.id },
            loadStrategy: loadStrategy
        )
    }

    private var sessionUnavailableError: APIError {
        APIError.http(
            statusCode: 401,
            message: "Your session is no longer available. Sign in again.",
            fieldMessages: [:]
        )
    }

    private var tokenAccount: String {
        let identity = (try? ServerConfiguration(
            address: serverAddress,
            allowInsecureHTTP: true
        ).normalizedAddress) ?? serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        // URL paths can be case-sensitive, so keep the normalized server identity intact.
        return Self.tokenAccountPrefix + identity
    }

    private func apply(_ auth: AuthResponse) throws {
        try tokenStore.save(auth.token, account: tokenAccount)
        user = auth.record
        token = auth.token
        preferences = nil
        restoreCachedPreferences(userID: auth.record.id)
        recoveryMessage = nil
        phase = .loggedIn
    }

    private func loadPreferences() async {
        guard let user, let token else { return }
        let requestID = UUID()
        latestPreferencesRequestID = requestID
        preferencesMessage = nil

        do {
            let loaded = try await makeClient().getPreferences(ownerID: user.id, token: token)
            guard latestPreferencesRequestID == requestID,
                  self.user?.id == user.id,
                  self.token == token else { return }
            preferences = loaded
            fallbackAppearance = loaded.theme
            cachePreferences()
            preferencesMessage = nil
        } catch {
            guard latestPreferencesRequestID == requestID,
                  self.user?.id == user.id,
                  self.token == token else { return }
            preferencesMessage = error.localizedDescription
        }
    }

    private func clearSession() {
        token = nil
        user = nil
        preferences = nil
        preferencesMessage = nil
        latestStatusRequestID = nil
        latestPreferencesRequestID = nil
    }

    private func failRecovery(_ error: Error) {
        recoveryMessage = error.localizedDescription
        phase = .recoveryFailed
    }

    private func cachePreferences() {
        guard let userID = user?.id,
              let preferences,
              let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: preferencesCacheKey(userID: userID))
    }

    private func restoreCachedPreferences(userID: String) {
        guard let data = defaults.data(forKey: preferencesCacheKey(userID: userID)),
              let cached = try? JSONDecoder().decode(UserPreferences.self, from: data),
              cached.owner == userID else { return }
        preferences = cached
        fallbackAppearance = cached.theme
    }

    private func preferencesCacheKey(userID: String) -> String {
        Self.preferencesCachePrefix + serverAddress + ":" + userID
    }
}
