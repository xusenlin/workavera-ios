import SwiftUI
import WidgetKit

@main
struct WorkaveraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthStore()
    @State private var notifications = NotificationStore()
    @State private var board = BoardStore()
    @State private var dashboard = DashboardStore()
    @State private var docs = DocsStore()
    @State private var calendar = CalendarStore()
    @State private var llmSettings = LLMSettingsStore()
    @State private var apiKeys = APIKeysStore()
    @State private var mcpServers = MCPServersStore()
    @State private var savedMemories = SavedMemoriesStore()
    @State private var contacts = ContactsStore()
    @State private var reading = ReadingStore()
    @State private var readingDiscover = ReadingDiscoverStore()
    @State private var chat = ChatStore()
    @State private var support = SupportStore()
    @State private var requestedSection: AppSection?

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
                    RootView(requestedSection: $requestedSection)
                }
            }
            .environment(auth)
            .environment(notifications)
            .environment(board)
            .environment(dashboard)
            .environment(docs)
            .environment(calendar)
            .environment(llmSettings)
            .environment(apiKeys)
            .environment(mcpServers)
            .environment(savedMemories)
            .environment(contacts)
            .environment(reading)
            .environment(readingDiscover)
            .environment(chat)
            .environment(support)
            .preferredColorScheme(auth.appearance.colorScheme)
            .task {
                await support.start()
            }
            .onOpenURL { url in
                requestedSection = AppSection(deepLink: url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Let the agenda widget pick up anything changed while the app was open.
            if phase == .background, auth.phase == .loggedIn {
                WidgetCenter.shared.reloadTimelines(ofKind: AgendaWidgetStore.widgetKind)
            }
        }
    }
}
