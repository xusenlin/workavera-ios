import SwiftUI

// MARK: - Add / edit server

struct MCPServerFormSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// `nil` means creating a new server.
    let server: MCPServer?
    let onSaved: (MCPServer) -> Void

    @State private var name: String
    @State private var slug: String
    @State private var url: String
    @State private var transport: MCPTransport
    @State private var approvalPolicy: MCPApprovalPolicy
    @State private var headersText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(server: MCPServer?, onSaved: @escaping (MCPServer) -> Void) {
        self.server = server
        self.onSaved = onSaved
        _name = State(initialValue: server?.name ?? "")
        _slug = State(initialValue: server?.slug ?? "")
        _url = State(initialValue: server?.url ?? "")
        _transport = State(initialValue: server?.transport ?? .http)
        _approvalPolicy = State(initialValue: server?.approvalPolicy ?? .writes)
    }

    private var isEditing: Bool { server != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Notion", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: name) {
                            if name.count > 100 { name = String(name.prefix(100)) }
                        }
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("e.g. notion", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isEditing)
                        .foregroundStyle(isEditing ? .secondary : .primary)
                        .onChange(of: slug) {
                            if slug.count > 20 { slug = String(slug.prefix(20)) }
                        }
                } header: {
                    Text("Tool Prefix")
                } footer: {
                    Text(
                        isEditing
                            ? "The prefix is fixed once tools exist, because changing it would rename every tool the assistant knows."
                            : "Tools appear to the assistant as mcp_\(slug.isEmpty ? "prefix" : slug)_toolname. Lowercase letters, digits, and underscores."
                    )
                }

                Section {
                    TextField("https://example.com/mcp", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Transport", selection: $transport) {
                        ForEach(MCPTransport.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } header: {
                    Text("Endpoint")
                }

                Section {
                    Picker(selection: $approvalPolicy) {
                        ForEach(MCPApprovalPolicy.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    } label: {
                        HStack {
                            Text("Policy")
                            Spacer()
                            Text(approvalPolicy.shortLabel)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Approval for Newly Found Tools")
                } footer: {
                    Text("\(approvalPolicy.hint) Only pre-selects tools found by a refresh; you can change each tool afterwards.")
                }

                Section {
                    TextEditor(text: $headersText)
                        .font(.callout.monospaced())
                        .frame(minHeight: 76)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(alignment: .topLeading) {
                            if headersText.isEmpty {
                                Text("Authorization: Bearer your-token")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Request Headers")
                } footer: {
                    Text(
                        isEditing
                            ? "One per line, written as “Name: value”. Leave empty to keep the stored credentials."
                            : "One per line, written as “Name: value”. These are your credentials for the upstream service, stored write-only."
                    )
                }

                Section {
                    Label(
                        isEditing
                            ? "Changing the endpoint or credentials does not touch the tools you already reviewed. Refresh afterwards if the server now offers something different."
                            : "Chat can use this server's tools after you refresh it and choose which tools to enable.",
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if isSaving {
                    Section { ProgressView("Saving…") }
                }
            }
            .navigationTitle(isEditing ? "Edit MCP Server" : "Add MCP Server")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { Task { await save() } }
                        .disabled(!isFormValid || isSaving)
                }
            }
            .alert("Could Not Save the Server", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return false }
        if !isEditing, trimmedSlug.isEmpty { return false }
        return true
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func parseHeaders() -> [String: String]? {
        var headers: [String: String] = [:]
        for line in headersText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let separator = trimmed.firstIndex(of: ":"), separator > trimmed.startIndex else {
                return nil
            }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    private func save() async {
        guard let headers = parseHeaders() else {
            errorMessage = "Each header must be written as “Name: value”."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: MCPServer
            if let server {
                var update = MCPServerUpdate()
                update.name = trimmedName
                update.url = trimmedURL
                update.transport = transport
                update.approvalPolicy = approvalPolicy
                // Credentials are write-only: an untouched field must leave the
                // stored headers alone rather than replacing them with nothing.
                if !headersText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    update.headers = headers
                }
                saved = try await auth.updateMCPServer(id: server.id, input: update)
            } else {
                saved = try await auth.createMCPServer(
                    input: MCPServerInput(
                        name: trimmedName,
                        slug: trimmedSlug,
                        transport: transport,
                        url: trimmedURL,
                        approvalPolicy: approvalPolicy,
                        headers: headers
                    )
                )
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tool review

struct MCPToolReviewSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(MCPServersStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let server: MCPServer

    @State private var tools: [MCPTool]
    @State private var report: MCPRefreshReport?
    @State private var refreshError: String
    @State private var isRefreshing = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(server: MCPServer) {
        self.server = server
        _tools = State(initialValue: server.tools)
        _refreshError = State(initialValue: server.lastError)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Button { Task { await refreshFromServer() } } label: {
                            Label(
                                isRefreshing ? "Refreshing…" : "Refresh from Server",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .disabled(isRefreshing || isSaving)

                        if let report, !report.removed.isEmpty {
                            Spacer()
                            Text("\(report.removed.count) removed upstream")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !refreshError.isEmpty {
                        Label(refreshError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let report, !report.unsupported.isEmpty {
                        Text("Not supported: \(report.unsupported.joined(separator: ", ")). Their input schemas use references Workavera cannot resolve.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    if tools.isEmpty {
                        Text("No tools loaded yet. Refresh to fetch them from the server.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(tools) { tool in
                            MCPToolReviewRow(
                                tool: tool,
                                status: status(for: tool),
                                onToggleEnabled: { enabled in
                                    update(tool.name, enabled: enabled)
                                },
                                onToggleApproval: { requires in
                                    update(tool.name, approval: requires ? .always : .never)
                                }
                            )
                        }
                    }
                } footer: {
                    Text("Only the tools you enable here are offered to Chat. Refreshing never enables anything on its own.")
                }
            }
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving || isRefreshing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving || isRefreshing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveSelection() } }
                        .disabled(tools.isEmpty || isSaving || isRefreshing)
                }
            }
            .alert("Could Not Save the Tool Selection", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Unknown error")
            }
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func status(for tool: MCPTool) -> String? {
        if report?.added.contains(tool.name) == true { return "New" }
        if report?.changed.contains(tool.name) == true { return "Changed" }
        if tool.stale { return "May be out of date" }
        return nil
    }

    private func update(_ toolName: String, enabled: Bool) {
        tools = tools.map { tool in
            guard tool.name == toolName else { return tool }
            return MCPTool(
                name: tool.name,
                description: tool.description,
                enabled: enabled,
                approval: tool.approval,
                stale: tool.stale
            )
        }
    }

    private func update(_ toolName: String, approval: MCPToolApproval) {
        tools = tools.map { tool in
            guard tool.name == toolName else { return tool }
            return MCPTool(
                name: tool.name,
                description: tool.description,
                enabled: tool.enabled,
                approval: approval,
                stale: tool.stale
            )
        }
    }

    private func refreshFromServer() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await auth.refreshMCPServer(id: server.id)
            // A failed refresh still writes last_error to the record, so the
            // list behind this sheet is stale either way and has to be updated.
            store.replace(response.server)
            guard response.ok else {
                refreshError = response.error ?? "Could not reach the server."
                return
            }
            refreshError = ""
            tools = response.server.tools
            report = response.report
        } catch {
            refreshError = error.localizedDescription
        }
    }

    private func saveSelection() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await auth.updateMCPServerTools(
                id: server.id,
                tools: tools.map {
                    MCPToolDecision(name: $0.name, enabled: $0.enabled, approval: $0.approval)
                }
            )
            store.replace(saved)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct MCPToolReviewRow: View {
    let tool: MCPTool
    let status: String?
    let onToggleEnabled: (Bool) -> Void
    let onToggleApproval: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(tool.name)
                            .font(.subheadline.monospaced())
                        if let status {
                            Text(status)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .textCase(.uppercase)
                        }
                    }
                    if !tool.description.isEmpty {
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Toggle("Enable \(tool.name)", isOn: Binding(
                    get: { tool.enabled },
                    set: onToggleEnabled
                ))
                .labelsHidden()
            }

            if tool.enabled {
                Toggle(isOn: Binding(
                    get: { tool.requiresApproval },
                    set: onToggleApproval
                )) {
                    Text("Ask before each call")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .tint(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
