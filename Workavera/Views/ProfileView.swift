import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @State private var showEditProfile = false
    @State private var showChangePassword = false
    @State private var showAvatarPreview = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage {
                InlineErrorListSection(
                    message: errorMessage,
                    actionTitle: "Dismiss"
                ) {
                    self.errorMessage = nil
                }
            }

            Section {
                VStack(spacing: 12) {
                    Button {
                        showAvatarPreview = true
                    } label: {
                        AvatarView(
                            url: auth.avatarURL,
                            name: auth.user?.displayName ?? "?",
                            size: 96
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill((auth.user?.status ?? .offline).color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(Color(.systemGroupedBackground), lineWidth: 3.5)
                                )
                                .offset(x: -2, y: -2)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.avatarURL == nil)
                    .accessibilityLabel("View profile photo")
                    .accessibilityHint("Opens the profile photo at a larger size")

                    VStack(spacing: 4) {
                        Text(auth.user?.displayName ?? "")
                            .font(.title2.bold())
                        if let title = auth.user?.title {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(auth.user?.email ?? "")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section("Status") {
                Picker("My Status", selection: statusBinding) {
                    ForEach(UserStatus.allCases) { status in
                        HStack {
                            StatusDot(status: status)
                            Text(status.label)
                        }
                        .tag(status)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Details") {
                LabeledContent("Phone", value: auth.user?.phone ?? "Not set")
                LabeledContent("Title", value: auth.user?.title ?? "Not set")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bio")
                    Text(auth.user?.bio ?? "Not set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account") {
                LabeledContent("User ID", value: auth.user?.id ?? "")
                LabeledContent("Joined", value: String((auth.user?.created ?? "").prefix(10)))
                Button {
                    showChangePassword = true
                } label: {
                    Label("Change Password", systemImage: "lock.rotation")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditProfile = true }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet()
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
        }
        .fullScreenCover(isPresented: $showAvatarPreview) {
            AvatarPreviewSheet(
                url: auth.avatarURL,
                name: auth.user?.displayName ?? "?"
            )
        }
    }

    private var statusBinding: Binding<UserStatus> {
        Binding(
            get: { auth.user?.status ?? .offline },
            set: { newValue in
                Task {
                    do {
                        try await auth.updateStatus(newValue)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

}

private struct AvatarPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL?
    let name: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                AvatarView(
                    url: url,
                    name: name,
                    size: min(proxy.size.width - 40, proxy.size.height - 180, 440)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .padding()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismiss()
            }
        }
        .statusBarHidden()
    }
}

private struct EditProfileSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var title = ""
    @State private var bio = ""
    @State private var status: UserStatus = .offline
    @State private var photoItem: PhotosPickerItem?
    @State private var cropCandidate: CropCandidate?
    @State private var avatarImage: UIImage?
    @State private var avatarUpload: AvatarUpload?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Group {
                            if let avatarImage {
                                Image(uiImage: avatarImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AvatarView(
                                    url: auth.avatarURL,
                                    name: auth.user?.displayName ?? "?",
                                    size: 96
                                )
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choose Photo", systemImage: "photo")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Profile") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Title", text: $title)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...8)
                    Picker("Status", selection: $status) {
                        ForEach(UserStatus.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                if let errorMessage {
                    InlineErrorListSection(
                        message: errorMessage,
                        actionTitle: "Dismiss"
                    ) {
                        self.errorMessage = nil
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { populate() }
            .onChange(of: photoItem) {
                Task { await prepareSelectedPhoto() }
            }
            .fullScreenCover(item: $cropCandidate) { candidate in
                AvatarCropperView(
                    image: candidate.image,
                    onCancel: {
                        photoItem = nil
                    },
                    onCrop: { croppedImage in
                        applyCroppedPhoto(croppedImage)
                    }
                )
            }
        }
    }

    private func populate() {
        guard let user = auth.user else { return }
        name = user.name
        phone = user.phone ?? ""
        title = user.title ?? ""
        bio = user.bio ?? ""
        status = user.status ?? .offline
    }

    private func prepareSelectedPhoto() async {
        guard let selectedItem = photoItem else { return }
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw ProfileImageError.couldNotRead
            }
            cropCandidate = CropCandidate(image: image)
            errorMessage = nil
        } catch {
            photoItem = nil
            errorMessage = error.localizedDescription
        }
    }

    private func applyCroppedPhoto(_ image: UIImage) {
        photoItem = nil

        guard let jpeg = Self.preparedJPEG(from: image) else {
            errorMessage = ProfileImageError.couldNotRead.localizedDescription
            return
        }
        guard jpeg.count <= 500 * 1024 else {
            errorMessage = ProfileImageError.tooLarge.localizedDescription
            return
        }

        avatarImage = UIImage(data: jpeg)
        avatarUpload = AvatarUpload(data: jpeg, fileName: "avatar.jpg", mimeType: "image/jpeg")
        errorMessage = nil
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await auth.updateProfile(
                ProfileUpdate(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: status
                ),
                avatar: avatarUpload
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private static func preparedJPEG(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in stride(from: 0.9, through: 0.3, by: -0.1) {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 500 * 1024 {
                return data
            }
        }
        return resized.jpegData(compressionQuality: 0.2)
    }
}

private struct CropCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum ProfileImageError: LocalizedError {
    case couldNotRead
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .couldNotRead: "The selected image could not be read."
        case .tooLarge: "The selected image is larger than the server's 500 KB avatar limit."
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm New Password", text: $confirmation)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Use at least 8 characters.")
                }

                if let errorMessage {
                    InlineErrorListSection(
                        message: errorMessage,
                        actionTitle: "Dismiss"
                    ) {
                        self.errorMessage = nil
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var isValid: Bool {
        !currentPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmation
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await auth.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
