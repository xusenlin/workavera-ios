import SwiftUI

struct NotificationsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(NotificationStore.self) private var notifications
    @State private var deleteTarget: AppNotification?
    @State private var showDeleteConfirmation = false

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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                PaginationBar(
                    pageCount: notifications.totalPages,
                    page: pageBinding,
                    alwaysVisible: true
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .background(Color(.systemGroupedBackground))
        }
        .task(id: auth.user?.id) {
            await notifications.loadAutomatically(using: auth)
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
                        Text("New task reminders, calendar events, and model shares will appear here.")
                    } actions: {
                        Button("Refresh") {
                            Task { await notifications.refresh(using: auth) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(notifications.items.enumerated()), id: \.element.id) { index, notification in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 62)
                            }
                            row(notification)
                        }
                    }
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.always)
        .refreshable {
            await notifications.refresh(using: auth)
        }
    }

    private func row(_ notification: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await notifications.markRead(notification, using: auth) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notification.type.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(notification.type.color)
                        .frame(width: 34, height: 34)
                        .background(notification.type.color.opacity(0.15), in: Circle())
                        .overlay(alignment: .topLeading) {
                            if !notification.isRead {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if notification.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(notification.title)
                                .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                                .foregroundStyle(.primary)
                        }
                        if !notification.body.isEmpty {
                            Text(notification.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(notification.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 30)

            if notification.type == .modelShare {
                modelShareActions(notification)
                    .padding(.leading, 46)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .topTrailing) {
            notificationMenu(notification)
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
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
                .frame(width: 30, height: 30)
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
