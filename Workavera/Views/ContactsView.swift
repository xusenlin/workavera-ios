import SwiftUI

struct ContactsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ContactsStore.self) private var store

    @State private var query = ""
    @State private var statusFilter: UserStatus?
    @State private var selection: ContactSelection?

    private var filtered: [Contact] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.contacts
            .filter { contact in
                if let statusFilter, contact.status != statusFilter { return false }
                guard !normalizedQuery.isEmpty else { return true }
                return contact.displayName.lowercased().contains(normalizedQuery)
                    || contact.email.lowercased().contains(normalizedQuery)
                    || (contact.title?.lowercased().contains(normalizedQuery) ?? false)
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    private var favorites: [Contact] { filtered.filter(\.isFavorite) }
    private var everyone: [Contact] { filtered.filter { !$0.isFavorite } }

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView("Loading contacts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = store.errorMessage {
                            errorBanner(error)
                        }
                        searchField
                        statusFilterPicker

                        if filtered.isEmpty {
                            emptyState
                        } else {
                            if !favorites.isEmpty {
                                contactSection(title: "Favorites", contacts: favorites)
                            }
                            if !everyone.isEmpty {
                                contactSection(title: "Everyone", contacts: everyone)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .refreshable { await store.refresh(using: auth) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Contacts")
        .task(id: auth.user?.id) {
            await store.loadIfNeeded(using: auth)
        }
        .sheet(item: $selection) { selection in
            ContactDetailSheet(contactID: selection.id)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
            TextField("Search name, email or title", text: $query)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, 20)
    }

    private var statusFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusChip(nil, title: "All")
                ForEach(UserStatus.allCases) { status in
                    statusChip(status, title: status.label)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func statusChip(_ value: UserStatus?, title: String) -> some View {
        let isSelected = statusFilter == value
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { statusFilter = value }
        } label: {
            HStack(spacing: 6) {
                if let value { StatusDot(status: value) }
                Text(title)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Contacts Found", systemImage: "person.2")
        } description: {
            Text(store.contacts.isEmpty ? "No other users are available." : "Try another search or status.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func contactSection(title: String, contacts: [Contact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 20)

            LazyVStack(spacing: 0) {
                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                    if index > 0 { Divider().padding(.leading, 72) }
                    contactRow(contact)
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 20)
        }
    }

    private func contactRow(_ contact: Contact) -> some View {
        Button { selection = ContactSelection(id: contact.id) } label: {
            HStack(spacing: 12) {
                AvatarView(url: contact.avatarURL, name: contact.displayName, size: 44)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(contact.status.color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2.5)
                            )
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(contact.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if contact.id == auth.user?.id {
                            Text("YOU")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        if contact.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#f59e0b"))
                        }
                    }
                    HStack(spacing: 5) {
                        Text(contact.status.label)
                        if let title = contact.title {
                            Text("·")
                            Text(title)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)
                if store.mutatingContactIDs.contains(contact.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry") { Task { await store.refresh(using: auth) } }
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
}

private struct ContactSelection: Identifiable {
    let id: String
}

private struct ContactDetailSheet: View {
    let contactID: String

    @Environment(AuthStore.self) private var auth
    @Environment(ContactsStore.self) private var store

    var body: some View {
        NavigationStack {
            if let contact = store.contact(id: contactID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(spacing: 10) {
                            AvatarView(url: contact.avatarURL, name: contact.displayName, size: 72)
                                .overlay(alignment: .bottomTrailing) {
                                    Circle()
                                        .fill(contact.status.color)
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle().stroke(Color(.systemGroupedBackground), lineWidth: 3)
                                        )
                                }

                            Text(contact.displayName).font(.title3.bold())
                            StatusBadge(status: contact.status)
                            if let title = contact.title {
                                Text(title).font(.footnote).foregroundStyle(.secondary)
                            }

                            if contact.id != auth.user?.id {
                                Button {
                                    Task { await store.toggleFavorite(contactID: contact.id, using: auth) }
                                } label: {
                                    if store.mutatingContactIDs.contains(contact.id) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label(
                                            contact.isFavorite ? "Favorited" : "Add to Favorites",
                                            systemImage: contact.isFavorite ? "star.fill" : "star"
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 0) {
                            infoRow(icon: "envelope", title: "Email", value: contact.email)
                            if let phone = contact.phone {
                                Divider().padding(.leading, 54)
                                infoRow(icon: "phone", title: "Phone", value: phone)
                            }
                        }
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )

                        if let bio = contact.bio {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About").font(.headline)
                                Text(bio)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(20)
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Contact Unavailable", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }
}
