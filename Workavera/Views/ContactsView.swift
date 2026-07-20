import SwiftUI

/// 联系人页面：搜索 + 状态筛选，收藏置顶分组，点人查看详情（只读）。
/// 当前数据来自 Contact.sample，接入 API 后替换为真实数据（users + contact_favorites）。
struct ContactsView: View {
    @State private var contacts = Contact.sample
    @State private var query = ""
    @State private var statusFilter: UserStatus?
    @State private var selectedContact: Contact?

    private var filtered: [Contact] {
        contacts
            .filter { contact in
                if let statusFilter, contact.status != statusFilter { return false }
                guard !query.isEmpty else { return true }
                let lowered = query.lowercased()
                return contact.name.lowercased().contains(lowered)
                    || contact.email.lowercased().contains(lowered)
                    || (contact.title?.lowercased().contains(lowered) ?? false)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var favorites: [Contact] {
        filtered.filter(\.isFavorite)
    }

    private var others: [Contact] {
        filtered.filter { !$0.isFavorite }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                statusFilterPicker

                if filtered.isEmpty {
                    emptyState
                } else {
                    if !favorites.isEmpty {
                        contactSection(title: "Favorites", contacts: favorites)
                    }
                    if !others.isEmpty {
                        contactSection(title: "Everyone", contacts: others)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Contacts")
        .sheet(item: $selectedContact) { contact in
            ContactDetailSheet(
                contact: contact,
                isFavorite: binding(for: contact.id)
            )
        }
    }

    // MARK: - 搜索与筛选

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
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
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
            withAnimation(.easeInOut(duration: 0.15)) {
                statusFilter = value
            }
        } label: {
            HStack(spacing: 6) {
                if let value {
                    StatusDot(status: value)
                }
                Text(title)
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

    // MARK: - 联系人分组

    private var emptyState: some View {
        Text("No matching contacts")
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
    }

    private func contactSection(title: String, contacts: [Contact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)
                .padding(.horizontal, 20)

            LazyVStack(spacing: 0) {
                ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 82)
                    }
                    row(contact)
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, 20)
        }
    }

    private func row(_ contact: Contact) -> some View {
        Button {
            selectedContact = contact
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: nil, name: contact.name, size: 44)
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
                        Text(contact.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 收藏（本地数据，接入 API 后改为写 contact_favorites）

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { contacts.first { $0.id == id }?.isFavorite ?? false },
            set: { newValue in
                if let index = contacts.firstIndex(where: { $0.id == id }) {
                    contacts[index].isFavorite = newValue
                }
            }
        )
    }
}

// MARK: - 联系人详情（只读）

private struct ContactDetailSheet: View {
    let contact: Contact
    @Binding var isFavorite: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        AvatarView(url: nil, name: contact.name, size: 72)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(contact.status.color)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle().stroke(Color(.systemGroupedBackground), lineWidth: 3)
                                    )
                            }

                        VStack(spacing: 4) {
                            Text(contact.name)
                                .font(.title3.bold())
                            StatusBadge(status: contact.status)
                            if let title = contact.title {
                                Text(title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            isFavorite.toggle()
                        } label: {
                            Label(
                                isFavorite ? "Favorited" : "Add to Favorites",
                                systemImage: isFavorite ? "star.fill" : "star"
                            )
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(isFavorite ? .white : Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isFavorite ? Color.accentColor : Color.accentColor.opacity(0.15),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
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
                            Text("About")
                                .font(.headline)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
            Text(title)
                .font(.subheadline)
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
