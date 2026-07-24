import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(SupportStore.self) private var support
    @State private var errorMessage: String?
    @State private var supportAlertTitle = "Support Workavera"
    @State private var supportMessage: String?
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var isDeletingAccount = false

    var body: some View {
        Form {
            if let warningMessage {
                InlineErrorListSection(
                    message: warningMessage,
                    actionTitle: errorMessage == nil ? "Retry" : "Dismiss"
                ) {
                    if errorMessage != nil {
                        errorMessage = nil
                    } else {
                        Task { await auth.reloadPreferences() }
                    }
                }
            }

            Section("Server") {
                LabeledContent {
                    Text(auth.serverAddress)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } label: {
                    Label("Address", systemImage: "server.rack")
                }
            }

            Section {
                NavigationLink {
                    ModelConfigurationsView()
                } label: {
                    Label("Model Configurations", systemImage: "sparkles")
                }
                NavigationLink {
                    ModelSharingView()
                } label: {
                    Label("Model Sharing", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Large Language Model")
            } footer: {
                Text("Add at least one model configuration to use Chat and AI summaries.")
            }

            Section {
                NavigationLink {
                    APIKeysView()
                } label: {
                    Label("API Keys", systemImage: "key")
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("Connect third-party MCP clients to your Workavera tools.")
            }

            Section {
                Toggle(isOn: memoryEnabledBinding) {
                    Label("Use Chat Memory", systemImage: "brain.head.profile")
                }
                Toggle(isOn: memoryAutoCaptureBinding) {
                    Label("Automatic Capture", systemImage: "wand.and.stars")
                }
                .disabled(!auth.memoryEnabled)
                NavigationLink {
                    SavedMemoriesView()
                } label: {
                    Label("Saved Memories", systemImage: "archivebox")
                }
            } header: {
                Text("Memory")
            } footer: {
                Text("Reuse facts and preferences you allow across chat sessions. Off by default.")
            }

            Section("Appearance") {
                Picker(selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label)
                            .tag(appearance)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
            }

            Section {
                LabeledContent {
                    Text(auth.user?.email ?? "")
                } label: {
                    Label("Email", systemImage: "envelope")
                }
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                Button(role: .destructive) {
                    confirmDeleteAccount = true
                } label: {
                    HStack {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundStyle(.red)
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeletingAccount)
            } header: {
                Text("Account")
            } footer: {
                Text("Deletes your account and signs you out on every device. You won't be able to sign back in, and this can't be undone from the app.")
            }

            Section("About") {
                LabeledContent {
                    Text(appVersion)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
                Link(destination: AppLinks.privacyPolicy) {
                    HStack {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Link(destination: AppLinks.repository) {
                    HStack {
                        Label("GitHub", systemImage: "link")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("xusenlin/workavera")
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            supportSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await auth.reloadPreferences()
        }
        .alert(
            "Sign out of Workavera?",
            isPresented: $confirmSignOut
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                auth.logout()
            }
        } message: {
            Text("Your session will be removed from this device.")
        }
        .alert(
            "Delete your account?",
            isPresented: $confirmDeleteAccount
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Your account will be deleted and you'll be signed out on every device. You won't be able to sign back in, and this can't be undone from the app.")
        }
        .alert(
            supportAlertTitle,
            isPresented: Binding(
                get: { supportMessage != nil },
                set: { if !$0 { supportMessage = nil } }
            )
        ) {
            Button("OK") {
                supportMessage = nil
            }
        } message: {
            Text(supportMessage ?? "")
        }
    }

    private var supportSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(
                    url: auth.avatarURL,
                    name: auth.user?.displayName ?? "?",
                    size: 54
                )
                .overlay(alignment: .topLeading) {
                    SupporterAvatarBadge(size: 20)
                        .offset(x: -3, y: -3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        support.isLifetimeSupporter
                            ? "Thank you for your support"
                            : "Supporter badge preview"
                    )
                    .font(.headline)

                    Text(
                        support.isLifetimeSupporter
                            ? "Your supporter mark is active on this Apple Account."
                            : "A one-time purchase supports continued open-source development."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)

            if support.isLifetimeSupporter {
                HStack(spacing: 10) {
                    Label("Lifetime Supporter", systemImage: "heart.circle.fill")
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    Label("Active", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    purchase(.lifetimeSupporter)
                } label: {
                    HStack {
                        Label("Become a Lifetime Supporter", systemImage: "heart.circle.fill")
                        Spacer()
                        if support.purchasingProductID == .lifetimeSupporter {
                            ProgressView()
                        } else {
                            Text(
                                support.product(for: .lifetimeSupporter)?.displayPrice
                                    ?? "One-time"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(
                    support.product(for: .lifetimeSupporter) == nil
                        || support.purchasingProductID != nil
                )
            }

            Menu {
                ForEach(SupportProductID.tips) { productID in
                    Button {
                        purchase(productID)
                    } label: {
                        Label {
                            if let price = support.product(for: productID)?.displayPrice {
                                Text("\(productID.title) · \(price)")
                            } else {
                                Text(productID.title)
                            }
                        } icon: {
                            Image(systemName: productID.systemImage)
                        }
                    }
                    .disabled(support.product(for: productID) == nil)
                }
            } label: {
                HStack {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 22)
                    Text("Leave a Tip")
                    Spacer()
                    if support.purchasingProductID.map(SupportProductID.tips.contains) == true {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(support.purchasingProductID != nil)

            Button("Restore Purchases", systemImage: "arrow.clockwise") {
                restorePurchases()
            }
            .disabled(support.purchasingProductID != nil)
        } header: {
            Text("Support Workavera")
        } footer: {
            Text("Tips are optional and do not unlock core features. Purchases are handled by the App Store and never pass through your Workavera server.")
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await auth.deleteAccount()
                // On success the store transitions to the logged-out phase and
                // this view is torn down, so no further UI work is needed here.
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    private func purchase(_ productID: SupportProductID) {
        Task {
            do {
                switch try await support.purchase(productID) {
                case .purchased(.lifetimeSupporter):
                    showSupportMessage(
                        title: "Thank You for Supporting Workavera",
                        message: "You're now a Lifetime Supporter. Your support helps Workavera stay open source and continue improving. A supporter badge has also been added to your avatar."
                    )
                case .purchased:
                    showSupportMessage(
                        title: "Thank You for Your Support",
                        message: "Your tip directly supports the continued development and maintenance of Workavera. It truly means a lot."
                    )
                case .pending:
                    showSupportMessage(
                        title: "Purchase Pending",
                        message: "The purchase is waiting for approval from the App Store. We'll update it automatically when it completes."
                    )
                case .cancelled:
                    break
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restorePurchases() {
        Task {
            do {
                try await support.restorePurchases()
                if support.isLifetimeSupporter {
                    showSupportMessage(
                        title: "Purchase Restored",
                        message: "Welcome back, and thank you for supporting Workavera. Your Lifetime Supporter badge is active again."
                    )
                } else {
                    showSupportMessage(
                        title: "Nothing to Restore",
                        message: "No Lifetime Supporter purchase was found for this Apple Account."
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showSupportMessage(title: String, message: String) {
        supportAlertTitle = title
        supportMessage = message
    }

    /// Reads the version from the bundle so MARKETING_VERSION remains the single source of truth.
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { auth.appearance },
            set: { appearance in
                Task {
                    do {
                        try await auth.updateAppearance(appearance)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var memoryEnabledBinding: Binding<Bool> {
        Binding(
            get: { auth.memoryEnabled },
            set: { enabled in
                Task {
                    do {
                        try await auth.updateMemoryEnabled(enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var memoryAutoCaptureBinding: Binding<Bool> {
        Binding(
            get: { auth.memoryAutoCapture },
            set: { enabled in
                Task {
                    do {
                        try await auth.updateMemoryAutoCapture(enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var warningMessage: String? {
        errorMessage ?? auth.preferencesMessage
    }
}
