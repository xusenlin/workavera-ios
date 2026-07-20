import Foundation

/// 联系人（工作区成员），字段对应后端 users 集合 + contact_favorites 的收藏关系。
struct Contact: Identifiable, Equatable {
    let id: String
    var name: String
    var email: String
    var phone: String?
    var title: String?
    var bio: String?
    var status: UserStatus
    var isFavorite: Bool
}

// MARK: - 布局示例数据（接入 API 前的占位数据）

extension Contact {
    static let sample: [Contact] = [
        Contact(
            id: "c1", name: "Ada Chen", email: "ada@workavera.dev",
            phone: "+86 138 0000 1024", title: "Product Designer",
            bio: "Design systems, typography and calm interfaces.",
            status: .online, isFavorite: true
        ),
        Contact(
            id: "c2", name: "Marco Li", email: "marco@workavera.dev",
            phone: nil, title: "iOS Engineer",
            bio: nil,
            status: .busy, isFavorite: true
        ),
        Contact(
            id: "c3", name: "Yuki Tanaka", email: "yuki@workavera.dev",
            phone: "+81 90 0000 2048", title: "Frontend Engineer",
            bio: "React and PocketBase. Coffee first.",
            status: .away, isFavorite: false
        ),
        Contact(
            id: "c4", name: "Priya Nair", email: "priya@workavera.dev",
            phone: nil, title: "Engineering Manager",
            bio: "Keeping the trains running on time.",
            status: .online, isFavorite: false
        ),
        Contact(
            id: "c5", name: "Tom Becker", email: "tom@workavera.dev",
            phone: "+49 170 0000 555", title: "QA Engineer",
            bio: nil,
            status: .offline, isFavorite: false
        ),
        Contact(
            id: "c6", name: "Lena Fischer", email: "lena@workavera.dev",
            phone: nil, title: "Content Strategist",
            bio: "Words for product and marketing.",
            status: .busy, isFavorite: false
        ),
        Contact(
            id: "c7", name: "Omar Haddad", email: "omar@workavera.dev",
            phone: nil, title: nil,
            bio: nil,
            status: .offline, isFavorite: false
        ),
        Contact(
            id: "c8", name: "Grace Liu", email: "grace@workavera.dev",
            phone: "+86 139 0000 8192", title: "Backend Engineer",
            bio: "Go, SQLite and boring technology.",
            status: .online, isFavorite: false
        ),
    ]
}
