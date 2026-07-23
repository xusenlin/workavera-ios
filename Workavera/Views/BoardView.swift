import SwiftUI

/// Mobile board layout: the current project card at the top opens project selection,
/// followed by status chips and full-width task cards. Task details replace drag-and-drop status changes.
struct BoardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var board
    @State private var selectedTask: BoardTask?
    @State private var showProjectSwitcher = false

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
        .task(id: auth.user?.id) {
            await board.loadForPresentation(using: auth)
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
        .sheet(item: $selectedTask) { task in
            if let project = selectedProject {
                TaskDetailSheet(
                    task: task,
                    states: project.states,
                    currentStateID: task.stateID,
                    onPriorityChange: { priority in
                        await board.updatePriority(of: task, to: priority, using: auth)
                    },
                    onDueDateChange: { dueDate in
                        await board.updateDueDate(of: task, to: dueDate, using: auth)
                    }
                ) { newStateID in
                    Task { await board.moveTask(task, to: newStateID, using: auth) }
                }
            }
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
                        Button {
                            selectedTask = task
                        } label: {
                            TaskCard(task: task)
                        }
                        .buttonStyle(.plain)
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
    let onDueDateChange: (Date?) async -> Bool
    let onMove: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priority: TaskPriority
    @State private var isUpdatingPriority = false
    @State private var dueDate: Date?
    @State private var draftDueDate: Date
    @State private var isUpdatingDueDate = false
    @State private var showDueDateEditor = false

    init(
        task: BoardTask,
        states: [BoardState],
        currentStateID: String?,
        onPriorityChange: @escaping (TaskPriority) async -> Bool,
        onDueDateChange: @escaping (Date?) async -> Bool,
        onMove: @escaping (String) -> Void
    ) {
        self.task = task
        self.states = states
        self.currentStateID = currentStateID
        self.onPriorityChange = onPriorityChange
        self.onDueDateChange = onDueDateChange
        self.onMove = onMove
        _priority = State(initialValue: task.priority)
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
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showDueDateEditor) {
            dueDateEditor
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
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveDueDate(_ newDueDate: Date?) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !task.labels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(task.labels) { label in
                        LabelChip(label: label)
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
        let hasMeta = task.priority != .none || task.dueDate != nil || task.documentCount > 0
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

                if let dueDate = task.dueDate {
                    Label(dueDate.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
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
