import SwiftUI

struct SavedMemoriesView: View {
    private static let limit = 50

    @Environment(AuthStore.self) private var auth
    @State private var memories: [SavedChatMemory] = []
    @State private var query = ""
    @State private var categoryFilter: MemoryCategory?
    @State private var isLoading = true
    @State private var mutatingIDs: Set<String> = []
    @State private var editor: MemoryEditorContext?
    @State private var deleteTarget: MemoryDeleteTarget?
    @State private var errorMessage: String?

    private var visibleMemories: [SavedChatMemory] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return memories.filter { memory in
            if let categoryFilter, memory.category != categoryFilter { return false }
            return normalized.isEmpty
                || memory.content.lowercased().contains(normalized)
                || memory.category.rawValue.contains(normalized)
        }
    }

    var body: some View {
        Group {
            if isLoading && memories.isEmpty {
                ProgressView("Loading memories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                memoryList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Saved Memories")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search memories")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("All Categories") { categoryFilter = nil }
                    Divider()
                    ForEach(MemoryCategory.allCases) { category in
                        Button {
                            categoryFilter = category
                        } label: {
                            Label(category.label, systemImage: category.icon)
                        }
                    }
                } label: {
                    Image(systemName: categoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter memories")

                Button {
                    editor = .new()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(memories.count >= Self.limit)
                .accessibilityLabel("Add memory")
            }
        }
        .task { await loadMemories() }
        .sheet(item: $editor) { context in
            MemoryEditorSheet(memory: context.memory) { saved in
                apply(saved)
            }
        }
        .alert(
            deleteTitle,
            isPresented: deletePresented
        ) {
            if let deleteTarget {
                Button("Cancel", role: .cancel) { self.deleteTarget = nil }
                Button(deleteButtonTitle, role: .destructive) {
                    Task { await delete(deleteTarget) }
                }
            }
        } message: {
            Text(deleteMessage)
        }
        .alert("Could Not Update Memories", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var memoryList: some View {
        List {
            if !auth.memoryEnabled {
                Section {
                    Label(
                        "Chat memory is currently disabled. You can still review and edit saved items.",
                        systemImage: "brain.head.profile"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                if visibleMemories.isEmpty {
                    ContentUnavailableView(
                        memories.isEmpty ? "No Saved Memories" : "No Memories Found",
                        systemImage: "brain.head.profile",
                        description: Text(
                            memories.isEmpty
                                ? "Add a memory here or ask Chat to remember something."
                                : "Try another search or category."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(visibleMemories) { memory in
                        SavedMemoryRow(
                            memory: memory,
                            isMutating: mutatingIDs.contains(memory.id),
                            onToggle: { active in
                                Task { await toggle(memory, active: active) }
                            },
                            onEdit: { editor = .edit(memory) },
                            onDelete: { deleteTarget = .one(memory) }
                        )
                    }
                }
            } header: {
                HStack {
                    Text(categoryFilter?.label ?? "All Memories")
                    Spacer()
                    Text("\(memories.count) of \(Self.limit)")
                }
            } footer: {
                if memories.count >= Self.limit {
                    Text("Delete an existing memory before adding another one.")
                        .foregroundStyle(.orange)
                }
            }

            if !memories.isEmpty {
                Section {
                    Button(role: .destructive) {
                        deleteTarget = .all
                    } label: {
                        Label("Delete All Memories", systemImage: "trash")
                    }
                }
            }
        }
        .refreshable { await loadMemories() }
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var deleteTitle: String {
        if case .all = deleteTarget { return "Delete all memories?" }
        return "Delete memory?"
    }

    private var deleteButtonTitle: String {
        if case .all = deleteTarget { return "Delete All" }
        return "Delete"
    }

    private var deleteMessage: String {
        if case .all = deleteTarget {
            return "Every saved Chat memory will be permanently removed."
        }
        return "This memory will be permanently removed and will no longer be available to Chat."
    }

    private func loadMemories() async {
        if memories.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            memories = try await auth.loadSavedMemories()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ memory: SavedChatMemory) {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
        memories.sort { $0.updatedAt > $1.updatedAt }
    }

    private func toggle(_ memory: SavedChatMemory, active: Bool) async {
        guard !mutatingIDs.contains(memory.id) else { return }
        mutatingIDs.insert(memory.id)
        defer { mutatingIDs.remove(memory.id) }
        do {
            apply(try await auth.setSavedMemoryActive(id: memory.id, active: active))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ target: MemoryDeleteTarget) async {
        switch target {
        case .one(let memory):
            mutatingIDs.insert(memory.id)
            defer { mutatingIDs.remove(memory.id) }
            do {
                try await auth.deleteSavedMemory(id: memory.id)
                memories.removeAll { $0.id == memory.id }
                deleteTarget = nil
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }

        case .all:
            let ids = memories.map(\.id)
            var failed = 0
            for id in ids {
                do {
                    try await auth.deleteSavedMemory(id: id)
                    memories.removeAll { $0.id == id }
                } catch {
                    failed += 1
                }
            }
            deleteTarget = nil
            if failed > 0 {
                await loadMemories()
                errorMessage = "Deleted \(ids.count - failed) memories, but \(failed) could not be removed."
            } else {
                errorMessage = nil
            }
        }
    }
}

private struct SavedMemoryRow: View {
    let memory: SavedChatMemory
    let isMutating: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(memory.category.label, systemImage: memory.category.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                Text(memory.origin.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if isMutating { ProgressView().controlSize(.small) }
                Toggle(
                    "",
                    isOn: Binding(
                        get: { memory.active },
                        set: onToggle
                    )
                )
                .labelsHidden()
                .controlSize(.small)
                .disabled(isMutating)
            }

            Text(memory.content)
                .font(.subheadline)
                .foregroundStyle(memory.active ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if memory.sourceConversationID != nil {
                    Label("From Chat", systemImage: "bubble.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(memory.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                .accessibilityLabel("Edit memory")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                .accessibilityLabel("Delete memory")
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MemoryEditorContext: Identifiable {
    let id: String
    let memory: SavedChatMemory?

    static func new() -> Self { .init(id: UUID().uuidString, memory: nil) }
    static func edit(_ memory: SavedChatMemory) -> Self { .init(id: memory.id, memory: memory) }
}

private enum MemoryDeleteTarget: Identifiable {
    case one(SavedChatMemory)
    case all

    var id: String {
        switch self {
        case .one(let memory): memory.id
        case .all: "all"
        }
    }
}

private struct MemoryEditorSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let memory: SavedChatMemory?
    let onSaved: (SavedChatMemory) -> Void

    @State private var category: MemoryCategory
    @State private var content: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(memory: SavedChatMemory?, onSaved: @escaping (SavedChatMemory) -> Void) {
        self.memory = memory
        self.onSaved = onSaved
        _category = State(initialValue: memory?.category ?? .preference)
        _content = State(initialValue: memory?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(MemoryCategory.allCases) { category in
                            Label(category.label, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 130)
                        .onChange(of: content) {
                            if content.count > 500 { content = String(content.prefix(500)) }
                        }
                } header: {
                    Text("Memory")
                } footer: {
                    HStack {
                        Text("One concise, durable fact.")
                        Spacer()
                        Text("\(content.count)/500")
                    }
                }

                if isSaving {
                    Section { ProgressView("Saving memory…") }
                }
            }
            .navigationTitle(memory == nil ? "New Memory" : "Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(trimmedContent.isEmpty || isSaving)
                }
            }
            .alert("Could Not Save Memory", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() async {
        guard !trimmedContent.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: SavedChatMemory
            if let memory {
                saved = try await auth.updateSavedMemory(
                    id: memory.id,
                    category: category,
                    content: trimmedContent
                )
            } else {
                saved = try await auth.createSavedMemory(
                    category: category,
                    content: trimmedContent
                )
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
