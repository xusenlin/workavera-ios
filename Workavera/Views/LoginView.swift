import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showServerSettings = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        header

                        credentialCard

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        loginButton

                        Button {
                            showServerSettings = true
                        } label: {
                            Label(serverDisplayName, systemImage: "server.rack")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)

                        Link(destination: AppLinks.privacyPolicy) {
                            Text("Privacy Policy")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .underline()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 440)
                    // Center the form vertically within the viewport, while still
                    // allowing it to scroll if the keyboard shrinks the space.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            if email.isEmpty {
                email = auth.lastLoginEmail
            }
        }
        .sheet(isPresented: $showServerSettings) {
            ServerSettingsSheet()
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: 6) {
                Text("Workavera")
                    .font(.largeTitle.bold())
                Text("AI-powered self-hosted workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var credentialCard: some View {
        VStack(spacing: 0) {
            fieldRow(icon: "envelope") {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Divider()
                .padding(.leading, 54)

            fieldRow(icon: "lock") {
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func fieldRow(icon: String, @ViewBuilder field: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            field()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var loginButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(Color(.systemBackground))
                } else {
                    Text("Sign In")
                        .font(.headline)
                }
            }
            .foregroundStyle(Color(.systemBackground))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isSubmitDisabled ? 0.45 : 1)
        }
        .disabled(isSubmitDisabled)
    }

    private var isSubmitDisabled: Bool {
        email.isEmpty || password.isEmpty || isLoading
    }

    private var serverDisplayName: String {
        let trimmed = auth.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmed.isEmpty ? ServerSettingsSheet.addressPlaceholder : trimmed
        return address
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        do {
            try await auth.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
