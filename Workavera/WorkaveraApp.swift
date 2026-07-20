import SwiftUI

@main
struct WorkaveraApp: App {
    @State private var auth = AuthStore()
    @State private var notifications = NotificationStore()
    @State private var board = BoardStore()
    @State private var dashboard = DashboardStore()
    @State private var docs = DocsStore()

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
            .environment(notifications)
            .environment(board)
            .environment(dashboard)
            .environment(docs)
            .preferredColorScheme(auth.appearance.colorScheme)
        }
    }
}
