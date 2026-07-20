import SwiftUI

private func calendarText(
    _ date: Date,
    timezone: TimeZone,
    dateStyle: DateFormatter.Style = .none,
    timeStyle: DateFormatter.Style = .none,
    format: String? = nil
) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timezone
    if let format {
        formatter.dateFormat = format
    } else {
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
    }
    return formatter.string(from: date)
}

struct CalendarView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(CalendarStore.self) private var store

    @State private var displayedMonth = Date.now
    @State private var selectedDate = Date.now
    @State private var selectedItem: CalendarItem?
    @State private var editor: CalendarEditorContext?
    @State private var deletingEvent: AppEvent?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: store.timezone) ?? .current
        return calendar
    }

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView("Loading calendar…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        if let error = store.errorMessage {
                            errorBanner(error)
                        }
                        monthCard
                        agendaSection
                    }
                    .padding(20)
                }
                .refreshable { await store.refresh(using: auth) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = .new(on: selectedDate)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New event")
            }
        }
        .task(id: auth.user?.id) {
            await store.loadIfNeeded(using: auth)
            await store.listenForRealtimeUpdates(using: auth)
        }
        .sheet(item: $selectedItem) { item in
            switch item {
            case .event(let occurrence):
                EventDetailSheet(
                    occurrence: occurrence,
                    timezone: store.timezone,
                    isMutating: store.mutatingEventIDs.contains(occurrence.event.id),
                    onEdit: {
                        selectedItem = nil
                        editor = .edit(occurrence.event)
                    },
                    onDelete: {
                        selectedItem = nil
                        deletingEvent = occurrence.event
                    }
                )
            case .task(let task):
                TaskDeadlineSheet(task: task, timezone: store.timezone)
            }
        }
        .sheet(item: $editor) { context in
            CalendarEventEditorSheet(context: context, timezone: store.timezone) { input in
                let saved: AppEvent
                if let event = context.event {
                    saved = try await store.update(event, input: input, using: auth)
                } else {
                    saved = try await store.create(input, using: auth)
                }
                selectedDate = saved.startAt
                displayedMonth = saved.startAt
            }
        }
        .alert(
            deleteTitle,
            isPresented: deletePresented
        ) {
            Button("Cancel", role: .cancel) { deletingEvent = nil }
            Button("Delete Event", role: .destructive) {
                guard let event = deletingEvent else { return }
                Task {
                    _ = await store.delete(event, using: auth)
                    deletingEvent = nil
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var monthCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(monthText(displayedMonth))
                    .font(.headline)

                Spacer()

                if !calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month) {
                    Button("Today") {
                        withAnimation(.easeInOut(duration: 0.2)) { goToToday() }
                    }
                    .font(.footnote.weight(.medium))
                }

                HStack(spacing: 4) {
                    monthButton(icon: "chevron.left", offset: -1)
                    monthButton(icon: "chevron.right", offset: 1)
                }
            }

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthDays: [Date?] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        days.append(contentsOf: range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: first)
        })
        return days
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dayItems = items(on: date)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedDate = date }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isToday || isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }

                HStack(spacing: 3) {
                    ForEach(dayItems.prefix(3)) { item in
                        Circle()
                            .fill(item.tint)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthButton(icon: String, offset: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = calendar.date(
                    byAdding: .month,
                    value: offset,
                    to: displayedMonth
                ) ?? displayedMonth
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
    }

    private func goToToday() {
        displayedMonth = .now
        selectedDate = .now
    }

    private enum CalendarItem: Identifiable {
        case event(AppEventOccurrence)
        case task(CalendarTaskDeadline)

        var id: String {
            switch self {
            case .event(let occurrence): "event-\(occurrence.id)"
            case .task(let task): "task-\(task.id)"
            }
        }

        var title: String {
            switch self {
            case .event(let occurrence): occurrence.event.title
            case .task(let task): task.title
            }
        }

        var tint: Color {
            switch self {
            case .event(let occurrence): occurrence.event.color.color
            case .task(let task): task.priority.calendarColor
            }
        }

        var icon: String {
            switch self {
            case .event: "calendar"
            case .task: "checkmark.square"
            }
        }

        var itemDescription: String {
            switch self {
            case .event(let occurrence): occurrence.event.description
            case .task(let task): task.description
            }
        }

        var isAllDay: Bool {
            switch self {
            case .event(let occurrence): occurrence.event.allDay
            case .task: true
            }
        }

        var sortDate: Date {
            switch self {
            case .event(let occurrence): occurrence.startAt
            case .task: .distantPast
            }
        }

        var isCompletedTask: Bool {
            if case .task(let task) = self { return task.completed }
            return false
        }
    }

    private func items(on date: Date) -> [CalendarItem] {
        let eventItems = store.events.flatMap {
            $0.occurrences(overlapping: date, calendar: calendar)
        }.map(CalendarItem.event)
        let dayKey = CalendarDate.dayKey(for: date, timezone: store.timezone)
        let taskItems = store.tasks
            .filter { $0.dueDate == dayKey }
            .map(CalendarItem.task)

        return (eventItems + taskItems).sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.sortDate < $1.sortDate
        }
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayHeading(selectedDate))
                    .font(.headline)
                Spacer()
                if !selectedDayItems.isEmpty {
                    Text("\(selectedDayItems.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if selectedDayItems.isEmpty {
                Text("No events or due tasks")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .foregroundStyle(Color(.separator))
                    )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(selectedDayItems) { item in
                        itemRow(item)
                    }
                }
            }
        }
    }

    private var selectedDayItems: [CalendarItem] { items(on: selectedDate) }

    private func itemRow(_ item: CalendarItem) -> some View {
        Button { selectedItem = item } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.tint)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(item.tint)
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if case .task(let task) = item, task.priority != .none {
                            priorityBadge(task.priority)
                        }
                    }

                    metaLine(item)

                    if !item.itemDescription.isEmpty {
                        Text(item.itemDescription)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .opacity(item.isCompletedTask ? 0.65 : 1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func metaLine(_ item: CalendarItem) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .event(let occurrence):
                Label(eventTime(occurrence), systemImage: "clock")
                if !occurrence.event.location.isEmpty {
                    Label(occurrence.event.location, systemImage: "mappin")
                }
            case .task(let task):
                Label(task.projectName, systemImage: "square.3.layers.3d")
                if task.completed {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Due", systemImage: "clock")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func priorityBadge(_ priority: TaskPriority) -> some View {
        Text(priority.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(priority.calendarColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priority.calendarColor.opacity(0.15), in: Capsule())
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { store.clearError() }
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deletingEvent != nil },
            set: { if !$0 { deletingEvent = nil } }
        )
    }

    private var deleteTitle: String {
        deletingEvent?.recurrenceFrequency == EventRecurrenceFrequency.none
            ? "Delete event?"
            : "Delete repeating event?"
    }

    private var deleteMessage: String {
        deletingEvent?.recurrenceFrequency == EventRecurrenceFrequency.none
            ? "This event will be permanently removed."
            : "This permanently removes the entire repeating series."
    }

    private func monthText(_ date: Date) -> String {
        calendarText(date, timezone: calendar.timeZone, format: "LLLL yyyy")
    }

    private func dayHeading(_ date: Date) -> String {
        calendarText(date, timezone: calendar.timeZone, format: "EEEE, MMM d")
    }

    private func eventTime(_ occurrence: AppEventOccurrence) -> String {
        guard !occurrence.event.allDay else { return "All day" }
        let start = calendarText(occurrence.startAt, timezone: calendar.timeZone, timeStyle: .short)
        let end = calendarText(occurrence.endAt, timezone: calendar.timeZone, timeStyle: .short)
        return "\(start) – \(end)"
    }
}

private extension TaskPriority {
    var calendarColor: Color {
        switch self {
        case .none, .low: EventColor.blue.color
        case .medium, .high: EventColor.amber.color
        case .urgent: EventColor.red.color
        }
    }
}

private struct CalendarEditorContext: Identifiable {
    let id: String
    let event: AppEvent?
    let defaultDate: Date

    static func new(on date: Date) -> Self {
        .init(id: UUID().uuidString, event: nil, defaultDate: date)
    }

    static func edit(_ event: AppEvent) -> Self {
        .init(id: event.id, event: event, defaultDate: event.startAt)
    }
}

private struct EventDetailSheet: View {
    let occurrence: AppEventOccurrence
    let timezone: String
    let isMutating: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var event: AppEvent { occurrence.event }
    private var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(event.color.color)
                            .frame(width: 38, height: 38)
                            .background(event.color.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        Text(event.title)
                            .font(.title3.bold())
                    }

                    VStack(spacing: 0) {
                        detailRow(icon: "clock", title: "Time", value: timeText)
                        Divider().padding(.leading, 54)
                        detailRow(icon: "calendar", title: "Date", value: dateText)
                        if !event.location.isEmpty {
                            Divider().padding(.leading, 54)
                            detailRow(icon: "mappin", title: "Location", value: event.location)
                        }
                        if event.recurrenceFrequency != .none {
                            Divider().padding(.leading, 54)
                            detailRow(icon: "repeat", title: "Repeats", value: recurrenceText)
                        }
                        if event.reminder != .none {
                            Divider().padding(.leading, 54)
                            detailRow(icon: "bell", title: "Reminder", value: event.reminder.label)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    if !event.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes").font(.headline)
                            Text(event.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isMutating { ProgressView().controlSize(.small) }
                    Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                        .disabled(isMutating)
                        .accessibilityLabel("Edit event")
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                        .disabled(isMutating)
                        .accessibilityLabel("Delete event")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var timeText: String {
        guard !event.allDay else { return "All day" }
        let start = calendarText(occurrence.startAt, timezone: timeZone, timeStyle: .short)
        let end = calendarText(occurrence.endAt, timezone: timeZone, timeStyle: .short)
        return "\(start) – \(end)"
    }

    private var dateText: String {
        calendarText(occurrence.startAt, timezone: timeZone, dateStyle: .medium)
    }

    private var recurrenceText: String {
        event.recurrenceInterval == 1
            ? event.recurrenceFrequency.label
            : "Every \(event.recurrenceInterval) \(event.recurrenceFrequency.intervalUnit)s"
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }
}

private struct TaskDeadlineSheet: View {
    let task: CalendarTaskDeadline
    let timezone: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: task.completed ? "checkmark.square.fill" : "checkmark.square")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(task.priority.calendarColor)
                            .frame(width: 38, height: 38)
                            .background(task.priority.calendarColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        Text(task.title).font(.title3.bold())
                    }

                    VStack(spacing: 0) {
                        detailRow(icon: "square.3.layers.3d", title: "Project", value: task.projectName)
                        Divider().padding(.leading, 54)
                        detailRow(icon: "flag", title: "Priority", value: task.priority.label)
                        Divider().padding(.leading, 54)
                        detailRow(icon: "clock", title: "Due Date", value: dueDateText)
                        if task.completed {
                            Divider().padding(.leading, 54)
                            detailRow(icon: "checkmark.circle.fill", title: "Status", value: "Completed")
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    if !task.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description").font(.headline)
                            Text(task.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var dueDateText: String {
        let configuredTimeZone = TimeZone(identifier: timezone) ?? .current
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.calendar = Calendar(identifier: .gregorian)
        input.timeZone = configuredTimeZone
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: task.dueDate) else { return task.dueDate }
        return calendarText(date, timezone: configuredTimeZone, dateStyle: .medium)
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }
}

private struct CalendarEventEditorSheet: View {
    let context: CalendarEditorContext
    let timezone: String
    let onSave: (CalendarEventInput) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var eventDescription: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var allDay: Bool
    @State private var location: String
    @State private var color: EventColor
    @State private var recurrence: EventRecurrenceFrequency
    @State private var recurrenceInterval: Int
    @State private var reminder: EventReminder
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        context: CalendarEditorContext,
        timezone: String,
        onSave: @escaping (CalendarEventInput) async throws -> Void
    ) {
        self.context = context
        self.timezone = timezone
        self.onSave = onSave
        let event = context.event
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let defaultStart = event?.startAt
            ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: context.defaultDate)
            ?? context.defaultDate
        let defaultEnd = event?.endAt
            ?? calendar.date(byAdding: .hour, value: 1, to: defaultStart)
            ?? defaultStart.addingTimeInterval(3600)

        _title = State(initialValue: event?.title ?? "")
        _eventDescription = State(initialValue: event?.description ?? "")
        _date = State(initialValue: defaultStart)
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: defaultEnd)
        _allDay = State(initialValue: event?.allDay ?? false)
        _location = State(initialValue: event?.location ?? "")
        _color = State(initialValue: event?.color ?? .blue)
        _recurrence = State(initialValue: event?.recurrenceFrequency ?? .none)
        _recurrenceInterval = State(initialValue: event?.recurrenceInterval ?? 1)
        _reminder = State(initialValue: event?.reminder ?? .none)
    }

    private var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    var body: some View {
        NavigationStack {
            Form {
                if let event = context.event, event.recurrenceFrequency != .none {
                    Section {
                        Label("Changes apply to the entire repeating series.", systemImage: "repeat")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Event") {
                    TextField("Title", text: $title)
                        .onChange(of: title) { if title.count > 240 { title = String(title.prefix(240)) } }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("All day", isOn: $allDay)
                    if !allDay {
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Schedule") {
                    Picker("Repeat", selection: $recurrence) {
                        ForEach(EventRecurrenceFrequency.allCases) { frequency in
                            Text(frequency.label).tag(frequency)
                        }
                    }
                    if recurrence != .none {
                        Stepper(value: $recurrenceInterval, in: 1...999) {
                            Text("Every \(recurrenceInterval) \(recurrence.intervalUnit)\(recurrenceInterval == 1 ? "" : "s")")
                        }
                    }
                    Picker("Reminder", selection: $reminder) {
                        ForEach(EventReminder.allCases) { reminder in
                            Text(reminder.label).tag(reminder)
                        }
                    }
                }

                Section("Color") {
                    HStack(spacing: 16) {
                        ForEach(EventColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if color == option {
                                            Circle().stroke(Color.primary, lineWidth: 2)
                                                .padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use \(option.rawValue)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Details") {
                    TextField("Location", text: $location)
                        .onChange(of: location) {
                            if location.count > 500 { location = String(location.prefix(500)) }
                        }
                    TextEditor(text: $eventDescription)
                        .frame(minHeight: 100)
                        .onChange(of: eventDescription) {
                            if eventDescription.count > 10_000 {
                                eventDescription = String(eventDescription.prefix(10_000))
                            }
                        }
                }

                if isSaving {
                    Section { ProgressView("Saving event…") }
                }
            }
            .environment(\.timeZone, timeZone)
            .navigationTitle(context.event == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
            .alert("Could Not Save Event", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .presentationDetents([.large])
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() async {
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let start: Date
        let end: Date
        if allDay {
            start = calendar.startOfDay(for: date)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        } else {
            guard let combinedStart = combine(date: date, time: startTime, calendar: calendar),
                  let combinedEnd = combine(date: date, time: endTime, calendar: calendar),
                  combinedEnd > combinedStart else {
                errorMessage = "End time must be after start time."
                return
            }
            start = combinedStart
            end = combinedEnd
        }

        let input = CalendarEventInput(
            title: trimmedTitle,
            description: eventDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            startAt: start,
            endAt: end,
            allDay: allDay,
            timezone: timezone,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            recurrenceFrequency: recurrence,
            recurrenceInterval: max(1, recurrenceInterval),
            reminder: reminder
        )

        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func combine(date: Date, time: Date, calendar: Calendar) -> Date? {
        let dateParts = calendar.dateComponents([.year, .month, .day], from: date)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = dateParts.year
        components.month = dateParts.month
        components.day = dateParts.day
        components.hour = timeParts.hour
        components.minute = timeParts.minute
        return calendar.date(from: components)
    }
}
