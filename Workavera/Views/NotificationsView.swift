import SwiftUI

struct NotificationsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications
    @State private var deleteTarget: AppNotification?
    @State private var showDeleteConfirmation = false
    @State private var selectedNotification: AppNotification?
    @State private var searchInput = ""

    var body: some View {
        CachedContentView(
            isLoading: notifications.isLoading,
            hasLoaded: notifications.hasLoaded,
            loadingTitle: "Loading notifications…"
        ) {
            notificationList
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Notifications")
        .searchable(
            text: $searchInput,
            prompt: "Search notifications"
        )
        .onSubmit(of: .search) {
            Task { await notifications.search(searchInput, using: auth) }
        }
        .onChange(of: searchInput) { oldValue, newValue in
            if !oldValue.isEmpty, newValue.isEmpty, !notifications.query.isEmpty {
                Task { await notifications.search("", using: auth) }
            }
        }
        .toolbar {
            if notifications.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark All Read") {
                        Task { await notifications.markAllRead(using: auth) }
                    }
                }
            }
        }
        .alert(
            "Delete Notification?",
            isPresented: $showDeleteConfirmation,
            presenting: deleteTarget
        ) { notification in
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
            Button("Delete", role: .destructive) {
                Task { await notifications.delete(notification, using: auth) }
                deleteTarget = nil
            }
        } message: { _ in
            Text("This notification will be permanently deleted. This action cannot be undone.")
        }
        .task(id: auth.user?.id) {
            await notifications.loadAutomatically(using: auth)
            searchInput = notifications.query
        }
        .sheet(item: $selectedNotification) { notification in
            NotificationDetailSheet(notification: notification)
        }
    }

    private var notificationList: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let errorMessage = notifications.errorMessage {
                    InlineErrorBanner(message: errorMessage) {
                        Task { await notifications.refresh(using: auth) }
                    }
                }

                if notifications.items.isEmpty {
                    ContentUnavailableView {
                        Label("No Notifications", systemImage: "bell.slash")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if notifications.query.isEmpty {
                            Button("Refresh") {
                                Task { await notifications.refresh(using: auth) }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Clear Search") {
                                clearSearch()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(notifications.items) { notification in
                            row(notification)
                        }
                    }
                }

                notificationPagination
            }
            .padding(20)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await notifications.refresh(using: auth)
        }
    }

    private var emptyDescription: String {
        if notifications.query.isEmpty {
            return "New task reminders, calendar events, and model shares will appear here."
        }
        return "No notifications match “\(notifications.query)”."
    }

    @ViewBuilder
    private var notificationPagination: some View {
        if notifications.hasLoaded, notifications.totalItems > 0 {
            ListPaginationFooter(
                pageCount: notifications.totalPages,
                page: pageBinding
            )
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
    }

    private func clearSearch() {
        searchInput = ""
        Task { await notifications.search("", using: auth) }
    }

    private func row(_ notification: AppNotification) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    // Opening a notification reads it, same as before, and now
                    // also shows the full text the row can only truncate.
                    Task { await notifications.markRead(notification, using: auth) }
                    selectedNotification = notification
                } label: {
                    notificationContent(notification)
                }
                .buttonStyle(.plain)

                if notification.type == .modelShare {
                    modelShareActions(notification)
                        .padding(.leading, 50)
                }
            }

            if notifications.isManaging(id: notification.id) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 38)
            } else {
                notificationMenu(notification)
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func notificationContent(_ notification: AppNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notification.type.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    Color.accentColor.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    if !notification.isRead {
                        Circle()
                            .fill(.red)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if notification.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(notification.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func notificationMenu(_ notification: AppNotification) -> some View {
        Menu {
            Button {
                Task { await notifications.archive(notification, using: auth) }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                deleteTarget = notification
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
        }
        .disabled(notifications.isManaging(id: notification.id))
    }

    @ViewBuilder
    private func modelShareActions(_ notification: AppNotification) -> some View {
        let status = notification.data.shareStatus ?? .pending
        if status == .pending {
            VStack(alignment: .leading, spacing: 8) {
                if let modelName = notification.data.modelName {
                    Text(modelName)
                        .font(.caption.weight(.semibold))
                }
                if let senderName = notification.data.senderName {
                    Text("Shared by \(senderName). Accepting creates an independent model configuration.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button {
                        respond(to: notification, decision: .accept)
                    } label: {
                        Label("Accept", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        respond(to: notification, decision: .reject)
                    } label: {
                        Label("Reject", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .disabled(notifications.isRespondingToShare(id: notification.id))
            }
        } else {
            Label(
                status == .accepted ? "Model configuration added" : "Share invitation declined",
                systemImage: status == .accepted ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .accepted ? .green : .secondary)
        }
    }

    private func respond(to notification: AppNotification, decision: ModelShareDecision) {
        Task {
            await notifications.respondToModelShare(notification, decision: decision, using: auth)
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { notifications.page },
            set: { page in
                Task { await notifications.loadPage(page, using: auth) }
            }
        )
    }

}

// MARK: - Notification detail

/// The full text of one notification. The list row truncates title and body
/// to stay scannable; this sheet shows everything, plus the model-share
/// actions for invitations still waiting on a decision.
private struct NotificationDetailSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    let notification: AppNotification

    /// Reads the live copy from the store, so an accept or reject tapped here
    /// updates the status without reopening the sheet.
    private var current: AppNotification {
        notifications.items.first { $0.id == notification.id } ?? notification
    }

    private var typeLabel: String {
        switch current.type {
        case .modelShare: "Model Share"
        case .taskDue: "Task Reminder"
        case .calendarEvent: "Calendar Event"
        case .unknown: "Notification"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: current.type.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(current.type.color)
                            .frame(width: 38, height: 38)
                            .background(
                                current.type.color.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(typeLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(
                                current.createdAt.formatted(
                                    .dateTime.month(.abbreviated).day().year().hour().minute()
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        if current.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(current.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    if !current.body.isEmpty {
                        Text(current.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    if current.type == .modelShare {
                        modelShareSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var modelShareSection: some View {
        let status = current.data.shareStatus ?? .pending
        VStack(alignment: .leading, spacing: 10) {
            if let modelName = current.data.modelName {
                LabeledContent("Model", value: modelName)
            }
            if let senderName = current.data.senderName {
                LabeledContent("Shared by", value: senderName)
            }
            if status == .pending {
                Text("Accepting creates an independent model configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        respond(.accept)
                    } label: {
                        Label("Accept", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        respond(.reject)
                    } label: {
                        Label("Reject", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.regular)
                .disabled(notifications.isRespondingToShare(id: current.id))
            } else {
                Label(
                    status == .accepted ? "Model configuration added" : "Share invitation declined",
                    systemImage: status == .accepted ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status == .accepted ? .green : .secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func respond(_ decision: ModelShareDecision) {
        Task {
            await notifications.respondToModelShare(current, decision: decision, using: auth)
        }
    }
}
