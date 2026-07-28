import SwiftUI

struct MCPServersView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(MCPServersStore.self) private var store
    @State private var editing: ServerEditing?
    @State private var reviewServer: MCPServer?
    @State private var deleteTarget: MCPServer?

    var body: some View {
        CachedContentView(
            isLoading: store.isLoading,
            hasLoaded: store.hasLoaded,
            loadingTitle: "Loading MCP servers…"
        ) {
            serverList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("MCP Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = ServerEditing(server: nil) } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add MCP server")
            }
        }
        .task { await store.loadForPresentation(using: auth) }
        .sheet(item: $editing) { value in
            MCPServerFormSheet(server: value.server) { saved in
                store.replace(saved)
            }
        }
        .sheet(item: $reviewServer) { server in
            MCPToolReviewSheet(server: server)
        }
        .alert(
            "Remove MCP server?",
            isPresented: deletePresented
        ) {
            if let deleteTarget {
                Button("Cancel", role: .cancel) { self.deleteTarget = nil }
                Button("Remove \"\(deleteTarget.name)\"", role: .destructive) {
                    Task {
                        _ = await store.delete(deleteTarget, using: auth)
                        self.deleteTarget = nil
                    }
                }
            }
        } message: {
            Text("The server and its stored credentials will be deleted. Chat will stop offering its tools immediately.")
        }
    }

    private var serverList: some View {
        List {
            if let errorMessage = store.errorMessage {
                InlineErrorListSection(message: errorMessage) {
                    Task { await store.refresh(using: auth) }
                }
            }

            Section {
                if store.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No MCP Servers", systemImage: "server.rack")
                    } description: {
                        Text("Add a server, refresh it, then choose which of its tools Chat may use.")
                    } actions: {
                        Button("Add Server") { editing = ServerEditing(server: nil) }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(store.servers) { server in
                        MCPServerRow(
                            server: server,
                            isMutating: store.mutatingServerIDs.contains(server.id),
                            onToggle: { enabled in
                                Task { _ = await store.setEnabled(enabled, serverID: server.id, using: auth) }
                            },
                            onManageTools: { reviewServer = server },
                            onEdit: { editing = ServerEditing(server: server) },
                            onDelete: { deleteTarget = server }
                        )
                    }
                }
            } header: {
                Text("Connected Servers")
            } footer: {
                Text("Servers and their credentials are private to your account. Only enabled tools from enabled servers are offered to Chat.")
            }
        }
        .refreshable { await store.refresh(using: auth) }
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { presented in
                if !presented, let deleteTarget,
                   !store.mutatingServerIDs.contains(deleteTarget.id) {
                    self.deleteTarget = nil
                }
            }
        )
    }
}

private struct ServerEditing: Identifiable {
    let server: MCPServer?

    var id: String { server?.id ?? "new" }
}

private enum MCPServerStatus {
    case connectionProblem
    case needsRefresh
    case noToolsLoaded
    case noToolsSelected
    case disabled
    case toolsEnabled(Int)

    init(server: MCPServer) {
        if !server.lastError.isEmpty {
            self = .connectionProblem
        } else if server.tools.contains(where: \.stale) {
            self = .needsRefresh
        } else if server.tools.isEmpty {
            self = .noToolsLoaded
        } else if server.enabledToolCount == 0 {
            self = .noToolsSelected
        } else if !server.enabled {
            self = .disabled
        } else {
            self = .toolsEnabled(server.enabledToolCount)
        }
    }

    var label: String {
        switch self {
        case .connectionProblem: "Connection problem"
        case .needsRefresh: "May need a refresh"
        case .noToolsLoaded: "No tools loaded"
        case .noToolsSelected: "No tools selected"
        case .disabled: "Disabled"
        case .toolsEnabled(let count): "\(count) tools enabled"
        }
    }

    var color: Color {
        switch self {
        case .connectionProblem: .red
        case .needsRefresh: .orange
        case .noToolsLoaded, .noToolsSelected, .disabled: .secondary
        case .toolsEnabled: .green
        }
    }
}

private struct MCPServerRow: View {
    let server: MCPServer
    let isMutating: Bool
    let onToggle: (Bool) -> Void
    let onManageTools: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.subheadline.weight(.semibold))
                        Text(status.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(status.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(status.color.opacity(0.12), in: Capsule())
                            .textCase(.uppercase)
                    }
                    Text(server.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Toggle(
                    "Enable server",
                    isOn: Binding(
                        get: { server.enabled && server.enabledToolCount > 0 },
                        set: onToggle
                    )
                )
                .labelsHidden()
                // Enabling means "offer this server's tools to Chat", which is
                // impossible until at least one tool is selected. A connection
                // failure is not auto-disabled: that would overwrite the user's
                // choice over what may be a temporary outage.
                .disabled(server.enabledToolCount == 0 || isMutating)
            }

            if !server.lastError.isEmpty {
                Text(server.lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            toolChips

            HStack(spacing: 16) {
                Button(action: onManageTools) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Manage tools for \(server.name)")
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Edit \(server.name)")
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Group {
                        if isMutating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .disabled(isMutating)
                .accessibilityLabel("Remove \(server.name)")
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    /// Shows which tools the server actually contributes. Only enabled tools
    /// are listed: the rest are not offered to Chat, so naming them would
    /// suggest a capability the assistant does not have.
    @ViewBuilder
    private var toolChips: some View {
        let enabled = server.tools.filter(\.enabled)
        if !enabled.isEmpty {
            let shown = enabled.prefix(8)
            let overflow = enabled.count - shown.count
            let idle = server.tools.count - enabled.count
            FlowRow(spacing: 4) {
                ForEach(shown) { tool in
                    HStack(spacing: 3) {
                        Text(tool.name)
                        if tool.requiresApproval {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tool.stale ? Color.orange : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        (tool.stale ? Color.orange : Color.secondary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .opacity(server.enabled ? 1 : 0.5)
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if idle > 0 {
                    Text("· \(idle) not enabled")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var status: MCPServerStatus {
        MCPServerStatus(server: server)
    }
}

/// A minimal wrapping layout for the tool chips, which vary in width and do
/// not fit a fixed grid.
private struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(
        in width: CGFloat,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
