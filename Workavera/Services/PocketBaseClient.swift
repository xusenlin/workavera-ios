import Foundation

struct AuthResponse: Decodable {
    let token: String
    let record: User
}

enum APIError: LocalizedError {
    case invalidResponse
    case transport(URLError)
    case http(statusCode: Int, message: String, fieldMessages: [String: String])
    case decoding(String)

    var errorDescription: String? {
        switch self {
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

    init(
        baseURLString: String,
        allowInsecureHTTP: Bool,
        session: URLSession = .shared
    ) throws {
        configuration = try ServerConfiguration(
            address: baseURLString,
            allowInsecureHTTP: allowInsecureHTTP
        )
        self.session = session
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

    func getNotifications(page: Int, pageSize: Int, token: String) async throws -> NotificationPage {
        let response: RecordListResponse<AppNotification> = try await send(
            path: "/api/collections/notifications/records",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "-pinned,-created"),
                URLQueryItem(name: "filter", value: "status = \"active\""),
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
                            message: "Could not connect to realtime notifications.",
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
                            struct Connection: Decodable { let clientId: String }
                            let connection = try JSONDecoder().decode(Connection.self, from: data)
                            try await Self.setRealtimeSubscriptions(
                                clientID: connection.clientId,
                                topics: ["notifications/*"],
                                token: token,
                                url: realtimeURL,
                                session: session
                            )
                        } else if eventName.hasPrefix("notifications") {
                            let event = try JSONDecoder().decode(NotificationRealtimeEvent.self, from: data)
                            continuation.yield(event)
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

    func getDashboardSummary(now: Date = .now, token: String) async throws -> DashboardSummary {
        let nextWeek = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: 7,
            to: now
        ) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let nowValue = Self.dashboardDate(now)
        let nextWeekValue = Self.dashboardDate(nextWeek)
        let openTaskFilter = "state.category != \"completed\""

        async let projects: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/board_projects/records",
            method: "GET",
            queryItems: Self.countQuery(filter: "archived = false"),
            token: token
        )
        async let tasks: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/board_tasks/records",
            method: "GET",
            queryItems: Self.countQuery(filter: openTaskFilter),
            token: token
        )
        async let events: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/calendar_events/records",
            method: "GET",
            queryItems: Self.countQuery(
                filter: "start_at >= \"\(nowValue)\" && start_at < \"\(nextWeekValue)\""
            ),
            token: token
        )
        async let upcomingTasks: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/board_tasks/records",
            method: "GET",
            queryItems: Self.countQuery(
                filter: "\(openTaskFilter) && due_date >= \"\(nowValue)\" && due_date < \"\(nextWeekValue)\""
            ),
            token: token
        )
        async let reading: RecordListResponse<RecordIDOnly> = send(
            path: "/api/collections/reading_items/records",
            method: "GET",
            queryItems: Self.countQuery(filter: "status = \"unread\""),
            token: token
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
        async let statesRequest: [BoardStateRecord] = listAllRecords(
            collection: "board_project_states",
            filter: filter,
            sort: "sort_order",
            token: token
        )
        async let tasksRequest: [BoardTaskRecord] = listAllRecords(
            collection: "board_tasks",
            filter: filter,
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

        let projects = Self.assembleBoardProjects(
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
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "sort", value: sort),
            ]
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

    private static func assembleBoardProjects(
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
            let owner = BoardMember(
                id: project.owner,
                name: project.expand?.owner?.displayName ?? "Project owner"
            )
            membersByProject[project.id, default: []].append(owner)
            membersByUserID[owner.id] = owner
        }
        for record in members {
            let member = BoardMember(
                id: record.user,
                name: record.expand?.user?.displayName ?? "Unknown member"
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
                dueDate: boardDate(record.dueDate),
                labels: record.labelIDs.compactMap { labelsByID[$0] },
                assignees: record.assigneeIDs.map {
                    membersByUserID[$0] ?? BoardMember(id: $0, name: "Unknown member")
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
        token: String? = nil
    ) async throws -> T {
        let data = try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            contentType: contentType,
            token: token
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
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
        token: String? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw APIError.invalidResponse }

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
        return data
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
