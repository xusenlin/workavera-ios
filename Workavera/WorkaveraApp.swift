import SwiftUI

@main
struct WorkaveraApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.phase {
                case .restoring:
                    ProgressView("Restoring session…")
                        .task { await auth.restoreSession() }
                case .recoveryFailed:
                    SessionRecoveryView()
                case .loggedOut:
                    LoginView()
                case .loggedIn:
                    RootView()
                }
            }
            .environment(auth)
            .preferredColorScheme(auth.appearance.colorScheme)
        }
    }
}
