import Foundation

/// Canonical external URLs shown in the app, kept in one place so the privacy
/// policy and project links stay consistent across the login and settings
/// screens (and match what's filed in App Store Connect).
enum AppLinks {
    /// Public privacy policy. Rendered by GitHub; must stay reachable while the
    /// app is on the App Store. Also used as the App Store Connect privacy URL.
    static let privacyPolicy = URL(string: "https://github.com/xusenlin/workavera-ios/blob/main/docs/PrivacyPolicy.md")!

    /// Project home / support page.
    static let repository = URL(string: "https://github.com/xusenlin/workavera")!
}
