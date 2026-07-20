import SwiftUI

/// 看板页面（移动端布局）：顶部为当前项目卡片（点按切换项目），
/// 其下为状态 chips 切换 + 全宽任务卡片列表，拖拽移动以详情页内切换状态代替。
/// 当前数据来自 BoardProject.sample，接入 API 后替换为真实数据。
struct BoardView: View {
    @State private var projects = BoardProject.sample
    @State private var selectedProjectID: String?
    @State private var selectedStateID: String?
    @State private var selectedTask: BoardTask?
    @State private var showProjectSwitcher = false

    private var selectedProject: BoardProject? {
        projects.first { $0.id == selectedProjectID } ?? projects.first
    }

    private var selectedState: BoardState? {
        guard let project = selectedProject else { return nil }
        return project.states.first { $0.id == selectedStateID } ?? project.states.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let project = selectedProject {
                    projectHeader(project)
                    statePicker(project)
                    taskList
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Board")
        .sheet(isPresented: $showProjectSwitcher) {
            ProjectSwitcherSheet(
                projects: projects,
                selectedID: selectedProject?.id
            ) { project in
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedProjectID = project.id
                    selectedStateID = nil
                }
            }
        }
        .sheet(item: $selectedTask) { task in
            if let project = selectedProject {
                TaskDetailSheet(
                    task: task,
                    states: project.states,
                    currentStateID: stateID(of: task, in: project)
                ) { newStateID in
                    moveTask(task, to: newStateID)
                }
            }
        }
    }

    // MARK: - 当前项目卡片（点按弹出项目切换卡片列表）

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

    // MARK: - 状态切换

    private func statePicker(_ project: BoardProject) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(project.states) { state in
                    let isSelected = state.id == selectedState?.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedStateID = state.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: state.color))
                                .frame(width: 7, height: 7)
                            Text(state.name)
                            Text("\(state.tasks.count)")
                                .foregroundStyle(isSelected ? .primary : .tertiary)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - 任务列表

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

    // MARK: - 状态变更（本地数据，接入 API 后改为写后端）

    private func stateID(of task: BoardTask, in project: BoardProject) -> String? {
        project.states.first { $0.tasks.contains { $0.id == task.id } }?.id
    }

    private func moveTask(_ task: BoardTask, to stateID: String) {
        guard let p = projects.firstIndex(where: { $0.id == selectedProject?.id }),
              let from = projects[p].states.firstIndex(where: { $0.tasks.contains { $0.id == task.id } }),
              let t = projects[p].states[from].tasks.firstIndex(where: { $0.id == task.id }),
              let to = projects[p].states.firstIndex(where: { $0.id == stateID }),
              from != to else { return }
        let moved = projects[p].states[from].tasks.remove(at: t)
        projects[p].states[to].tasks.append(moved)
    }
}

// MARK: - 项目切换（卡片列表 sheet）

private struct ProjectSwitcherSheet: View {
    let projects: [BoardProject]
    let selectedID: String?
    let onSelect: (BoardProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// 移动端每页展示 2 个项目。
    private let pageSize = 2

    private var pageCount: Int {
        max(1, Int(ceil(Double(projects.count) / Double(pageSize))))
    }

    private var pageProjects: [BoardProject] {
        Array(projects.dropFirst(page * pageSize).prefix(pageSize))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(pageProjects) { project in
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

                if pageCount > 1 {
                    Divider()
                    PaginationBar(pageCount: pageCount, page: $page)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Switch Project")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 项目卡片（页头与切换列表共用）

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

// MARK: - 任务详情（查看信息 + 切换状态）

private struct TaskDetailSheet: View {
    let task: BoardTask
    let states: [BoardState]
    let currentStateID: String?
    let onMove: (String) -> Void

    @Environment(\.dismiss) private var dismiss

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
                        infoRow(icon: "flag", title: "Priority") {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(task.priority.color)
                                    .frame(width: 6, height: 6)
                                Text(task.priority.label)
                            }
                        }
                        if let dueDate = task.dueDate {
                            Divider().padding(.leading, 54)
                            infoRow(icon: "calendar", title: "Due Date") {
                                Text(dueDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                            }
                        }
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
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 状态行：菜单选择目标状态，代替移动端的拖拽移动。
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

// MARK: - 任务卡片

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

// MARK: - 通用小组件

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

/// 重叠头像组，最多展示 max 个，超出部分以 +N 表示。
private struct MemberStack: View {
    let members: [BoardMember]
    var size: CGFloat = 24
    var max: Int = 3

    var body: some View {
        HStack(spacing: -(size * 0.3)) {
            ForEach(members.prefix(max)) { member in
                AvatarView(url: nil, name: member.name, size: size)
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
