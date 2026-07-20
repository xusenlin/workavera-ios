import SwiftUI

struct ServerSettingsSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var allowInsecureHTTP = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://workavera.example.com", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server Address")
                } footer: {
                    Text("Use HTTPS for remote and production servers. A path is supported when Workavera is hosted below a reverse-proxy prefix.")
                }

                if usesHTTP && !isLoopbackAddress {
                    Section {
                        Toggle("Allow Insecure HTTP", isOn: $allowInsecureHTTP)
                    } footer: {
                        Label(
                            "Passwords and session tokens can be read by other devices on the network when HTTP is used.",
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
