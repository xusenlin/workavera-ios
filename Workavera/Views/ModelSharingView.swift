import SwiftUI

struct ModelSharingView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(LLMSettingsStore.self) private var store

    @State private var selectedModelID: String?
    @State private var selectedUserIDs: Set<String> = []
    @State private var query = ""
    @State private var successMessage: String?

    private var selectedModel: LLMModelConfiguration? {
        store.shareableModels.first { $0.id == selectedModelID }
    }

    private var visibleTargets: [LLMShareTarget] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return store.shareTargets }
        return store.shareTargets.filter { $0.name.lowercased().contains(normalized) }
    }

    var body: some View {
        CachedContentView(
            isLoading: store.isLoadingModels,
            hasLoaded: store.hasLoadedModels,
            loadingTitle: "Loading sharing options…"
        ) {
            sharingForm
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Model Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search users")
        .task(id: auth.user?.id) { await load(refresh: false) }
        .alert("Invitation Sent", isPresented: successPresented) {
            Button("OK", role: .cancel) { successMessage = nil }
        } message: {
            Text(successMessage ?? "The invitation was sent.")
        }
    }

    private var sharingForm: some View {
        Form {
            if let errorMessage = store.errorMessage {
                InlineErrorListSection(message: errorMessage) {
                        Task { await load(refresh: true) }
                }
            }

            if store.shareableModels.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Models to Share", systemImage: "square.and.arrow.up")
                    } description: {
                        Text(
                            store.models.isEmpty
                                ? "Create a model configuration before sharing it."
                                : "Configurations received from another user cannot be shared onward."
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
            Section {
                Label(
                    "Recipients get a notification and may accept or reject it. Accepting creates an independent copy; the API key is never displayed.",
                    systemImage: "person.2"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Configuration", selection: $selectedModelID) {
                    ForEach(store.shareableModels) { model in
                        Text("\(model.name) · \(model.modelID)")
                            .tag(Optional(model.id))
                    }
                }
                .pickerStyle(.menu)

                if let selectedModel {
                    LabeledContent("Protocol", value: selectedModel.protocolType.label)
                    LabeledContent("Base URL") {
                        Text(selectedModel.baseURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Section {
                if store.isLoadingTargets && store.shareTargets.isEmpty {
                    ProgressView("Loading users…")
                } else if visibleTargets.isEmpty {
                    ContentUnavailableView(
                        store.shareTargets.isEmpty ? "No Other Users" : "No Users Found",
                        systemImage: "person.slash",
                        description: Text(
                            store.shareTargets.isEmpty
                                ? "There are no available recipients."
                                : "Try another search."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(visibleTargets) { target in
                        Button {
                            toggle(target.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedUserIDs.contains(target.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedUserIDs.contains(target.id) ? Color.accentColor : .secondary)
                                Text(target.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(String(target.id.suffix(6)))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("Recipients")
                    Spacer()
                    if !selectedUserIDs.isEmpty {
                        Text("\(selectedUserIDs.count) selected")
                    }
                }
            } footer: {
                Text("You can invite up to 100 users at once. Pending invitations are updated instead of duplicated.")
            }

            Section {
                Button {
                    Task { await share() }
                } label: {
                    HStack {
                        Spacer()
                        if store.isSharing {
                            ProgressView().controlSize(.small)
                        }
                        Text(shareButtonTitle)
                        Spacer()
                    }
                }
                .disabled(selectedModel == nil || selectedUserIDs.isEmpty || store.isSharing)
            }
            }
        }
        .refreshable { await load(refresh: true) }
    }

    private var shareButtonTitle: String {
        if store.isSharing { return "Sending Invitations…" }
        return "Share with \(selectedUserIDs.count) User\(selectedUserIDs.count == 1 ? "" : "s")"
    }

    private var successPresented: Binding<Bool> {
        Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )
    }

    private func load(refresh: Bool) async {
        if refresh {
            await store.refreshModels(using: auth)
            await store.loadShareTargets(using: auth)
        } else {
            await store.loadModelsForPresentation(using: auth)
            await store.loadShareTargetsForPresentation(using: auth)
        }
        if selectedModel == nil {
            selectedModelID = store.shareableModels.first?.id
        }
        let availableIDs = Set(store.shareTargets.map(\.id))
        selectedUserIDs.formIntersection(availableIDs)
    }

    private func toggle(_ id: String) {
        if selectedUserIDs.contains(id) {
            selectedUserIDs.remove(id)
        } else if selectedUserIDs.count < 100 {
            selectedUserIDs.insert(id)
        }
    }

    private func share() async {
        guard let selectedModel, !selectedUserIDs.isEmpty else { return }
        do {
            let count = try await store.share(
                model: selectedModel,
                userIDs: Array(selectedUserIDs).sorted(),
                using: auth
            )
            selectedUserIDs.removeAll()
            successMessage = "Share invitation sent to \(count) user\(count == 1 ? "" : "s")."
        } catch {
            // The shared store presents the server's field-safe error message.
        }
    }
}
