import SwiftUI

@main
struct WorkaveraApp: App {
    @State private var auth = AuthStore()
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.phase {
                case .restoring:
                    ProgressView("Restoring session…")
                        .task { await auth.restoreSession() }
                case .loggedOut:
                    LoginView()
                case .loggedIn:
                    RootView()
                }
            }
            .environment(auth)
            .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
        }
    }
}
