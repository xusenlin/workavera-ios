import SwiftUI

/// 阅读页面（稍后读）：筛选（全部 / 收藏 / 已归档），列表 + 分页，
/// 支持收藏、归档、二次确认删除（均为本地示例数据操作），点条目查看详情。
/// 当前数据来自 ReadingItem.sample，接入 API 后替换为真实数据。
struct ReadingView: View {
    @State private var items = ReadingItem.sample
    @State private var filter: ReadingFilter = .all
    @State private var page = 0
    @State private var selectedItem: ReadingItem?
    @State private var itemToDelete: ReadingItem?

    private let pageSize = 6

    private enum ReadingFilter: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites"
        case archived = "Archived"
    }

    private var filtered: [ReadingItem] {
        items
            .filter { item in
                switch filter {
                case .all: !item.isArchived
                case .favorites: item.isFavorite && !item.isArchived
                case .archived: item.isArchived
                }
            }
            .sorted { $0.addedAt > $1.addedAt }
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(filtered.count) / Double(pageSize))))
    }

    private var pageItems: [ReadingItem] {
        Array(filtered.dropFirst(page * pageSize).prefix(pageSize))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterPicker
                itemList
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reading")
        .sheet(item: $selectedItem) { item in
            ReadingDetailSheet(item: item)
        }
        .confirmationDialog(
            "Remove this article?",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = itemToDelete {
                Button("Remove \"\(item.title)\"", role: .destructive) {
                    delete(item)
                }
                Button("Cancel", role: .cancel) {
                    itemToDelete = nil
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .safeAreaInset(edge: .bottom) {
            if pageCount > 1 {
                VStack(spacing: 0) {
                    Divider()
                    PaginationBar(pageCount: pageCount, page: $page)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    // MARK: - 筛选

    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(ReadingFilter.allCases, id: \.self) { value in
                let isSelected = filter == value
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        filter = value
                        page = 0
                    }
                } label: {
                    HStack(spacing: 6) {
                        switch value {
                        case .all:
                            Image(systemName: "book")
                        case .favorites:
                            Image(systemName: "star.fill")
                        case .archived:
                            Image(systemName: "archivebox")
                        }
                        Text(value.rawValue)
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
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 文章列表

    @ViewBuilder
    private var itemList: some View {
        if pageItems.isEmpty {
            Text("Nothing here yet")
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
        } else {
            LazyVStack(spacing: 12) {
                ForEach(pageItems) { item in
                    card(item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func card(_ item: ReadingItem) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedItem = item
            } label: {
                HStack(spacing: 12) {
                    Text(String(item.siteName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.accentColor.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color(hex: "#f59e0b"))
                            }
                        }

                        Text(item.excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Text(item.host)
                            Text("·")
                            Text("\(item.readingMinutes) min read")
                            Text("·")
                            Text(item.addedAt.formatted(.relative(presentation: .named)))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    toggleFavorite(item)
                } label: {
                    if item.isFavorite {
                        Label("Unfavorite", systemImage: "star.slash")
                    } else {
                        Label("Favorite", systemImage: "star")
                    }
                }

                Button {
                    toggleArchive(item)
                } label: {
                    if item.isArchived {
                        Label("Unarchive", systemImage: "archivebox")
                    } else {
                        Label("Archive", systemImage: "archivebox")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    itemToDelete = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - 本地数据操作（接入 API 后改为写后端）

    private func toggleFavorite(_ item: ReadingItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
    }

    private func toggleArchive(_ item: ReadingItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isArchived.toggle()
    }

    private func delete(_ item: ReadingItem) {
        items.removeAll { $0.id == item.id }
        itemToDelete = nil
    }
}

// MARK: - 文章详情（只读）

private struct ReadingDetailSheet: View {
    let item: ReadingItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.title3.bold())
                        HStack(spacing: 6) {
                            Text(item.host)
                            Text("·")
                            Text("\(item.readingMinutes) min read")
                            if let author = item.author {
                                Text("·")
                                Text(author)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)
                        Text(item.excerpt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        if let url = URL(string: item.url) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Original Article", systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
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
        .presentationDetents([.medium])
    }
}
