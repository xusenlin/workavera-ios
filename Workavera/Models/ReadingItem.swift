import Foundation

/// 阅读条目（稍后读），字段对应后端 reading_items 集合。
struct ReadingItem: Identifiable, Equatable {
    let id: String
    var title: String
    var url: String
    var siteName: String
    var excerpt: String
    var author: String?
    var readingMinutes: Int
    var addedAt: Date
    var isArchived: Bool
    var isFavorite: Bool

    var host: String {
        URL(string: url)?.host() ?? siteName
    }
}

// MARK: - 布局示例数据（接入 API 前的占位数据）

extension ReadingItem {
    static let sample: [ReadingItem] = {
        func daysAgo(_ value: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -value, to: .now) ?? .now
        }

        return [
            ReadingItem(
                id: "r1",
                title: "Designing a Calm Kanban for Small Screens",
                url: "https://blog.example.com/calm-kanban",
                siteName: "Design Blog",
                excerpt: "Why horizontal columns fail on phones, and what to do instead: single-column lists, state switchers and progressive disclosure.",
                author: "Nora Fields",
                readingMinutes: 8,
                addedAt: daysAgo(0), isArchived: false, isFavorite: true
            ),
            ReadingItem(
                id: "r2",
                title: "Offline-First Sync Strategies",
                url: "https://engineering.example.com/offline-first",
                siteName: "Engineering Weekly",
                excerpt: "Mutation queues, optimistic updates and conflict resolution patterns that actually work in production.",
                author: nil,
                readingMinutes: 14,
                addedAt: daysAgo(1), isArchived: false, isFavorite: false
            ),
            ReadingItem(
                id: "r3",
                title: "SwiftUI Observation Framework Deep Dive",
                url: "https://swift.example.com/observation",
                siteName: "Swift Notes",
                excerpt: "How @Observable tracks access at the property level and what that means for view invalidation.",
                author: "Kenji Mori",
                readingMinutes: 11,
                addedAt: daysAgo(2), isArchived: false, isFavorite: true
            ),
            ReadingItem(
                id: "r4",
                title: "The Craft of Release Notes",
                url: "https://writing.example.com/release-notes",
                siteName: "Product Writing",
                excerpt: "Release notes are a product surface. Write them like you mean it.",
                author: nil,
                readingMinutes: 5,
                addedAt: daysAgo(4), isArchived: false, isFavorite: false
            ),
            ReadingItem(
                id: "r5",
                title: "PocketBase in Production: Lessons Learned",
                url: "https://backend.example.com/pocketbase",
                siteName: "Backend Journal",
                excerpt: "Migrations, hooks, realtime subscriptions and where the sharp edges are.",
                author: "Grace Liu",
                readingMinutes: 9,
                addedAt: daysAgo(6), isArchived: false, isFavorite: false
            ),
            ReadingItem(
                id: "r6",
                title: "Typography for Developer Tools",
                url: "https://design.example.com/dev-typography",
                siteName: "Design Blog",
                excerpt: "Monospace beyond code: numerals, alignment and legibility in dense UIs.",
                author: "Ada Chen",
                readingMinutes: 6,
                addedAt: daysAgo(8), isArchived: false, isFavorite: false
            ),
            ReadingItem(
                id: "r7",
                title: "A Field Guide to Empty States",
                url: "https://blog.example.com/empty-states",
                siteName: "UX Patterns",
                excerpt: "Empty states are onboarding moments. Use them well.",
                author: nil,
                readingMinutes: 4,
                addedAt: daysAgo(10), isArchived: true, isFavorite: false
            ),
            ReadingItem(
                id: "r8",
                title: "Mobile Navigation Patterns, Revisited",
                url: "https://ux.example.com/mobile-nav",
                siteName: "UX Patterns",
                excerpt: "Tabs, sheets and drill-ins — picking the right container for your content.",
                author: "Tom Becker",
                readingMinutes: 7,
                addedAt: daysAgo(12), isArchived: false, isFavorite: false
            ),
            ReadingItem(
                id: "r9",
                title: "SQLite Is All You Need (Sometimes)",
                url: "https://backend.example.com/sqlite",
                siteName: "Backend Journal",
                excerpt: "When a single-file database outperforms your distributed setup.",
                author: nil,
                readingMinutes: 12,
                addedAt: daysAgo(15), isArchived: true, isFavorite: true
            ),
            ReadingItem(
                id: "r10",
                title: "Making Friends with Date Formatters",
                url: "https://swift.example.com/dates",
                siteName: "Swift Notes",
                excerpt: "Relative dates, calendars and time zones without tears.",
                author: "Kenji Mori",
                readingMinutes: 6,
                addedAt: daysAgo(18), isArchived: false, isFavorite: false
            ),
        ]
    }()
}
