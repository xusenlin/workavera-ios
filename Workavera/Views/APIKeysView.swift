import SwiftUI
import UIKit

struct APIKeysView: View {
    @Environment(AuthStore.self) private var auth
    @State private var keys: [WorkaveraAPIKey] = []
    @State private var isLoading = true
    @State private var isRevoking = false
    @State private var showCreateSheet = false
    @State private var revokeTarget: WorkaveraAPIKey?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && keys.isEmpty {
                ProgressView("Loading API keys…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if keys.isEmpty {
                ContentUnavailableView {
                    Label("No API Keys", systemImage: "key")
                } description: {
                    Text("Create a key to connect MCP clients such as Claude Code or Cursor.")
                } actions: {
                    Button("Create Key") { showCreateSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                keyList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create API key")
            }
        }
        .task { await loadKeys() }
        .sheet(isPresented: $showCreateSheet) {
            CreateAPIKeySheet(serverAddress: auth.serverAddress) {
                Task { await loadKeys() }
            }
        }
        .alert(
            "Revoke API key?",
            isPresented: revokePresented
        ) {
            if let revokeTarget {
                Button("Cancel", role: .cancel) { self.revokeTarget = nil }
                Button("Revoke \"\(revokeTarget.name)\"", role: .destructive) {
                    Task { await revoke(revokeTarget) }
                }
            }
        } message: {
            Text("The key will stop working immediately. Connected MCP clients will lose access.")
        }
        .alert("Could Not Update API Keys", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var keyList: some View {
        List {
            Section {
                ForEach(keys) { key in
                    APIKeyRow(key: key, isRevoking: isRevoking && revokeTarget?.id == key.id) {
                        revokeTarget = key
                    }
                }
            } header: {
                Text("MCP Access")
            } footer: {
                Text("Keys act on your behalf. The full secret is only shown once when created.")
            }
        }
        .refreshable { await loadKeys() }
    }

    private var revokePresented: Binding<Bool> {
        Binding(
            get: { revokeTarget != nil && !isRevoking },
            set: { if !$0 && !isRevoking { revokeTarget = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadKeys() async {
        if keys.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            keys = try await auth.loadAPIKeys()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ key: WorkaveraAPIKey) async {
        guard !isRevoking else { return }
        isRevoking = true
        do {
            try await auth.revokeAPIKey(id: key.id)
            keys.removeAll { $0.id == key.id }
            revokeTarget = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isRevoking = false
    }
}

private struct APIKeyRow: View {
    let key: WorkaveraAPIKey
    let isRevoking: Bool
    let onRevoke: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(key.name)
                        .font(.subheadline.weight(.semibold))
                    if key.allowsDestructiveActions {
                        Text("ALLOWS DELETION")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.1), in: Capsule())
                    }
                }
                Text("\(key.prefix)…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(expirationText)
                        .foregroundStyle(isExpired ? Color.red : Color.secondary.opacity(0.7))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(lastUsedText)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)
                .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button(role: .destructive, action: onRevoke) {
                if isRevoking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .disabled(isRevoking)
            .accessibilityLabel("Revoke \(key.name)")
        }
        .padding(.vertical, 5)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions.width
        }
    }

    private var isExpired: Bool {
        key.expiresAt.map { $0 <= .now } ?? false
    }

    private var expirationText: String {
        guard let expiresAt = key.expiresAt else { return "Never expires" }
        if isExpired { return "Expired \(expiresAt.formatted(date: .abbreviated, time: .omitted))" }
        return "Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var lastUsedText: String {
        guard let lastUsedAt = key.lastUsedAt else { return "Never used" }
        return "Last used \(lastUsedAt.formatted(.relative(presentation: .named)))"
    }
}

private struct CreateAPIKeySheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let serverAddress: String
    let onCreated: () -> Void

    @State private var name = ""
    @State private var expiration: APIKeyExpiration = .never
    @State private var allowsDestructiveActions = false
    @State private var isCreating = false
    @State private var createdKey: CreatedWorkaveraAPIKey?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let createdKey {
                    createdContent(createdKey)
                } else {
                    createForm
                }
            }
            .navigationTitle(createdKey == nil ? "Create API Key" : "Save API Key")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isCreating || createdKey != nil)
            .toolbar {
                if createdKey == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isCreating)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await create() } }
                            .disabled(trimmedName.isEmpty || isCreating)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .alert("Could Not Create API Key", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var createForm: some View {
        Form {
            Section {
                TextField("e.g. Claude Code on my laptop", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .onChange(of: name) {
                        if name.count > 100 { name = String(name.prefix(100)) }
                    }
                Picker("Expiration", selection: $expiration) {
                    ForEach(APIKeyExpiration.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Key Details")
            }

            Section {
                Toggle("Allow destructive actions", isOn: $allowsDestructiveActions)
                    .tint(.red)
            } footer: {
                Text("Allows MCP clients to delete tasks or calendar events without another confirmation.")
            }

            Section {
                Label(
                    "The full key is shown once. Workavera stores only its hash.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if isCreating {
                Section { ProgressView("Creating key…") }
            }
        }
    }

    private func createdContent(_ key: CreatedWorkaveraAPIKey) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("This is the only time the full key is shown.", systemImage: "exclamationmark.shield")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)

                copyCard(title: "API Key", value: key.key, message: "API key copied")
                copyCard(
                    title: "MCP Client Configuration",
                    value: mcpConfiguration(for: key.key),
                    message: "MCP configuration copied"
                )

                Text("Paste the configuration into `.mcp.json` for Claude Code or `mcp.json` for Cursor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func copyCard(title: String, value: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .font(.footnote.weight(.medium))
            }
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityHint(message)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func create() async {
        guard !trimmedName.isEmpty, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            createdKey = try await auth.createAPIKey(
                name: trimmedName,
                expiration: expiration,
                allowsDestructiveActions: allowsDestructiveActions
            )
            onCreated()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mcpConfiguration(for key: String) -> String {
        let base = serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let object: [String: Any] = [
            "mcpServers": [
                "workavera": [
                    "type": "http",
                    "url": "\(base)/api/mcp",
                    "headers": ["Authorization": "Bearer \(key)"],
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
