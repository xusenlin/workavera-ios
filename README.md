# Workavera iOS

The native iOS client for Workavera, a self-hosted AI workspace. Its modules and interaction patterns follow the Workavera web app.

**This version needs a Workavera server on 0.1.1 or newer**, because task start
dates, public project links, and subscription discovery depend on fields and
endpoints added in that release. Upgrade the server first. The
[server README](https://github.com/xusenlin/workavera#server-compatibility)
carries the full version table.

The app does not provide account registration or automatic account creation.
Sign-in accounts are provisioned and managed by the administrator of each
self-hosted Workavera server.

## Technology

- **SwiftUI** and the **Observation** framework (`@Observable` / `@Environment`, iOS 17+)
- **async/await** and `URLSession` for direct access to the PocketBase HTTP API
- **NavigationSplitView** with an iPad sidebar and automatic compact navigation on iPhone
- Shared memory and disk caching for raster and SVG avatars
- Server-scoped authentication tokens stored in the **Keychain**, with server settings in `UserDefaults`
- HTTPS required by default; loopback HTTP is allowed, while LAN HTTP requires explicit risk acknowledgement
- XCTest coverage for server validation, network error parsing, preferences, caching, and session recovery
- Xcode 16 project format with file-system-synchronized groups, so new source files do not require project-file edits

## Project Structure

```
Workavera/
├── WorkaveraApp.swift           # Entry point: session recovery → login or main interface
├── Models/User.swift            # User record model with tolerant decoding for empty fields
├── Models/ChatConversation.swift # Chat records, states, and pagination models
├── Services/
│   ├── PocketBaseClient.swift   # Typed networking, profiles, uploads, and user preferences
│   ├── ServerConfiguration.swift # HTTPS/HTTP policy and address normalization
│   └── Keychain.swift           # Server-scoped secure token storage
├── Stores/AuthStore.swift       # Authentication, session recovery, and user preferences
├── Stores/ChatStore.swift       # Chat pagination, selection, pinning, archiving, and deletion
├── Components/                  # Shared avatars, status badges, pagination, and cached UI
├── Widget/                      # Agenda snapshot and App Group storage shared with the widget
└── Views/
    ├── AppSection.swift         # App sections, menu labels, icons, and descriptions
    ├── LoginView.swift          # Authentication and server selection
    ├── RootView.swift           # Adaptive sidebar and detail navigation
    ├── DashboardView.swift      # User greeting, summary statistics, and quick access
    ├── ProfileView.swift        # Profile editing, avatar cropping, password, and status
    ├── ChatView.swift           # Adaptive iPhone/iPad chat and tool-result interface
    ├── SettingsView.swift       # Preferences, server information, and account actions
    ├── ServerSettingsSheet.swift # Server address and insecure HTTP acknowledgement
    └── SessionRecoveryView.swift # Retry interface for session recovery failures
WorkaveraWidget/                 # Agenda widget extension: month grid, next 7 days, refresh button
```

The app and the widget share the `group.com.xusenlin.workavera.ios` App Group.
The app writes the signed-in server, user, and token there (the token in the
App Group keychain access group) so the widget can fetch the agenda on its own.

## Running

1. Start a local Workavera backend (default: `http://127.0.0.1:8090`):

   ```bash
   cd ~/Git/Github/workavera && ./workavera serve
   ```

2. Open `Workavera.xcodeproj` in Xcode 16 or later, choose an iOS 17+ simulator, and run the `Workavera` scheme.

3. A fresh installation connects to `https://demo.workavera.com`. To use your own Workavera deployment, open **Server Settings** from the login screen before signing in. The iOS Simulator can reach a backend on the Mac through `127.0.0.1`. For a physical device, prefer HTTPS. To temporarily use a Mac over LAN HTTP, start the backend with `--http=0.0.0.0:8090` and explicitly enable insecure HTTP in Server Settings.

After signing in, the sidebar, Dashboard, and Profile display the user's avatar, name, title, bio, and online status from the server. Profile supports profile editing, square avatar cropping, avatar upload, and password changes. Settings persists theme and memory preferences through `user_preferences` and provides local sign-out. Account lifecycle management is handled by the selected server's administrator.

## Testing

Run the `Workavera` scheme tests in Xcode, or use:

```bash
xcodebuild test \
  -project Workavera.xcodeproj \
  -scheme Workavera \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
