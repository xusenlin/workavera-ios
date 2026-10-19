import Foundation

/// Loads the agenda straight from the user's Workavera server, using the session
/// the app shared through `AgendaWidgetStore`. Mirrors the app's Calendar snapshot
/// request: personal events, open assigned task deadlines, and the server time zone.
enum AgendaWidgetFetcher {
    enum FetchError: Error {
        case signedOut
        case invalidResponse
    }

    private struct RecordList<Record: Decodable>: Decodable {
        let items: [Record]
        let totalPages: Int
    }

    private struct SystemConfig: Decodable {
        let timezone: String
    }

    /// Fetches a fresh snapshot and stores it for later renders.
    static func refresh() async throws -> AgendaWidgetSnapshot {
        guard let (session, token) = AgendaWidgetStore.loadSession() else { throw FetchError.signedOut }

        async let events: [AppEvent] = listAll(
            "calendar_events",
            filter: "",
            sort: "start_at",
            session: session,
            token: token
        )
        async let tasks: [CalendarTaskDeadline] = listAll(
            "board_tasks",
            filter: "state.category != \"completed\" && due_date != \"\" && archived = false && assignees.id ?= \"\(session.userID)\"",
            sort: "due_date",
            expand: "project,state",
            session: session,
            token: token
        )
        async let config: SystemConfig = get(
            "/api/configs/system",
            session: session,
            token: token
        )

        let (loadedEvents, loadedTasks, loadedConfig) = try await (events, tasks, config)
        let timezone = TimeZone(identifier: loadedConfig.timezone) == nil
            ? TimeZone.current.identifier
            : loadedConfig.timezone
        let normalizedEvents = loadedEvents.map { event in
            var event = event
            event.timezone = timezone
            return event
        }
        let snapshot = AgendaWidgetSnapshot(
            events: normalizedEvents,
            tasks: loadedTasks,
            timezone: timezone
        )
        AgendaWidgetStore.saveSnapshot(snapshot)
        return snapshot
    }

    private static func listAll<Record: Decodable>(
        _ collection: String,
        filter: String,
        sort: String,
        expand: String? = nil,
        session: AgendaWidgetStore.Session,
        token: String
    ) async throws -> [Record] {
        var page = 1
        var records: [Record] = []
        while true {
            var query = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: "200"),
                URLQueryItem(name: "sort", value: sort),
            ]
            if !filter.isEmpty { query.append(URLQueryItem(name: "filter", value: filter)) }
            if let expand { query.append(URLQueryItem(name: "expand", value: expand)) }
            let response: RecordList<Record> = try await get(
                "/api/collections/\(collection)/records",
                query: query,
                session: session,
                token: token
            )
            records.append(contentsOf: response.items)
            if page >= response.totalPages { return records }
            page += 1
        }
    }

    private static func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        session: AgendaWidgetStore.Session,
        token: String
    ) async throws -> T {
        var components = URLComponents(
            url: session.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw FetchError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw FetchError.signedOut }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
