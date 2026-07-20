import SwiftUI

struct SessionRecoveryView: View {
    @Environment(AuthStore.self) private var auth
    @State private var isRetrying = false
    @State private var showServerSettings = false
    @State private var confirmSignOut = false

    var body: some View {
        ContentUnavailableView {
            Label("Server Unavailable", systemImage: "network.slash")
        } description: {
            Text(auth.recoveryMessage ?? "Workavera could not restore your session.")
        } actions: {
            Button {
                Task { await retry() }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)

            Button("Server Settings") {
                showServerSettings = true
            }
            .buttonStyle(.bordered)

            Button("Sign Out", role: .destructive) {
                confirmSignOut = true
            }
        }
        .sheet(isPresented: $showServerSettings, onDismiss: {
            Task { await retry() }
        }) {
            ServerSettingsSheet()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Sign out of Workavera?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                auth.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved session will be removed from this device.")
        }
    }

    private func retry() async {
        isRetrying = true
        await auth.restoreSession()
        isRetrying = false
    }
}
