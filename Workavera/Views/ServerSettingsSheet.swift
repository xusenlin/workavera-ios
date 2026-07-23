import SwiftUI

struct ServerSettingsSheet: View {
    /// Shared example used as the server-address placeholder here and as the
    /// fallback hint on the login screen, so both surfaces show the same thing.
    static let addressPlaceholder = ServerConfiguration.defaultAddress

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var allowInsecureHTTP = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Self.addressPlaceholder, text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server Address")
                } footer: {
                    Text("Use HTTPS for any remote or production server. If Workavera runs behind a reverse proxy, include its path prefix.\n\nWorkavera is open source — you can self-host the server from github.com/xusenlin/workavera.")
                }

                if usesHTTP {
                    Section {
                        Toggle("Allow Insecure HTTP", isOn: $allowInsecureHTTP)
                            .disabled(isLoopbackAddress)
                    } footer: {
                        Label(
                            isLoopbackAddress
                                ? "HTTP is unencrypted. It is allowed here only because this is a local loopback address that never leaves the device."
                                : "HTTP is unencrypted. Anyone on the same network can read your password and session token. Only allow it for a server you trust on a private network.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                address = auth.serverAddress
                allowInsecureHTTP = auth.allowInsecureHTTP
            }
            .onChange(of: address) {
                errorMessage = nil
                if !usesHTTP || isLoopbackAddress {
                    allowInsecureHTTP = false
                }
            }
        }
    }

    private var usesHTTP: Bool {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("http://")
    }

    private var isLoopbackAddress: Bool {
        guard let host = URLComponents(string: address)?.host?.lowercased() else { return false }
        return host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1"
    }

    private func save() {
        do {
            try auth.updateServerSettings(
                address: address,
                allowInsecureHTTP: allowInsecureHTTP
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
