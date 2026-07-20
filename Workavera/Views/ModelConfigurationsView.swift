import SwiftUI

struct ModelConfigurationsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(LLMSettingsStore.self) private var store

    @State private var editor: ModelEditorContext?
    @State private var deleteTarget: LLMModelConfiguration?

    var body: some View {
        Group {
            if store.isLoadingModels && !store.hasLoadedModels {
                ProgressView("Loading model configurations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.models.isEmpty {
                ContentUnavailableView {
                    Label("No Models Configured", systemImage: "sparkles")
                } description: {
                    Text("Add a model configuration to use Chat and AI features.")
                } actions: {
                    Button("Add Model") { editor = .new() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                modelList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Model Configurations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .new() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add model")
            }
        }
        .task { await store.refreshModels(using: auth) }
        .sheet(item: $editor) { context in
            ModelConfigurationEditor(context: context) { input in
                if let model = context.model {
                    try await store.update(model, input: input, using: auth)
                } else {
                    try await store.create(input, using: auth)
                }
            }
        }
        .alert("Delete model configuration?", isPresented: deletePresented) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                guard let model = deleteTarget else { return }
                Task {
                    _ = await store.delete(model, using: auth)
                    deleteTarget = nil
                }
            }
        } message: {
            Text(deleteMessage)
        }
        .alert("Could Not Update Models", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var modelList: some View {
        List {
            Section {
                ForEach(store.models) { model in
                    ModelConfigurationRow(
                        model: model,
                        isMutating: store.mutatingModelIDs.contains(model.id),
                        onSetDefault: { Task { await store.setDefault(model, using: auth) } },
                        onEdit: { editor = .edit(model) },
                        onDelete: { deleteTarget = model }
                    )
                }
            } header: {
                Text("Available to Your Account")
            } footer: {
                Text("Saved API keys are handled by protected server APIs and are never displayed again.")
            }
        }
        .refreshable { await store.refreshModels(using: auth) }
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.clearError() } }
        )
    }

    private var deleteMessage: String {
        guard let deleteTarget else { return "This model will be permanently removed." }
        return "“\(deleteTarget.name)” will be permanently removed. Copies previously shared with other users are not affected."
    }
}

private struct ModelConfigurationRow: View {
    let model: LLMModelConfiguration
    let isMutating: Bool
    let onSetDefault: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if model.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                    if model.hasAPIKey {
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("API key configured")
                    }
                    Spacer(minLength: 2)
                }

                Text("\(model.modelID) · \(model.baseURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(
                    "\(model.protocolType.label) · "
                        + "\(LLMTokenFormat.display(contextTokens)) · "
                        + LLMTokenFormat.display(outputTokens)
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

                if model.isSharedCopy {
                    Label(
                        "Shared by \(model.sharedFromName.isEmpty ? "another user" : model.sharedFromName)",
                        systemImage: "person.2"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if isMutating {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    if !model.isDefault {
                        Button(action: onSetDefault) {
                            Label("Set as Default", systemImage: "pin")
                        }
                    }
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, 5)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions.width
        }
    }

    private var outputTokens: Int {
        model.maxOutputTokens > 0 ? model.maxOutputTokens : 16_384
    }

    private var contextTokens: Int {
        model.maxContextTokens > 0 ? model.maxContextTokens : 256_000
    }
}

private struct ModelEditorContext: Identifiable {
    let id: String
    let model: LLMModelConfiguration?

    static func new() -> Self { .init(id: UUID().uuidString, model: nil) }
    static func edit(_ model: LLMModelConfiguration) -> Self { .init(id: model.id, model: model) }
}

private struct ModelConfigurationEditor: View {
    let context: ModelEditorContext
    let onSave: (LLMModelInput) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var modelID: String
    @State private var baseURL: String
    @State private var protocolType: LLMProtocol
    @State private var maxOutputTokens: String
    @State private var maxContextTokens: String
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var clearSavedKey = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        context: ModelEditorContext,
        onSave: @escaping (LLMModelInput) async throws -> Void
    ) {
        self.context = context
        self.onSave = onSave
        let model = context.model
        _name = State(initialValue: model?.name ?? "")
        _modelID = State(initialValue: model?.modelID ?? "")
        _baseURL = State(initialValue: model?.baseURL ?? LLMProtocol.openAI.defaultBaseURL)
        _protocolType = State(initialValue: model?.protocolType ?? .openAI)
        _maxOutputTokens = State(initialValue: String(
            model.map { $0.maxOutputTokens > 0 ? $0.maxOutputTokens : 16_384 } ?? 16_384
        ))
        _maxContextTokens = State(initialValue: String(
            model.map { $0.maxContextTokens > 0 ? $0.maxContextTokens : 256_000 } ?? 256_000
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let model = context.model, model.isSharedCopy {
                    Section {
                        Label(
                            "This is an independent copy shared by \(model.sharedFromName.isEmpty ? "another user" : model.sharedFromName). It cannot be shared onward.",
                            systemImage: "person.2"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Model") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { if name.count > 120 { name = String(name.prefix(120)) } }
                    TextField("Model ID", text: $modelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: modelID) {
                            if modelID.count > 255 { modelID = String(modelID.prefix(255)) }
                        }
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: baseURL) {
                            if baseURL.count > 2_048 { baseURL = String(baseURL.prefix(2_048)) }
                        }
                }

                Section("Protocol") {
                    Picker("Protocol", selection: $protocolType) {
                        ForEach(LLMProtocol.allCases) { item in
                            VStack(alignment: .leading) {
                                Text(item.label)
                                Text(item.details)
                            }
                            .tag(item)
                        }
                    }
                    .onChange(of: protocolType) { _, newValue in
                        let knownDefaults = Set(LLMProtocol.allCases.map(\.defaultBaseURL))
                        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || knownDefaults.contains(baseURL) {
                            baseURL = newValue.defaultBaseURL
                        }
                    }
                }

                Section {
                    HStack {
                        Group {
                            if showAPIKey {
                                TextField("Optional API key", text: $apiKey)
                            } else {
                                SecureField("Optional API key", text: $apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) {
                            if apiKey.count > 4_096 { apiKey = String(apiKey.prefix(4_096)) }
                            if !apiKey.isEmpty { clearSavedKey = false }
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showAPIKey ? "Hide API key" : "Show API key")
                    }

                    if context.model?.hasAPIKey == true {
                        Toggle("Remove saved key", isOn: $clearSavedKey)
                            .onChange(of: clearSavedKey) { _, clear in
                                if clear { apiKey = "" }
                            }
                    }
                } header: {
                    HStack {
                        Text("API Key")
                        if context.model?.hasAPIKey == true && !clearSavedKey {
                            Spacer()
                            Label("Configured", systemImage: "key.fill")
                        }
                    }
                } footer: {
                    Text(apiKeyFooter)
                }

                Section {
                    TextField("Max output tokens", text: $maxOutputTokens)
                        .textInputAutocapitalization(.never)
                    TextField("Max context tokens", text: $maxContextTokens)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Token Limits")
                } footer: {
                    Text("Examples: 16384, 256k, or 1m. Context is compacted when conversations approach the configured limit.")
                }

                if isSaving {
                    Section { ProgressView("Saving model…") }
                }
            }
            .navigationTitle(context.model == nil ? "Add Model" : "Edit Model")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || trimmedName.isEmpty || trimmedModelID.isEmpty)
                }
            }
            .alert("Could Not Save Model", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .presentationDetents([.large])
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModelID: String { modelID.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var apiKeyFooter: String {
        if context.model?.hasAPIKey == true {
            return clearSavedKey
                ? "The saved key will be removed when you save."
                : "Leave blank to keep the saved key, or enter a replacement."
        }
        return "The key is optional and will not be displayed after saving."
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() async {
        guard !isSaving else { return }
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedModelID.isEmpty, isValidBaseURL(trimmedBaseURL) else {
            errorMessage = "Name, model ID, and an absolute HTTP or HTTPS base URL are required."
            return
        }
        guard let output = parseTokens(maxOutputTokens), output > 0,
              let context = parseTokens(maxContextTokens), context > 0 else {
            errorMessage = "Token limits must be positive values such as 16k, 256k, or 1000000."
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyValue: String?
        if self.context.model == nil {
            keyValue = trimmedKey
        } else if clearSavedKey {
            keyValue = ""
        } else {
            keyValue = trimmedKey.isEmpty ? nil : trimmedKey
        }

        let input = LLMModelInput(
            name: trimmedName,
            modelID: trimmedModelID,
            baseURL: trimmedBaseURL,
            protocolType: protocolType,
            maxOutputTokens: output,
            maxContextTokens: context,
            apiKey: keyValue
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

    private func isValidBaseURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return components.host?.isEmpty == false
    }

    private func parseTokens(_ value: String) -> Int? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
        let multiplier: Double
        let number: String
        if normalized.hasSuffix("k") {
            multiplier = 1_000
            number = String(normalized.dropLast())
        } else if normalized.hasSuffix("m") {
            multiplier = 1_000_000
            number = String(normalized.dropLast())
        } else {
            multiplier = 1
            number = normalized
        }
        guard let parsed = Double(number), parsed.isFinite else { return nil }
        let result = parsed * multiplier
        guard result > 0, result <= Double(Int.max), result.rounded() == result else { return nil }
        return Int(result)
    }
}
