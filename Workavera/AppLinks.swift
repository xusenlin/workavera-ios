import Foundation

/// Canonical external URLs shown in the app, kept in one place so the privacy
/// policy, support, and project links stay consistent across the login and settings
/// screens (and match what's filed in App Store Connect).
enum AppLinks {
    /// Public privacy policy. Rendered by GitHub; must stay reachable while the
    /// app is on the App Store. Also used as the App Store Connect privacy URL.
    static let privacyPolicy = URL(string: "https://github.com/xusenlin/workavera/blob/main/doc/privacy-policy.md")!

    /// Public support page. Also used as the App Store Connect support URL.
    static let support = URL(string: "https://github.com/xusenlin/workavera/blob/main/doc/support.md")!

    /// Project home.
    static let repository = URL(string: "https://github.com/xusenlin/workavera")!
}
