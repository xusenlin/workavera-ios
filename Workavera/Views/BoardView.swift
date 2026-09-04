import SwiftUI

/// Mobile board layout: the current project card at the top opens project selection,
/// followed by status chips and full-width task cards. Task details replace drag-and-drop status changes.
struct BoardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var board
    @State private var selectedTask: BoardTask?
    @State private var shareProject: BoardProject?
    @State private var showProjectSwitcher = false
    @State private var showArchivedTasks = false

    private var selectedProject: BoardProject? {
        board.projects.first { $0.id == board.selectedProjectID } ?? board.projects.first
    }

    private var selectedState: BoardState? {
        guard let project = selectedProject else { return nil }
        return project.states.first { $0.id == board.selectedStateID } ?? project.states.first
    }

    var body: some View {
        CachedContentView(
            isLoading: board.isLoading,
            hasLoaded: board.hasLoaded,
            loadingTitle: "Loading board…"
        ) {
            boardContent
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Board")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Only the owner may publish a project, matching the web app.
                if let project = selectedProject, project.ownerID == auth.user?.id {
                    let shared = board.shares[project.id] != nil
                    Button {
                        shareProject = project
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(shared ? Color.green : Color.accentColor)
                    }
                    .accessibilityLabel(shared ? "Shared publicly" : "Share project")
                }
                Button {
                    showArchivedTasks = true
                } label: {
                    Image(systemName: "archivebox")
                }
                .disabled(selectedProject == nil)
                .accessibilityLabel("Archived tasks")
            }
        }
        .task(id: auth.user?.id) {
            await board.loadForPresentation(using: auth)
        }
        // The icon reports that a project is public, so the share resolves
        // with the selected project rather than when the sheet opens.
        .task(id: selectedProject?.id) {
            guard let project = selectedProject,
                  project.ownerID == auth.user?.id,
                  !board.resolvedShareIDs.contains(project.id) else { return }
            try? await board.loadShare(projectID: project.id, using: auth)
        }
        .task(id: auth.user?.id) {
            await board.listenForRealtimeUpdates(using: auth)
        }
        .sheet(isPresented: $showProjectSwitcher) {
            ProjectSwitcherSheet(
                projects: board.projects,
                selectedID: selectedProject?.id,
                page: board.page,
                pageCount: board.totalPages,
                isLoading: board.isLoading,
                onPage: { page in
                    Task { await board.loadPage(page, using: auth) }
                }
            ) { project in
                withAnimation(.easeInOut(duration: 0.15)) {
                    board.selectProject(project)
                }
            }
        }
        .sheet(isPresented: $showArchivedTasks) {
            if let project = selectedProject {
                ArchivedTasksSheet(project: project)
            }
        }
        .sheet(item: $selectedTask) { task in
            if let project = selectedProject {
                TaskDetailSheet(
                    task: task,
                    states: project.states,
                    currentStateID: task.stateID,
                    onPriorityChange: { priority in
                        await board.updatePriority(of: task, to: priority, using: auth)
                    },
                    onStartDateChange: { startDate in
                        await board.updateStartDate(of: task, to: startDate, using: auth)
                    },
                    onDueDateChange: { dueDate in
                        await board.updateDueDate(of: task, to: dueDate, using: auth)
                    }
                ) { newStateID in
                    Task { await board.moveTask(task, to: newStateID, using: auth) }
                }
            }
        }
        .sheet(item: $shareProject) { project in
            ProjectShareSheet(project: project)
        }
    }

    private var boardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = board.errorMessage {
                    InlineErrorBanner(message: error) {
                        Task { await board.refresh(using: auth) }
                    }
                    .padding(.horizontal, 20)
                }

                if board.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "rectangle.split.3x1")
                    } description: {
                        Text("Create or join a project in Workavera to see it here.")
                    } actions: {
                        Button("Refresh") {
                            Task { await board.refresh(using: auth) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else if let project = selectedProject {
                    projectHeader(project)
                    statePicker(project)
                    taskList
                }
            }
            .padding(.vertical, 20)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await board.refresh(using: auth)
        }
    }

    // MARK: - Current project card (opens the project selection sheet)

    private func projectHeader(_ project: BoardProject) -> some View {
        Button {
            showProjectSwitcher = true
        } label: {
            ProjectCard(project: project, descriptionLines: 1) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Status selection

    private func statePicker(_ project: BoardProject) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.states) { state in
                    let isSelected = state.id == selectedState?.id
                    WorkspaceFilterChip(
                        title: state.name,
                        isSelected: isSelected,
                        dotColor: Color(hex: state.color),
                        count: state.tasks.count
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            board.selectState(state.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Task list

    @ViewBuilder
    private var taskList: some View {
        if let state = selectedState {
            if state.tasks.isEmpty {
                Text("No tasks in \(state.name)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .foregroundStyle(Color(.separator))
                    )
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(state.tasks) { task in
                        TaskCard(
                            task: task,
                            isUpdating: board.updatingTaskIDs.contains(task.id),
                            onArchive: state.id == selectedProject?.states.last?.id
                                ? { Task { await board.archiveTask(task, using: auth) } }
                                : nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTask = task
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

}

// MARK: - Project selection (card-list sheet)

private struct ProjectSwitcherSheet: View {
    let projects: [BoardProject]
    let selectedID: String?
    let page: Int
    let pageCount: Int
    let isLoading: Bool
    let onPage: (Int) -> Void
    let onSelect: (BoardProject) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("SWITCH PROJECT")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(projects) { project in
                            let isSelected = project.id == selectedID
                            Button {
                                onSelect(project)
                                dismiss()
                            } label: {
                                ProjectCard(project: project, isSelected: isSelected, descriptionLines: 2) {
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
                .overlay {
                    if isLoading {
                        ProgressView()
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                Divider()
                PaginationBar(
                    pageCount: max(1, pageCount),
                    page: pageBinding,
                    alwaysVisible: true
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium, .large])
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { page },
            set: { onPage($0) }
        )
    }
}

// MARK: - Archived tasks (list and restore for the current project)

private struct ArchivedTasksSheet: View {
    let project: BoardProject

    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var board

    var body: some View {
        NavigationStack {
            Group {
                if board.isLoadingArchived, !board.hasLoadedArchived {
                    ProgressView("Loading archived tasks…")
                } else if board.archivedTasks.isEmpty {
                    ContentUnavailableView(
                        "No Archived Tasks",
                        systemImage: "archivebox",
                        description: Text("Tasks you archive appear here.")
                    )
                } else {
                    ScrollView {
                        if let error = board.archivedErrorMessage {
                            InlineErrorBanner(message: error) {
                                Task { await load() }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(board.archivedTasks) { task in
                                row(task)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .refreshable { await load() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Archived Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Two-line inline title naming the project the list belongs to.
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Archived Tasks")
                            .font(.headline)
                        Text(project.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if board.hasLoadedArchived, board.archivedTotalItems > 0 {
                    VStack(spacing: 0) {
                        Divider()
                        PaginationBar(
                            pageCount: board.archivedTotalPages,
                            page: pageBinding,
                            alwaysVisible: true
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .background(.bar)
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ task: ArchivedBoardTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if board.restoringTaskIDs.contains(task.id) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30, height: 30)
            } else {
                Button {
                    Task { await board.restoreTask(task, using: auth) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!board.restoringTaskIDs.isEmpty)
                .accessibilityLabel("Restore \(task.title)")
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    /// The state a restored task returns to, plus its description when it has one.
    private func subtitle(for task: ArchivedBoardTask) -> String {
        let state = task.stateName.isEmpty ? "Original state" : task.stateName
        return task.description.isEmpty ? state : "\(state) · \(task.description)"
    }

    private func load(page: Int? = nil) async {
        await board.loadArchivedTasks(for: project.id, page: page, using: auth)
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { board.archivedPage },
            set: { page in
                Task { await load(page: page) }
            }
        )
    }
}

// MARK: - Project card (shared by the header and selection list)

private struct ProjectCard<Accessory: View>: View {
    let project: BoardProject
    var isSelected = false
    var descriptionLines: Int = 1
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !project.description.isEmpty {
                        Text(project.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(descriptionLines)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                accessory
            }

            Divider()

            HStack(spacing: 16) {
                statItem(icon: "square.3.layers.3d", count: project.taskCount)
                statItem(icon: "tag", count: project.labelCount)
                statItem(icon: "person.2", count: project.members.count)
                Spacer()
                MemberStack(members: project.members, size: 22)
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
        )
    }

    private func statItem(icon: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Task details (information and status changes)

private struct TaskDetailSheet: View {
    let task: BoardTask
    let states: [BoardState]
    let currentStateID: String?
    let onPriorityChange: (TaskPriority) async -> Bool
    let onStartDateChange: (Date?) async -> Bool
    let onDueDateChange: (Date?) async -> Bool
    let onMove: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priority: TaskPriority
    @State private var isUpdatingPriority = false
    @State private var startDate: Date?
    @State private var draftStartDate: Date
    @State private var isUpdatingStartDate = false
    @State private var showStartDateEditor = false
    @State private var dueDate: Date?
    @State private var draftDueDate: Date
    @State private var isUpdatingDueDate = false
    @State private var showDueDateEditor = false

    init(
        task: BoardTask,
        states: [BoardState],
        currentStateID: String?,
        onPriorityChange: @escaping (TaskPriority) async -> Bool,
        onStartDateChange: @escaping (Date?) async -> Bool,
        onDueDateChange: @escaping (Date?) async -> Bool,
        onMove: @escaping (String) -> Void
    ) {
        self.task = task
        self.states = states
        self.currentStateID = currentStateID
        self.onPriorityChange = onPriorityChange
        self.onStartDateChange = onStartDateChange
        self.onDueDateChange = onDueDateChange
        self.onMove = onMove
        _priority = State(initialValue: task.priority)
        _startDate = State(initialValue: task.startDate)
        _draftStartDate = State(initialValue: task.startDate ?? .now)
        _dueDate = State(initialValue: task.dueDate)
        _draftDueDate = State(
            initialValue: task.dueDate
                ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)
                ?? .now
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !task.labels.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(task.labels) { label in
                                LabelChip(label: label)
                            }
                        }
                    }

                    if !task.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(task.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: 0) {
                        stateRow
                        Divider().padding(.leading, 54)
                        priorityRow
                        Divider().padding(.leading, 54)
                        startDateRow
                        Divider().padding(.leading, 54)
                        dueDateRow
                        if task.documentCount > 0 {
                            Divider().padding(.leading, 54)
                            infoRow(icon: "doc", title: "Documents") {
                                Text("\(task.documentCount)")
                            }
                        }
                        if !task.assignees.isEmpty {
                            Divider().padding(.leading, 54)
                            infoRow(icon: "person.2", title: "Assignees") {
                                Text(task.assignees.map(\.name).joined(separator: ", "))
                            }
                        }
                    }
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CopyInfoButton(
                        text: task.copyText,
                        accessibilityLabel: "Copy task ID and name"
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showStartDateEditor) {
            startDateEditor
        }
        .sheet(isPresented: $showDueDateEditor) {
            dueDateEditor
        }
    }

    private var startDateRow: some View {
        Button {
            draftStartDate = startDate ?? .now
            showStartDateEditor = true
        } label: {
            infoRow(icon: "calendar.badge.clock", title: "Start Date") {
                HStack(spacing: 5) {
                    if isUpdatingStartDate {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    if let startDate {
                        Text(
                            startDate.formatted(
                                .dateTime.month(.abbreviated).day().year()
                            )
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        Text("No start date")
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingStartDate)
    }

    private var startDateEditor: some View {
        NavigationStack {
            Form {
                // A start date is a day, not a moment: the web form picks
                // YYYY-MM-DD, so this picker leaves the time out too.
                DatePicker(
                    "Start date",
                    selection: $draftStartDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

                // The server rejects an inverted span; say so before a save
                // can fail on it.
                if !BoardTask.isValidSpan(start: draftStartDate, due: dueDate) {
                    Text("The start date cannot be after the due date.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if startDate != nil {
                    Button("Clear Start Date", role: .destructive) {
                        saveStartDate(nil)
                    }
                }
            }
            .navigationTitle("Start Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStartDateEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveStartDate(draftStartDate) }
                        .disabled(!BoardTask.isValidSpan(start: draftStartDate, due: dueDate))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveStartDate(_ newStartDate: Date?) {
        guard BoardTask.isValidSpan(start: newStartDate, due: dueDate) else { return }
        let previousStartDate = startDate
        startDate = newStartDate
        showStartDateEditor = false
        isUpdatingStartDate = true
        Task {
            if !(await onStartDateChange(newStartDate)) {
                startDate = previousStartDate
            }
            isUpdatingStartDate = false
        }
    }

    private var dueDateRow: some View {
        Button {
            draftDueDate = dueDate
                ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)
                ?? .now
            showDueDateEditor = true
        } label: {
            infoRow(icon: "calendar", title: "Due Date") {
                HStack(spacing: 5) {
                    if isUpdatingDueDate {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    if let dueDate {
                        Text(
                            dueDate.formatted(
                                .dateTime.month(.abbreviated).day().year().hour().minute()
                            )
                        )
                        .foregroundStyle(dueDate < .now ? .red : .secondary)
                    } else {
                        Text("No due date")
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingDueDate)
    }

    private var dueDateEditor: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Due date",
                    selection: $draftDueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)

                // A due date before the start date would render as a negative
                // span, which the server rejects.
                if !BoardTask.isValidSpan(start: startDate, due: draftDueDate) {
                    Text("The due date cannot be before the start date.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if dueDate != nil {
                    Button("Clear Due Date", role: .destructive) {
                        saveDueDate(nil)
                    }
                }
            }
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDueDateEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveDueDate(draftDueDate) }
                        .disabled(!BoardTask.isValidSpan(start: startDate, due: draftDueDate))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveDueDate(_ newDueDate: Date?) {
        guard BoardTask.isValidSpan(start: startDate, due: newDueDate) else { return }
        let previousDueDate = dueDate
        dueDate = newDueDate
        showDueDateEditor = false
        isUpdatingDueDate = true
        Task {
            if !(await onDueDateChange(newDueDate)) {
                dueDate = previousDueDate
            }
            isUpdatingDueDate = false
        }
    }

    private var priorityRow: some View {
        Menu {
            ForEach(TaskPriority.allCases) { option in
                Button {
                    guard option != priority, !isUpdatingPriority else { return }
                    let previousPriority = priority
                    priority = option
                    isUpdatingPriority = true
                    Task {
                        if !(await onPriorityChange(option)) {
                            priority = previousPriority
                        }
                        isUpdatingPriority = false
                    }
                } label: {
                    Label {
                        Text(option.label)
                    } icon: {
                        if option == priority {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            infoRow(icon: "flag", title: "Priority") {
                HStack(spacing: 5) {
                    if isUpdatingPriority {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Circle()
                            .fill(priority.color)
                            .frame(width: 6, height: 6)
                    }
                    Text(priority.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isUpdatingPriority)
    }

    /// Status row with a destination-state menu replacing drag-and-drop on mobile.
    private var stateRow: some View {
        Menu {
            ForEach(states) { state in
                Button {
                    guard state.id != currentStateID else { return }
                    onMove(state.id)
                    dismiss()
                } label: {
                    Label {
                        Text(state.name)
                    } icon: {
                        if state.id == currentStateID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            infoRow(icon: "rectangle.split.3x1", title: "Status") {
                HStack(spacing: 5) {
                    if let current = states.first(where: { $0.id == currentStateID }) {
                        Circle()
                            .fill(Color(hex: current.color))
                            .frame(width: 6, height: 6)
                        Text(current.name)
                    } else {
                        Text("—")
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func infoRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(title)
                .font(.subheadline)
            Spacer()
            value()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

// MARK: - Task card

private struct TaskCard: View {
    let task: BoardTask
    let isUpdating: Bool
    let onArchive: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !task.labels.isEmpty || onArchive != nil {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(task.labels) { label in
                            LabelChip(label: label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let onArchive {
                        Button(action: onArchive) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdating)
                        .accessibilityLabel("Archive \(task.title)")
                    }
                }
            }

            Text(task.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !task.description.isEmpty {
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    @ViewBuilder
    private var footer: some View {
        let hasMeta = task.priority != .none || task.dateSpanText != nil || task.documentCount > 0
        if hasMeta || !task.assignees.isEmpty {
            HStack(spacing: 10) {
                if task.priority != .none {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(task.priority.color)
                            .frame(width: 6, height: 6)
                        Text(task.priority.label)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                if let span = task.dateSpanText {
                    Label(span, systemImage: "calendar")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                }

                if task.documentCount > 0 {
                    Label("\(task.documentCount)", systemImage: "doc")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                MemberStack(members: task.assignees, size: 20)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Shared components

private struct CopyInfoButton: View {
    let text: String
    let accessibilityLabel: String

    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : accessibilityLabel)
        .accessibilityHint("Copies both fields to the clipboard")
    }

    private func copy() {
        UIPasteboard.general.string = text
        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) {
                copied = false
            }
        }
    }
}

private struct LabelChip: View {
    let label: BoardLabel

    var body: some View {
        Text(label.name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color(hex: label.color))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: label.color).opacity(0.15), in: Capsule())
    }
}

/// An overlapping avatar group showing at most max items, with +N for the remainder.
private struct MemberStack: View {
    let members: [BoardMember]
    var size: CGFloat = 24
    var max: Int = 3

    var body: some View {
        HStack(spacing: -(size * 0.3)) {
            ForEach(members.prefix(max)) { member in
                AvatarView(url: member.avatarURL, name: member.name, size: size)
                    .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
            }
            if members.count > max {
                ZStack {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                    Text("+\(members.count - max)")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
                .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
            }
        }
    }

    private var borderColor: Color {
        Color(.secondarySystemGroupedBackground)
    }
}

// MARK: - Project public link

/// Publishes a project to a public preview link (web app ShareProjectButton).
/// Unlike a shared document, the link pins nothing: the page always shows the
/// project as it stands, so there is no revision to republish — only an expiry
/// to set and a link to revoke.
private struct ProjectShareSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var board
    let project: BoardProject

    /// The store owns the link, so the toolbar behind this sheet reflects
    /// publishing and revoking without being told twice.
    private var share: BoardProjectShare? { board.shares[project.id] }
    private var hasLoaded: Bool { board.resolvedShareIDs.contains(project.id) }

    @State private var expiry: DocumentShareExpiry = .never
    @State private var chineseDates = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copied = false
    // Publishing roughly doubles the height of the sheet. Left at .medium it
    // would hide the link it just created below the fold, so the sheet grows
    // with what it has to show.
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        """
                        Anyone with the link sees this project as it stands \
                        right now, without signing in.
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label {
                        Text("Task titles and descriptions, states, labels, dates, and member names with their avatars.")
                    } icon: {
                        Image(systemName: "eye")
                    }
                    Label {
                        Text("Archived tasks, activity records, assignees, and member emails and roles stay private.")
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                } header: {
                    Text("What the link shows")
                } footer: {
                    Text("Archiving or deleting the project takes the link down immediately.")
                }
                .font(.footnote)

                if let errorMessage {
                    InlineErrorListSection(message: errorMessage) {
                        Task { await load() }
                    }
                }

                if !hasLoaded {
                    Section { ProgressView("Loading link…") }
                } else if let share {
                    linkSection(share)
                    expirySection
                    Section {
                        Button(role: .destructive) {
                            Task { await revoke() }
                        } label: {
                            Text("Revoke Link").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(isWorking)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    expirySection
                    Section {
                        Button {
                            Task { await publish(expiry: expiry) }
                        } label: {
                            Text(isWorking ? "Creating…" : "Create Link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWorking)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("Share Project")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    /// The language parameter only formats dates, so it belongs to the link
    /// the owner hands out rather than to the share record.
    private func linkURL(for share: BoardProjectShare) -> URL? {
        guard var url = auth.publicBoardURL(for: share) else { return nil }
        if chineseDates {
            url.append(queryItems: [URLQueryItem(name: "lang", value: "zh")])
        }
        return url
    }

    @ViewBuilder
    private func linkSection(_ share: BoardProjectShare) -> some View {
        Section("Public Link") {
            if let url = linkURL(for: share) {
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button {
                    copy(url)
                } label: {
                    Label(
                        copied ? "Copied" : "Copy Link",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
                }
                ShareLink(item: url) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                Link(destination: url) {
                    Label("Open Link", systemImage: "safari")
                }
                Toggle(isOn: $chineseDates) {
                    Text("Chinese date format (?lang=zh)")
                        .font(.footnote)
                }
            } else {
                Text("The server address could not be read.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var expirySection: some View {
        Section {
            Picker("Expires", selection: expirySelection) {
                ForEach(expiryOptions) { option in
                    Text(label(for: option)).tag(option)
                }
            }
            .disabled(isWorking)
        }
    }

    /// Changing the expiry of a published link takes effect at once, matching
    /// the web app; before there is a link it only stages the choice.
    private var expirySelection: Binding<DocumentShareExpiry> {
        Binding(get: { expiry }, set: { option in
            expiry = option
            if share != nil {
                Task { await publish(expiry: option) }
            }
        })
    }

    /// "Keep" is offered only for a link that already expires, so every other
    /// change to it leaves that date where the creator set it.
    private var expiryOptions: [DocumentShareExpiry] {
        DocumentShareExpiry.allCases.filter { $0 != .keep || share?.expiresAt != nil }
    }

    private func label(for option: DocumentShareExpiry) -> String {
        guard option == .keep, let expiresAt = share?.expiresAt else { return option.label }
        return "Keep \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
    }

    /// The label carries its own confirmation, the way the code-block copy
    /// button does: a sheet this small has nowhere to put a banner.
    private func copy(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }

    private func load() async {
        errorMessage = nil
        // The toolbar may already have resolved the link, so open at the right
        // size instead of growing once the refresh lands.
        syncToShare(animated: false)
        do {
            try await board.loadShare(projectID: project.id, using: auth)
            syncToShare()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publish(expiry option: DocumentShareExpiry) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await board.publishShare(
                projectID: project.id,
                expires: option.requestValue(share: share),
                using: auth
            )
            syncToShare()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await board.revokeShare(projectID: project.id, using: auth)
            syncToShare()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Brings the picker and the sheet's height in line with the link the
    /// store now holds.
    private func syncToShare(animated: Bool = true) {
        expiry = share?.expiresAt == nil ? .never : .keep
        let target: PresentationDetent = share == nil ? .medium : .large
        if animated {
            withAnimation { detent = target }
        } else {
            detent = target
        }
    }
}

private extension DocumentShareExpiry {
    /// Expiry for a board project share request; an empty string means the
    /// link never expires.
    func requestValue(share: BoardProjectShare?, now: Date = .now) -> String {
        if self == .keep { return share?.expires ?? "" }
        let days: Int
        switch self {
        case .never, .keep: return ""
        case .sevenDays: days = 7
        case .thirtyDays: days = 30
        }
        guard let date = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: days,
            to: now
        ) else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
