import Foundation

struct AuthResponse: Decodable {
    let token: String
    let record: User
}

private struct CalendarEventPayload: Encodable {
    let owner: String?
    let title: String
    let description: String
    let startAt: String
    let endAt: String
    let allDay: Bool
    let timezone: String
    let location: String
    let color: EventColor
    let recurrenceFrequency: EventRecurrenceFrequency
    let recurrenceInterval: Int
    let reminderMinutesBefore: Int

    private enum CodingKeys: String, CodingKey {
        case owner, title, description, timezone, location, color
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case recurrenceFrequency = "recurrence_frequency"
        case recurrenceInterval = "recurrence_interval"
        case reminderMinutesBefore = "reminder_minutes_before"
    }

    init(owner: String?, input: CalendarEventInput) {
        self.owner = owner
        title = input.title
        description = input.description
        startAt = CalendarDate.string(from: input.startAt)
        endAt = CalendarDate.string(from: input.endAt)
        allDay = input.allDay
        timezone = input.timezone
        location = input.location
        color = input.color
        recurrenceFrequency = input.recurrenceFrequency
        recurrenceInterval = input.recurrenceInterval
        reminderMinutesBefore = input.reminder.rawValue
    }
}

private struct RealtimeConnection: Decodable {
    let clientId: String
}

enum APIError: LocalizedError {
    case cacheMiss
    case invalidResponse
    case transport(URLError)
    case http(statusCode: Int, message: String, fieldMessages: [String: String])
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .cacheMiss:
            "No cached response is available."
        case .invalidResponse:
            "The server returned an invalid response."
        case .transport(let error):
            "Could not reach the server. \(error.localizedDescription)"
        case .http(_, let message, let fieldMessages):
            if let first = fieldMessages.sorted(by: { $0.key < $1.key }).first {
                "\(message) \(first.key): \(first.value)"
            } else {
                message
            }
        case .decoding:
            "The server returned data this version of Workavera could not read."
        }
    }

    var isAuthenticationFailure: Bool {
        guard case .http(let statusCode, _, _) = self else { return false }
        return statusCode == 401 || statusCode == 403
    }
}

struct PocketBaseClient {
    let configuration: ServerConfiguration
    private let session: URLSession
    private let responseCache: APIResponseCache
    private let cacheNamespace: String?
    private let loadStrategy: DataLoadStrategy

    init(
        baseURLString: String,
        allowInsecureHTTP: Bool,
        session: URLSession = .shared,
        responseCache: APIResponseCache = .shared,
        cacheNamespace: String? = nil,
        loadStrategy: DataLoadStrategy = .networkOnly
    ) throws {
        configuration = try ServerConfiguration(
            address: baseURLString,
            allowInsecureHTTP: allowInsecureHTTP
        )
        self.session = session
        self.responseCache = responseCache
        self.cacheNamespace = cacheNamespace
        self.loadStrategy = loadStrategy
    }

    func authWithPassword(identity: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable {
            let identity: String
            let password: String
        }
        return try await sendJSON(
            path: "/api/collections/users/auth-with-password",
            method: "POST",
            body: Body(identity: identity, password: password)
        )
    }

    func authRefresh(token: String) async throws -> AuthResponse {
        try await send(path: "/api/collections/users/auth-refresh", method: "POST", token: token)
    }

    func updateStatus(id: String, status: UserStatus, token: String) async throws -> User {
        struct Body: Encodable { let status: UserStatus }
        return try await sendJSON(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: Body(status: status),
            token: token
        )
    }

    func updateProfile(
        id: String,
        profile: ProfileUpdate,
        avatar: AvatarUpload?,
        token: String
    ) async throws -> User {
        var form = MultipartFormData()
        form.addField(name: "name", value: profile.name)
        form.addField(name: "phone", value: profile.phone)
        form.addField(name: "title", value: profile.title)
        form.addField(name: "bio", value: profile.bio)
        form.addField(name: "status", value: profile.status.rawValue)
        if let avatar {
            form.addFile(
                name: "avatar",
                fileName: avatar.fileName,
                mimeType: avatar.mimeType,
                data: avatar.data
            )
        }
        let payload = form.finalize()
        return try await send(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: payload.data,
            contentType: "multipart/form-data; boundary=\(payload.boundary)",
            token: token
        )
    }

    func changePassword(
        id: String,
        currentPassword: String,
        newPassword: String,
        token: String
    ) async throws -> User {
        struct Body: Encodable {
            let oldPassword: String
            let password: String
            let passwordConfirm: String
        }
        return try await sendJSON(
            path: "/api/collections/users/records/\(id)",
            method: "PATCH",
            body: Body(
                oldPassword: currentPassword,
                password: newPassword,
                passwordConfirm: newPassword
            ),
            token: token
        )
    }

    func getPreferences(ownerID: String, token: String) async throws -> UserPreferences {
        let response: RecordListResponse<UserPreferences> = try await send(
            path: "/api/collections/user_preferences/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "filter", value: "owner = \"\(ownerID)\""),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perPage", value: "1"),
            ],
            token: token
        )
        guard let preferences = response.items.first else {
            throw APIError.http(
                statusCode: 404,
                message: "User preferences were not found.",
                fieldMessages: [:]
            )
        }
        return preferences
    }

    func updatePreferences(
        id: String,
        theme: AppAppearance? = nil,
        memoryEnabled: Bool? = nil,
        memoryAutoCapture: Bool? = nil,
        token: String
    ) async throws -> UserPreferences {
        struct Body: Encodable {
            let theme: String?
            let memoryEnabled: Bool?
            let memoryAutoCapture: Bool?

            enum CodingKeys: String, CodingKey {
                case theme
                case memoryEnabled = "memory_enabled"
                case memoryAutoCapture = "memory_auto_capture"
            }
        }
        return try await sendJSON(
            path: "/api/collections/user_preferences/records/\(id)",
            method: "PATCH",
            body: Body(
                theme: theme?.rawValue,
                memoryEnabled: memoryEnabled,
                memoryAutoCapture: memoryAutoCapture
            ),
            token: token
        )
    }

    func getContacts(ownerID: String, token: String) async throws -> ContactsSnapshot {
        async let contactsRequest: [ContactRecord] = listAllRecords(
            collection: "users",
            filter: "",
            sort: "name,id",
            token: token
        )
        async let favoritesRequest: [ContactFavoriteRecord] = listAllRecords(
            collection: "contact_favorites",
            filter: "owner = \"\(Self.filterLiteral(ownerID))\"",
            sort: "-created",
            token: token
        )
        let (records, favorites) = try await (contactsRequest, favoritesRequest)
        let favoriteRecordIDs = Dictionary(
            uniqueKeysWithValues: favorites.map { ($0.contact, $0.id) }
        )
        let contacts = records.map { record in
            Contact(
                id: record.id,
                collectionID: record.collectionID,
                name: record.name,
                email: record.email,
                phone: record.phone,
                title: record.title,
                bio: record.bio,
                status: record.status,
                avatarURL: fileURL(
                    collectionId: record.collectionID,
                    recordId: record.id,
                    fileName: record.avatar
                ),
                isFavorite: favoriteRecordIDs[record.id] != nil
            )
        }
        return ContactsSnapshot(contacts: contacts, favoriteRecordIDs: favoriteRecordIDs)
    }

    func createContactFavorite(
        ownerID: String,
        contactID: String,
        token: String
    ) async throws -> ContactFavoriteRecord {
        struct Body: Encodable {
            let owner: String
            let contact: String
        }
        return try await sendJSON(
            path: "/api/collections/contact_favorites/records",
            method: "POST",
            body: Body(owner: ownerID, contact: contactID),
            token: token
        )
    }

    func deleteContactFavorite(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/contact_favorites/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getChatConversations(
        status: ChatConversationStatus,
        page: Int,
        pageSize: Int,
        query: String = "",
        token: String
    ) async throws -> ChatConversationsPage {
        let sort = status == .active
            ? "-pinned,-last_message_at,-updated"
            : "-updated"
        var filter = "status = \"\(status.rawValue)\""
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedQuery.isEmpty {
            filter += " && title ~ \"\(Self.filterLiteral(normalizedQuery))\""
        }
        let response: RecordListResponse<ChatConversation> = try await send(
            path: "/api/collections/chat_conversations/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(pageSize)),
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "sort", value: sort),
            ],
            token: token
        )
        return ChatConversationsPage(
            items: response.items,
            page: response.page,
            totalPages: response.totalPages,
            totalItems: response.totalItems
        )
    }

    func createChatConversation(title: String, token: String) async throws -> ChatConversation {
        struct Body: Encodable { let title: String }
        return try await sendJSON(
            path: "/api/collections/chat_conversations/records",
            method: "POST",
            body: Body(title: title),
            token: token
        )
    }

    func updateChatConversation(
        id: String,
        update: ChatConversationUpdate,
        token: String
    ) async throws -> ChatConversation {
        try await sendJSON(
            path: "/api/collections/chat_conversations/records/\(id)",
            method: "PATCH",
            body: update,
            token: token
        )
    }

    func deleteChatConversation(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/chat_conversations/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getChatMessages(conversationID: String, token: String) async throws -> [ChatMessage] {
        try await send(
            path: "/api/chat/conversations/\(conversationID)/messages",
            method: "GET",
            token: token
        )
    }

    func startChatStream(
        request: ChatStreamRequest,
        token: String
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: APIError.decoding(error.localizedDescription))
            }
        }
        return chatStream(
            path: "/api/chat/stream",
            method: "POST",
            body: body,
            token: token
        )
    }

    func resumeChatStream(
        runID: String,
        token: String
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        chatStream(
            path: "/api/chat/runs/\(runID)/stream",
            method: "GET",
            body: nil,
            token: token
        )
    }

    func stopChatRun(runID: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/chat/runs/\(runID)/stop",
            method: "POST",
            token: token
        )
    }

    func respondToChatApproval(
        runID: String,
        approvalID: String,
        approved: Bool,
        token: String
    ) async throws {
        struct Body: Encodable { let approved: Bool }
        _ = try await perform(
            path: "/api/chat/runs/\(runID)/approvals/\(approvalID)",
            method: "POST",
            body: try JSONEncoder().encode(Body(approved: approved)),
            contentType: "application/json",
            token: token
        )
    }

    func getReadingPage(
        filter: ReadingListFilter,
        page: Int,
        pageSize: Int,
        query: String,
        token: String
    ) async throws -> ReadingPage {
        var filters: [String]
        switch filter {
        case .active:
            filters = ["status != \"archived\""]
        case .unread:
            filters = ["status = \"unread\""]
        case .read:
            filters = ["status = \"read\""]
        case .pinned:
            filters = ["status != \"archived\"", "pinned = true"]
        case .archived:
            filters = ["status = \"archived\""]
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedQuery.isEmpty {
            let escaped = Self.filterLiteral(normalizedQuery)
            filters.append(
                "(title ~ \"\(escaped)\" || url ~ \"\(escaped)\" || "
                    + "description ~ \"\(escaped)\" || summary ~ \"\(escaped)\" || "
                    + "tags ~ \"\(escaped)\" || key_points ~ \"\(escaped)\")"
            )
        }
        let filterString = filters.joined(separator: " && ")

        async let pageRequest: RecordListResponse<ReadingItem> = send(
            path: "/api/collections/reading_items/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "-pinned,-updated"),
                URLQueryItem(name: "filter", value: filterString),
                URLQueryItem(
                    name: "fields",
                    value: "id,owner,project,url,title,description,tags,status,pinned,summary,key_points,summary_language,created,updated"
                ),
            ],
            token: token
        )
        async let unreadRequest: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/reading_items/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perPage", value: "1"),
                URLQueryItem(name: "filter", value: "status = \"unread\""),
                URLQueryItem(name: "fields", value: "id"),
            ],
            token: token
        )
        let (result, unread) = try await (pageRequest, unreadRequest)
        return ReadingPage(
            items: result.items,
            page: result.page,
            totalPages: max(1, result.totalPages),
            totalItems: result.totalItems,
            unreadCount: unread.totalItems
        )
    }

    func createReadingItem(
        ownerID: String,
        input: ReadingItemInput,
        token: String
    ) async throws -> ReadingItem {
        struct Body: Encodable {
            let owner: String
            let url: String
            let title: String
            let description: String
            let tags: [String]
            let status: ReadingStatus
        }
        return try await sendJSON(
            path: "/api/collections/reading_items/records",
            method: "POST",
            body: Body(
                owner: ownerID,
                url: input.url,
                title: input.title,
                description: input.description,
                tags: input.tags,
                status: input.status
            ),
            token: token
        )
    }

    func updateReadingStatus(
        id: String,
        status: ReadingStatus,
        token: String
    ) async throws -> ReadingItem {
        struct Body: Encodable { let status: ReadingStatus }
        return try await sendJSON(
            path: "/api/collections/reading_items/records/\(id)",
            method: "PATCH",
            body: Body(status: status),
            token: token
        )
    }

    func setReadingPinned(id: String, pinned: Bool, token: String) async throws {
        struct Body: Encodable { let pinned: Bool }
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await sendJSON(
            path: "/api/reading/items/\(id)/pin",
            method: "POST",
            body: Body(pinned: pinned),
            token: token
        )
    }

    func deleteReadingItem(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/reading_items/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func summarizeReadingItem(id: String, token: String) async throws -> ReadingSummaryResponse {
        try await send(
            path: "/api/reading/items/\(id)/summarize",
            method: "POST",
            token: token
        )
    }

    func markAllReadingItemsRead(token: String) async throws -> Int {
        struct Response: Decodable { let updated: Int }
        let response: Response = try await send(
            path: "/api/reading/items/read-all",
            method: "POST",
            token: token
        )
        return response.updated
    }

    func getNotifications(
        page: Int,
        pageSize: Int,
        query: String = "",
        token: String
    ) async throws -> NotificationPage {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedQuery = Self.filterLiteral(normalizedQuery)
        var filters = ["status = \"active\""]
        if !escapedQuery.isEmpty {
            filters.append("(title ~ \"\(escapedQuery)\" || body ~ \"\(escapedQuery)\")")
        }
        let response: RecordListResponse<AppNotification> = try await send(
            path: "/api/collections/notifications/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "-pinned,-created"),
                URLQueryItem(name: "filter", value: filters.joined(separator: " && ")),
            ],
            token: token
        )
        return NotificationPage(
            items: response.items,
            page: response.page,
            totalPages: response.totalPages,
            totalItems: response.totalItems
        )
    }

    func getUnreadNotificationCount(token: String) async throws -> Int {
        let response: RecordListResponse<AppNotification> = try await send(
            path: "/api/collections/notifications/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perPage", value: "1"),
                URLQueryItem(name: "filter", value: "status = \"active\" && read_at = \"\""),
            ],
            token: token
        )
        return response.totalItems
    }

    func markNotificationRead(id: String, token: String) async throws {
        let _: NotificationMutationResponse = try await send(
            path: "/api/notifications/\(id)/read",
            method: "POST",
            token: token
        )
    }

    func markAllNotificationsRead(token: String) async throws {
        let _: NotificationMutationResponse = try await send(
            path: "/api/notifications/read-all",
            method: "POST",
            token: token
        )
    }

    func respondToModelShare(
        notificationID: String,
        decision: ModelShareDecision,
        token: String
    ) async throws -> ModelShareStatus {
        struct Body: Encodable { let decision: ModelShareDecision }
        struct Response: Decodable { let status: ModelShareStatus }
        let response: Response = try await sendJSON(
            path: "/api/llm/shares/\(notificationID)/respond",
            method: "POST",
            body: Body(decision: decision),
            token: token
        )
        return response.status
    }

    func archiveNotification(id: String, token: String) async throws -> AppNotification {
        struct Body: Encodable {
            let status = "archived"
            let pinned = false
        }
        return try await sendJSON(
            path: "/api/collections/notifications/records/\(id)",
            method: "PATCH",
            body: Body(),
            token: token
        )
    }

    func deleteNotification(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/notifications/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func notificationRealtimeEvents(
        token: String
    ) -> AsyncThrowingStream<NotificationRealtimeEvent, Error> {
        realtimeEvents(
            topics: ["notifications/*"],
            eventPrefixes: ["notifications"],
            token: token,
            connectionError: "Could not connect to realtime notifications."
        )
    }

    func calendarRealtimeSignals(
        token: String
    ) -> AsyncThrowingStream<CalendarRealtimeSignal, Error> {
        realtimeEvents(
            topics: ["calendar_events/*", "board_tasks/*"],
            eventPrefixes: ["calendar_events", "board_tasks"],
            token: token,
            connectionError: "Could not connect to realtime calendar updates."
        )
    }

    func boardRealtimeSignals(
        token: String
    ) -> AsyncThrowingStream<CalendarRealtimeSignal, Error> {
        realtimeEvents(
            topics: [
                "board_projects/*",
                "board_project_preferences/*",
                "board_project_states/*",
                "board_tasks/*",
                "board_project_labels/*",
                "board_project_members/*"
            ],
            eventPrefixes: [
                "board_projects",
                "board_project_preferences",
                "board_project_states",
                "board_tasks",
                "board_project_labels",
                "board_project_members"
            ],
            token: token,
            connectionError: "Could not connect to realtime board updates."
        )
    }

    func dashboardRealtimeSignals(
        token: String
    ) -> AsyncThrowingStream<CalendarRealtimeSignal, Error> {
        realtimeEvents(
            topics: [
                "board_projects/*",
                "board_tasks/*",
                "calendar_events/*",
                "reading_items/*"
            ],
            eventPrefixes: [
                "board_projects",
                "board_tasks",
                "calendar_events",
                "reading_items"
            ],
            token: token,
            connectionError: "Could not connect to realtime dashboard updates."
        )
    }

    func getDashboardSummary(now: Date = .now, token: String) async throws -> DashboardSummary {
        let nextWeek = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: 7,
            to: now
        ) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let nowValue = Self.dashboardDate(now)
        let nextWeekValue = Self.dashboardDate(nextWeek)
        let openTaskFilter = "state.category != \"completed\" && archived = false"

        async let projects: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/board_projects/records",
            method: "GET",
            queryItems: Self.countQuery(filter: "archived = false"),
            token: token,
            cacheKey: "dashboard.active-projects"
        )
        async let tasks: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/board_tasks/records",
            method: "GET",
            queryItems: Self.countQuery(filter: openTaskFilter),
            token: token,
            cacheKey: "dashboard.open-tasks"
        )
        async let events: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/calendar_events/records",
            method: "GET",
            queryItems: Self.countQuery(
                filter: "start_at >= \"\(nowValue)\" && start_at < \"\(nextWeekValue)\""
            ),
            token: token,
            cacheKey: "dashboard.next-seven-days-events"
        )
        async let upcomingTasks: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/board_tasks/records",
            method: "GET",
            queryItems: Self.countQuery(
                filter: "\(openTaskFilter) && due_date >= \"\(nowValue)\" && due_date < \"\(nextWeekValue)\""
            ),
            token: token,
            cacheKey: "dashboard.next-seven-days-tasks"
        )
        async let reading: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/reading_items/records",
            method: "GET",
            queryItems: Self.countQuery(filter: "status = \"unread\""),
            token: token,
            cacheKey: "dashboard.unread-reading"
        )

        let (projectResult, taskResult, eventResult, upcomingTaskResult, readingResult) = try await (
            projects,
            tasks,
            events,
            upcomingTasks,
            reading
        )
        return DashboardSummary(
            activeProjects: projectResult.totalItems,
            openTasks: taskResult.totalItems,
            nextSevenDays: eventResult.totalItems + upcomingTaskResult.totalItems,
            unreadReading: readingResult.totalItems,
            loadedAt: now
        )
    }

    func getDocsPage(
        userID: String,
        view: DocsViewFilter,
        page: Int,
        pageSize: Int,
        query: String,
        token: String
    ) async throws -> DocsPage {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedQuery = Self.filterLiteral(normalizedQuery)
        let pinnedQuery = normalizedQuery.isEmpty
            ? []
            : [URLQueryItem(name: "query", value: normalizedQuery)]

        async let pinnedRequest: [PinnedDocumentRecord] = send(
            path: "/api/docs-pinned",
            method: "GET",
            queryItems: pinnedQuery,
            token: token
        )
        async let foldersRequest: [DocumentFolderRecord] = listAllRecords(
            collection: "doc_folders",
            filter: "",
            sort: "name",
            token: token
        )
        async let projectsRequest: [BoardProjectPreferenceRecord] = listAllRecords(
            collection: "board_project_preferences",
            filter: "user = \"\(Self.filterLiteral(userID))\" && project.archived = false",
            sort: "sort_order,id",
            expand: "project",
            token: token
        )

        let listResponse: RecordListResponse<DocumentRecord>?
        if view == .pinned {
            listResponse = nil
        } else {
            var filters = [view == .archived ? "status = \"archived\"" : "status = \"draft\""]
            if !escapedQuery.isEmpty {
                filters.append("(title ~ \"\(escapedQuery)\" || content ~ \"\(escapedQuery)\")")
            }
            switch view {
            case .myDocuments:
                filters.append("project = \"\"")
                filters.append("folder = \"\"")
            case .folder(let id):
                filters.append("project = \"\"")
                filters.append("folder = \"\(Self.filterLiteral(id))\"")
            case .project(let id):
                filters.append("project = \"\(Self.filterLiteral(id))\"")
            case .recent, .pinned, .archived:
                break
            }
            let isRecent = view == .recent
            listResponse = try await send(
                path: "/api/collections/docs/records",
                method: "GET",
                queryItems: [
                    URLQueryItem(name: "page", value: String(isRecent ? 1 : page)),
                    URLQueryItem(name: "perPage", value: String(isRecent ? 10 : pageSize)),
                    URLQueryItem(name: "sort", value: "-updated"),
                    URLQueryItem(name: "filter", value: filters.joined(separator: " && ")),
                    URLQueryItem(
                        name: "fields",
                        value: "id,title,kind,owner,project,folder,status,revision,last_edited_by,created,updated"
                    ),
                ],
                token: token
            )
        }

        let (pinnedRecords, folderRecords, projectPreferences) = try await (
            pinnedRequest,
            foldersRequest,
            projectsRequest
        )
        let pinnedIDs = Set(pinnedRecords.map(\.id))
        let documents: [DocumentSummary]
        let resolvedPage: Int
        let totalPages: Int
        let totalItems: Int
        if view == .pinned {
            documents = pinnedRecords.map(Self.documentSummary)
            resolvedPage = 1
            totalPages = 1
            totalItems = documents.count
        } else if let listResponse {
            documents = listResponse.items.map {
                Self.documentSummary($0, pinned: pinnedIDs.contains($0.id))
            }
            resolvedPage = view == .recent ? 1 : listResponse.page
            totalPages = view == .recent ? 1 : max(1, listResponse.totalPages)
            totalItems = view == .recent ? documents.count : listResponse.totalItems
        } else {
            documents = []
            resolvedPage = 1
            totalPages = 1
            totalItems = 0
        }

        return DocsPage(
            documents: documents,
            folders: folderRecords.map { DocumentFolder(id: $0.id, name: $0.name) },
            projects: projectPreferences.compactMap { preference in
                guard let project = preference.expand?.project else { return nil }
                return DocumentProject(id: project.id, name: project.name)
            },
            page: resolvedPage,
            totalPages: totalPages,
            totalItems: totalItems
        )
    }

    func getDocument(id: String, pinned: Bool, token: String) async throws -> WorkspaceDocument {
        let record: DocumentRecord = try await send(
            path: "/api/collections/docs/records/\(id)",
            method: "GET",
            token: token
        )
        return Self.workspaceDocument(record, pinned: pinned)
    }

    func getDocumentVersions(id: String, token: String) async throws -> [DocumentVersion] {
        try await send(
            path: "/api/docs/\(id)/versions",
            method: "GET",
            token: token
        )
    }

    func getDocumentVersion(
        id: String,
        revision: Int,
        token: String
    ) async throws -> DocumentVersion {
        try await send(
            path: "/api/docs/\(id)/versions/\(revision)",
            method: "GET",
            token: token
        )
    }

    func setDocumentPinned(id: String, pinned: Bool, token: String) async throws {
        struct Body: Encodable { let pinned: Bool }
        struct Response: Decodable { let pinned: Bool }
        let _: Response = try await sendJSON(
            path: "/api/docs/\(id)/pin",
            method: "POST",
            body: Body(pinned: pinned),
            token: token
        )
    }

    func setDocumentArchived(id: String, archived: Bool, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/docs/\(id)/\(archived ? "archive" : "unarchive")",
            method: "POST",
            token: token
        )
    }

    func deleteDocument(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/docs/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getAPIKeys(token: String) async throws -> [WorkaveraAPIKey] {
        try await listAllRecords(
            collection: "api_keys",
            filter: "",
            sort: "-created",
            token: token
        )
    }

    func createAPIKey(
        name: String,
        expiration: APIKeyExpiration,
        allowsDestructiveActions: Bool,
        token: String
    ) async throws -> CreatedWorkaveraAPIKey {
        struct Body: Encodable {
            let name: String
            let allowDestructive: Bool
            let expires: String
        }
        return try await sendJSON(
            path: "/api/apikeys",
            method: "POST",
            body: Body(
                name: name,
                allowDestructive: allowsDestructiveActions,
                expires: expiration.requestValue()
            ),
            token: token
        )
    }

    func revokeAPIKey(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/api_keys/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getLLMModels(token: String) async throws -> [LLMModelConfiguration] {
        try await send(path: "/api/llm/models", method: "GET", token: token)
    }

    func createLLMModel(
        input: LLMModelInput,
        token: String
    ) async throws -> LLMModelConfiguration {
        try await sendJSON(
            path: "/api/llm/models",
            method: "POST",
            body: input,
            token: token
        )
    }

    func updateLLMModel(
        id: String,
        input: LLMModelInput,
        token: String
    ) async throws -> LLMModelConfiguration {
        try await sendJSON(
            path: "/api/llm/models/\(id)",
            method: "PATCH",
            body: input,
            token: token
        )
    }

    func deleteLLMModel(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/llm/models/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func setDefaultLLMModel(id: String, token: String) async throws -> LLMModelConfiguration {
        try await send(
            path: "/api/llm/models/\(id)/default",
            method: "POST",
            token: token
        )
    }

    func getLLMShareTargets(token: String) async throws -> [LLMShareTarget] {
        try await send(path: "/api/llm/share-targets", method: "GET", token: token)
    }

    func shareLLMModel(
        id: String,
        userIDs: [String],
        token: String
    ) async throws -> Int {
        struct Body: Encodable { let userIds: [String] }
        let response: LLMShareResponse = try await sendJSON(
            path: "/api/llm/models/\(id)/share",
            method: "POST",
            body: Body(userIds: userIDs),
            token: token
        )
        return response.shared
    }

    func getMCPServers(token: String) async throws -> [MCPServer] {
        try await listAllRecords(
            collection: "mcp_servers",
            filter: "",
            sort: "created",
            token: token
        )
    }

    func createMCPServer(
        input: MCPServerInput,
        token: String
    ) async throws -> MCPServer {
        struct Body: Encodable {
            let name: String
            let slug: String
            let transport: String
            let url: String
            let approvalPolicy: String
            let headers: [String: String]
        }
        return try await sendJSON(
            path: "/api/mcp-servers",
            method: "POST",
            body: Body(
                name: input.name,
                slug: input.slug,
                transport: input.transport.rawValue,
                url: input.url,
                approvalPolicy: input.approvalPolicy.rawValue,
                headers: input.headers
            ),
            token: token
        )
    }

    /// Credentials are write-only, so an untouched header field must leave the
    /// stored headers alone rather than replacing them with nothing.
    func updateMCPServer(
        id: String,
        input: MCPServerUpdate,
        token: String
    ) async throws -> MCPServer {
        struct Body: Encodable {
            let name: String?
            let url: String?
            let transport: String?
            let approvalPolicy: String?
            let headers: [String: String]?
            let enabled: Bool?
        }
        return try await sendJSON(
            path: "/api/mcp-servers/\(id)",
            method: "PATCH",
            body: Body(
                name: input.name,
                url: input.url,
                transport: input.transport?.rawValue,
                approvalPolicy: input.approvalPolicy?.rawValue,
                headers: input.headers,
                enabled: input.enabled
            ),
            token: token
        )
    }

    func refreshMCPServer(id: String, token: String) async throws -> MCPRefreshResponse {
        try await send(
            path: "/api/mcp-servers/\(id)/refresh",
            method: "POST",
            token: token
        )
    }

    /// Applies the user's review decisions. The route only accepts the two
    /// fields the user owns: whether a tool is enabled and whether each call
    /// needs approval. Tool definitions themselves only come from a refresh.
    func updateMCPServerTools(
        id: String,
        tools: [MCPToolDecision],
        token: String
    ) async throws -> MCPServer {
        struct ToolBody: Encodable {
            let name: String
            let enabled: Bool
            let approval: String
        }
        struct Body: Encodable {
            let tools: [ToolBody]
        }
        return try await sendJSON(
            path: "/api/mcp-servers/\(id)/tools",
            method: "PATCH",
            body: Body(
                tools: tools.map {
                    ToolBody(name: $0.name, enabled: $0.enabled, approval: $0.approval.rawValue)
                }
            ),
            token: token
        )
    }

    func deleteMCPServer(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/mcp_servers/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getSavedMemories(token: String) async throws -> [SavedChatMemory] {
        try await listAllRecords(
            collection: "chat_memories",
            filter: "",
            sort: "-updated",
            token: token
        )
    }

    func createSavedMemory(
        category: MemoryCategory,
        content: String,
        token: String
    ) async throws -> SavedChatMemory {
        struct Body: Encodable {
            let category: MemoryCategory
            let content: String
        }
        return try await sendJSON(
            path: "/api/collections/chat_memories/records",
            method: "POST",
            body: Body(category: category, content: content),
            token: token
        )
    }

    func updateSavedMemory(
        id: String,
        category: MemoryCategory,
        content: String,
        token: String
    ) async throws -> SavedChatMemory {
        struct Body: Encodable {
            let category: MemoryCategory
            let content: String
        }
        return try await sendJSON(
            path: "/api/collections/chat_memories/records/\(id)",
            method: "PATCH",
            body: Body(category: category, content: content),
            token: token
        )
    }

    func setSavedMemoryActive(
        id: String,
        active: Bool,
        token: String
    ) async throws -> SavedChatMemory {
        struct Body: Encodable { let active: Bool }
        return try await sendJSON(
            path: "/api/collections/chat_memories/records/\(id)",
            method: "PATCH",
            body: Body(active: active),
            token: token
        )
    }

    func deleteSavedMemory(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/chat_memories/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getCalendarSnapshot(
        userID: String,
        token: String
    ) async throws -> CalendarSnapshot {
        struct SystemConfig: Decodable { let timezone: String }

        async let eventsRequest: [AppEvent] = listAllRecords(
            collection: "calendar_events",
            filter: "",
            sort: "start_at",
            token: token
        )
        async let tasksRequest: [CalendarTaskDeadline] = listAllRecords(
            collection: "board_tasks",
            filter: "due_date != \"\" && archived = false && assignees ?= \"\(userID)\"",
            sort: "due_date",
            expand: "project,state",
            token: token
        )
        async let configRequest: SystemConfig = send(
            path: "/api/configs/system",
            method: "GET",
            token: token
        )

        let (loadedEvents, tasks, config) = try await (eventsRequest, tasksRequest, configRequest)
        let timezone = TimeZone(identifier: config.timezone) == nil
            ? TimeZone.current.identifier
            : config.timezone
        let events = loadedEvents.map { event in
            var event = event
            event.timezone = timezone
            return event
        }
        return CalendarSnapshot(events: events, tasks: tasks, timezone: timezone)
    }

    func createCalendarEvent(
        ownerID: String,
        input: CalendarEventInput,
        token: String
    ) async throws -> AppEvent {
        try await sendJSON(
            path: "/api/collections/calendar_events/records",
            method: "POST",
            body: CalendarEventPayload(owner: ownerID, input: input),
            token: token
        )
    }

    func updateCalendarEvent(
        id: String,
        input: CalendarEventInput,
        token: String
    ) async throws -> AppEvent {
        try await sendJSON(
            path: "/api/collections/calendar_events/records/\(id)",
            method: "PATCH",
            body: CalendarEventPayload(owner: nil, input: input),
            token: token
        )
    }

    func deleteCalendarEvent(id: String, token: String) async throws {
        try await sendWithoutResponse(
            path: "/api/collections/calendar_events/records/\(id)",
            method: "DELETE",
            token: token
        )
    }

    func getBoardPage(
        userID: String,
        page: Int,
        pageSize: Int,
        token: String
    ) async throws -> BoardPage {
        let preferences: RecordListResponse<BoardProjectPreferenceRecord> = try await send(
            path: "/api/collections/board_project_preferences/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "sort_order,id"),
                URLQueryItem(name: "expand", value: "project,project.owner"),
                URLQueryItem(
                    name: "filter",
                    value: "user = \"\(userID)\" && project.archived = false"
                ),
            ],
            token: token
        )
        let projectRecords = preferences.items.compactMap(\.expand?.project)
        let projectIDs = projectRecords.map(\.id)
        guard !projectIDs.isEmpty else {
            return BoardPage(
                projects: [],
                page: preferences.page,
                totalPages: max(1, preferences.totalPages),
                totalItems: preferences.totalItems
            )
        }

        let filter = Self.projectFilter(projectIDs)
        let activeTaskFilter = "(\(filter)) && archived = false"
        async let statesRequest: [BoardStateRecord] = listAllRecords(
            collection: "board_project_states",
            filter: filter,
            sort: "sort_order",
            token: token
        )
        async let tasksRequest: [BoardTaskRecord] = listAllRecords(
            collection: "board_tasks",
            filter: activeTaskFilter,
            sort: "rank",
            token: token
        )
        async let labelsRequest: [BoardLabelRecord] = listAllRecords(
            collection: "board_project_labels",
            filter: filter,
            sort: "name",
            token: token
        )
        async let membersRequest: [BoardMemberRecord] = listAllRecords(
            collection: "board_project_members",
            filter: filter,
            sort: "created",
            expand: "user",
            token: token
        )
        let (stateRecords, taskRecords, labelRecords, memberRecords) = try await (
            statesRequest,
            tasksRequest,
            labelsRequest,
            membersRequest
        )

        let projects = assembleBoardProjects(
            projects: projectRecords,
            states: stateRecords,
            tasks: taskRecords,
            labels: labelRecords,
            members: memberRecords
        )
        return BoardPage(
            projects: projects,
            page: preferences.page,
            totalPages: max(1, preferences.totalPages),
            totalItems: preferences.totalItems
        )
    }

    func moveBoardTask(
        id: String,
        stateID: String,
        rank: Double,
        token: String
    ) async throws -> BoardTaskMoveResponse {
        struct Body: Encodable {
            let state: String
            let rank: Double
        }
        return try await sendJSON(
            path: "/api/collections/board_tasks/records/\(id)",
            method: "PATCH",
            body: Body(state: stateID, rank: rank),
            token: token
        )
    }

    func updateBoardTaskPriority(
        id: String,
        priority: TaskPriority,
        token: String
    ) async throws -> BoardTaskPriorityResponse {
        struct Body: Encodable {
            let priority: TaskPriority
        }
        return try await sendJSON(
            path: "/api/collections/board_tasks/records/\(id)",
            method: "PATCH",
            body: Body(priority: priority),
            token: token
        )
    }

    func updateBoardTaskDueDate(
        id: String,
        dueDate: Date?,
        token: String
    ) async throws -> BoardTaskDueDateResponse {
        struct Body: Encodable {
            let dueDate: String

            private enum CodingKeys: String, CodingKey {
                case dueDate = "due_date"
            }
        }
        return try await sendJSON(
            path: "/api/collections/board_tasks/records/\(id)",
            method: "PATCH",
            body: Body(dueDate: dueDate.map(Self.dashboardDate) ?? ""),
            token: token
        )
    }

    func archiveBoardTask(
        id: String,
        token: String
    ) async throws -> BoardTaskArchiveResponse {
        struct Body: Encodable {
            let archived: Bool
        }
        return try await sendJSON(
            path: "/api/collections/board_tasks/records/\(id)",
            method: "PATCH",
            body: Body(archived: true),
            token: token
        )
    }

    func fileURL(collectionId: String, recordId: String, fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        return configuration.baseURL.appending(
            path: "/api/files/\(collectionId)/\(recordId)/\(fileName)"
        )
    }

    private func listAllRecords<Record: Decodable>(
        collection: String,
        filter: String,
        sort: String,
        expand: String? = nil,
        token: String
    ) async throws -> [Record] {
        var page = 1
        var records: [Record] = []
        while true {
            var queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: "200"),
            ]
            if !filter.isEmpty {
                queryItems.append(URLQueryItem(name: "filter", value: filter))
            }
            if !sort.isEmpty {
                queryItems.append(URLQueryItem(name: "sort", value: sort))
            }
            if let expand {
                queryItems.append(URLQueryItem(name: "expand", value: expand))
            }
            let response: RecordListResponse<Record> = try await send(
                path: "/api/collections/\(collection)/records",
                method: "GET",
                queryItems: queryItems,
                token: token
            )
            records.append(contentsOf: response.items)
            if page >= response.totalPages { return records }
            page += 1
        }
    }

    private static func projectFilter(_ projectIDs: [String]) -> String {
        projectIDs.map { "project = \"\($0)\"" }.joined(separator: " || ")
    }

    private func assembleBoardProjects(
        projects: [BoardProjectRecord],
        states: [BoardStateRecord],
        tasks: [BoardTaskRecord],
        labels: [BoardLabelRecord],
        members: [BoardMemberRecord]
    ) -> [BoardProject] {
        let boardLabels = labels.map {
            BoardLabel(id: $0.id, projectID: $0.project, name: $0.name, color: $0.color)
        }
        let labelsByID = Dictionary(uniqueKeysWithValues: boardLabels.map { ($0.id, $0) })

        var membersByProject: [String: [BoardMember]] = [:]
        var membersByUserID: [String: BoardMember] = [:]
        for project in projects {
            let ownerRecord = project.expand?.owner
            let owner = BoardMember(
                id: project.owner,
                name: ownerRecord?.displayName ?? "Project owner",
                avatarURL: ownerRecord.flatMap(boardAvatarURL)
            )
            membersByProject[project.id, default: []].append(owner)
            membersByUserID[owner.id] = owner
        }
        for record in members {
            let userRecord = record.expand?.user
            let member = BoardMember(
                id: record.user,
                name: userRecord?.displayName ?? "Unknown member",
                avatarURL: userRecord.flatMap(boardAvatarURL)
            )
            guard membersByProject[record.project]?.contains(where: { $0.id == member.id }) != true else {
                continue
            }
            membersByProject[record.project, default: []].append(member)
            membersByUserID[member.id] = member
        }

        var tasksByState: [String: [BoardTask]] = [:]
        for record in tasks {
            let task = BoardTask(
                id: record.id,
                projectID: record.project,
                stateID: record.state,
                title: record.title,
                description: record.description,
                priority: record.priority,
                dueDate: Self.boardDate(record.dueDate),
                labels: record.labelIDs.compactMap { labelsByID[$0] },
                assignees: record.assigneeIDs.map {
                    membersByUserID[$0] ?? BoardMember(
                        id: $0,
                        name: "Unknown member",
                        avatarURL: nil
                    )
                },
                documentCount: record.documentIDs.count,
                rank: record.rank
            )
            tasksByState[record.state, default: []].append(task)
        }

        var statesByProject: [String: [BoardState]] = [:]
        for record in states {
            statesByProject[record.project, default: []].append(
                BoardState(
                    id: record.id,
                    projectID: record.project,
                    name: record.name,
                    color: record.color,
                    category: record.category,
                    sortOrder: record.sortOrder,
                    tasks: (tasksByState[record.id] ?? []).sorted { $0.rank < $1.rank }
                )
            )
        }

        return projects.map { project in
            BoardProject(
                id: project.id,
                ownerID: project.owner,
                name: project.name,
                description: project.description,
                members: membersByProject[project.id] ?? [],
                labels: boardLabels.filter { $0.projectID == project.id },
                states: (statesByProject[project.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            )
        }
    }

    private func boardAvatarURL(for user: BoardUserRecord) -> URL? {
        fileURL(
            collectionId: user.collectionId,
            recordId: user.id,
            fileName: user.avatar
        )
    }

    private static func boardDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
        return formatter.date(from: value)
    }

    private static func countQuery(filter: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "perPage", value: "1"),
            URLQueryItem(name: "fields", value: "id"),
            URLQueryItem(name: "filter", value: filter),
        ]
    }

    private static func dashboardDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func filterLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func documentSummary(
        _ record: DocumentRecord,
        pinned: Bool
    ) -> DocumentSummary {
        DocumentSummary(
            id: record.id,
            title: record.title,
            kind: record.kind,
            ownerID: record.owner,
            projectID: record.project.isEmpty ? nil : record.project,
            folderID: record.folder.isEmpty ? nil : record.folder,
            status: record.status,
            revision: record.revision,
            updatedAt: DocsDate.parse(record.updated),
            pinned: pinned
        )
    }

    private static func documentSummary(_ record: PinnedDocumentRecord) -> DocumentSummary {
        DocumentSummary(
            id: record.id,
            title: record.title,
            kind: record.kind,
            ownerID: record.ownerID,
            projectID: record.projectID,
            folderID: record.folderID,
            status: record.status,
            revision: record.revision,
            updatedAt: DocsDate.parse(record.updated),
            pinned: true
        )
    }

    private static func workspaceDocument(
        _ record: DocumentRecord,
        pinned: Bool
    ) -> WorkspaceDocument {
        WorkspaceDocument(
            id: record.id,
            title: record.title,
            kind: record.kind,
            content: record.content,
            ownerID: record.owner,
            projectID: record.project.isEmpty ? nil : record.project,
            folderID: record.folder.isEmpty ? nil : record.folder,
            status: record.status,
            revision: record.revision,
            lastEditedBy: record.lastEditedBy,
            createdAt: DocsDate.parse(record.created),
            updatedAt: DocsDate.parse(record.updated),
            pinned: pinned
        )
    }

    private func realtimeEvents<Event: Decodable>(
        topics: [String],
        eventPrefixes: [String],
        token: String,
        connectionError: String
    ) -> AsyncThrowingStream<Event, Error> {
        let realtimeURL = configuration.baseURL.appending(path: "/api/realtime")
        let session = session

        return AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    var request = URLRequest(url: realtimeURL)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 35 * 60
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw APIError.http(
                            statusCode: http.statusCode,
                            message: connectionError,
                            fieldMessages: [:]
                        )
                    }

                    func dispatchFrame(_ frame: Data) async throws {
                        let text = String(decoding: frame, as: UTF8.self)
                        var eventName = ""
                        var dataLines: [String] = []
                        for rawLine in text.split(whereSeparator: \.isNewline) {
                            let line = String(rawLine)
                            if line.hasPrefix("event:") {
                                eventName = String(line.dropFirst("event:".count))
                                    .trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("data:") {
                                dataLines.append(
                                    String(line.dropFirst("data:".count))
                                        .trimmingCharacters(in: .whitespaces)
                                )
                            }
                        }
                        guard !eventName.isEmpty else { return }
                        let data = Data(dataLines.joined(separator: "\n").utf8)
                        if eventName == "PB_CONNECT" {
                            let connection = try JSONDecoder().decode(RealtimeConnection.self, from: data)
                            try await Self.setRealtimeSubscriptions(
                                clientID: connection.clientId,
                                topics: topics,
                                token: token,
                                url: realtimeURL,
                                session: session
                            )
                        } else if eventPrefixes.contains(where: eventName.hasPrefix) {
                            continuation.yield(try JSONDecoder().decode(Event.self, from: data))
                        }
                    }

                    var frameBytes: [UInt8] = []
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        frameBytes.append(byte)
                        let delimiterLength: Int
                        if frameBytes.suffix(4).elementsEqual([13, 10, 13, 10]) {
                            delimiterLength = 4
                        } else if frameBytes.suffix(2).elementsEqual([10, 10]) {
                            delimiterLength = 2
                        } else {
                            if frameBytes.count > 1_048_576 {
                                throw APIError.invalidResponse
                            }
                            continue
                        }
                        frameBytes.removeLast(delimiterLength)
                        try await dispatchFrame(Data(frameBytes))
                        frameBytes.removeAll(keepingCapacity: true)
                    }
                    if !frameBytes.isEmpty {
                        try await dispatchFrame(Data(frameBytes))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in streamTask.cancel() }
        }
    }

    private func chatStream(
        path: String,
        method: String,
        body: Data?,
        token: String
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let url = configuration.baseURL.appending(path: path)
        let session = session

        return AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = method
                    request.timeoutInterval = 11 * 60
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    request.setValue(token, forHTTPHeaderField: "Authorization")
                    if let body {
                        request.httpBody = body
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes.prefix(1_048_576) {
                            errorData.append(byte)
                        }
                        let details = Self.errorDetails(from: errorData, statusCode: http.statusCode)
                        throw APIError.http(
                            statusCode: http.statusCode,
                            message: details.message,
                            fieldMessages: details.fieldMessages
                        )
                    }

                    func dispatchFrame(_ frame: Data) throws -> Bool {
                        let text = String(decoding: frame, as: UTF8.self)
                        let payload = text
                            .split(whereSeparator: \.isNewline)
                            .compactMap { rawLine -> String? in
                                let line = String(rawLine)
                                guard line.hasPrefix("data:") else { return nil }
                                return String(line.dropFirst("data:".count))
                                    .trimmingCharacters(in: .whitespaces)
                            }
                            .joined(separator: "\n")
                        guard !payload.isEmpty else { return false }
                        if payload == "[DONE]" { return true }
                        let chunk = try JSONDecoder().decode(
                            ChatStreamChunk.self,
                            from: Data(payload.utf8)
                        )
                        continuation.yield(chunk)
                        return false
                    }

                    var frameBytes: [UInt8] = []
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        frameBytes.append(byte)
                        let delimiterLength: Int
                        if frameBytes.suffix(4).elementsEqual([13, 10, 13, 10]) {
                            delimiterLength = 4
                        } else if frameBytes.suffix(2).elementsEqual([10, 10]) {
                            delimiterLength = 2
                        } else {
                            if frameBytes.count > 5 * 1_048_576 {
                                throw APIError.invalidResponse
                            }
                            continue
                        }
                        frameBytes.removeLast(delimiterLength)
                        let done = try dispatchFrame(Data(frameBytes))
                        frameBytes.removeAll(keepingCapacity: true)
                        if done { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: APIError.transport(error))
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in streamTask.cancel() }
        }
    }

    private static func setRealtimeSubscriptions(
        clientID: String,
        topics: [String],
        token: String,
        url: URL,
        session: URLSession
    ) async throws {
        struct Body: Encodable {
            let clientId: String
            let subscriptions: [String]
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            Body(clientId: clientID, subscriptions: topics)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let details = errorDetails(from: data, statusCode: http.statusCode)
            throw APIError.http(
                statusCode: http.statusCode,
                message: details.message,
                fieldMessages: details.fieldMessages
            )
        }
    }

    private func sendJSON<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        token: String? = nil
    ) async throws -> T {
        try await send(
            path: path,
            method: method,
            body: try JSONEncoder().encode(body),
            contentType: "application/json",
            token: token
        )
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        token: String? = nil,
        cacheKey: String? = nil
    ) async throws -> T {
        let data = try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            contentType: contentType,
            token: token,
            cacheKey: cacheKey
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if loadStrategy != .networkOnly,
               let responseCacheKey = responseCacheKey(
                   path: path,
                   method: method,
                   queryItems: queryItems,
                   override: cacheKey
               ) {
                responseCache.removeValue(for: responseCacheKey)
                throw APIError.cacheMiss
            }
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func sendWithoutResponse(
        path: String,
        method: String,
        token: String? = nil
    ) async throws {
        _ = try await perform(path: path, method: method, token: token)
    }

    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        token: String? = nil,
        cacheKey: String? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw APIError.invalidResponse }

        let responseCacheKey = responseCacheKey(
            path: path,
            method: method,
            queryItems: queryItems,
            override: cacheKey
        )
        if loadStrategy == .cacheOnly {
            guard let responseCacheKey,
                  let cached = responseCache.data(for: responseCacheKey) else {
                throw APIError.cacheMiss
            }
            return cached
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // URLSession commonly reports Swift task cancellation as URLError.cancelled.
            // Keep it out of user-facing connectivity banners.
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            throw APIError.transport(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let details = Self.errorDetails(from: data, statusCode: http.statusCode)
            throw APIError.http(
                statusCode: http.statusCode,
                message: details.message,
                fieldMessages: details.fieldMessages
            )
        }
        if let responseCacheKey {
            responseCache.store(data, for: responseCacheKey)
        }
        return data
    }

    private func responseCacheKey(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        override: String?
    ) -> String? {
        guard method == "GET", let cacheNamespace else { return nil }
        if let override {
            return cacheNamespace + "|" + override
        }
        var components = URLComponents(
            url: configuration.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { return nil }
        return cacheNamespace + "|" + url.absoluteString
    }

    private static func errorDetails(
        from data: Data,
        statusCode: Int
    ) -> (message: String, fieldMessages: [String: String]) {
        struct FieldError: Decodable { let message: String? }
        struct ErrorResponse: Decodable {
            let message: String?
            let data: [String: FieldError]?
        }
        if let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            let fields = response.data?.compactMapValues(\.message) ?? [:]
            return (
                response.message?.isEmpty == false ? response.message! : "Request failed (HTTP \(statusCode)).",
                fields
            )
        }
        return ("Request failed (HTTP \(statusCode)).", [:])
    }
}

private struct RecordListResponse<Record: Decodable>: Decodable {
    let items: [Record]
    let page: Int
    let totalPages: Int
    let totalItems: Int

    private enum CodingKeys: String, CodingKey {
        case items, page, totalPages, totalItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([Record].self, forKey: .items)
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 1
        totalItems = try container.decodeIfPresent(Int.self, forKey: .totalItems) ?? items.count
    }
}

private struct RecordIDOnly: Decodable {
    let id: String
}

private struct NotificationMutationResponse: Decodable {}

private struct MultipartFormData {
    private let boundary = "Workavera-\(UUID().uuidString)"
    private var data = Data()

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(escaped(name))\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(escaped(name))\"; filename=\"\(escaped(fileName))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finalize() -> (data: Data, boundary: String) {
        append("--\(boundary)--\r\n")
        return (data, boundary)
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
