import Foundation
import Observation

/// 全局认证状态：登录、会话恢复、当前用户与状态更新。
@MainActor
@Observable
final class AuthStore {
    enum Phase {
        case restoring
        case loggedOut
        case loggedIn
    }

    private(set) var phase: Phase = .restoring
    private(set) var user: User?
    private(set) var token: String?

    /// PocketBase 服务器地址，可在登录页修改。
    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: Self.serverKey) }
    }

    /// 上次成功登录的邮箱，用于登录页自动填充。
    private(set) var lastLoginEmail: String {
        didSet { UserDefaults.standard.set(lastLoginEmail, forKey: Self.lastEmailKey) }
    }

    private static let serverKey = "workavera.serverAddress"
    private static let lastEmailKey = "workavera.lastLoginEmail"
    private static let tokenAccount = "workavera.authToken"

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverKey) ?? "http://127.0.0.1:8090"
        lastLoginEmail = UserDefaults.standard.string(forKey: Self.lastEmailKey) ?? ""
    }

    private var client: PocketBaseClient? {
        PocketBaseClient(baseURLString: serverAddress)
    }

    var avatarURL: URL? {
        guard let user, let client else { return nil }
        return client.fileURL(collectionId: user.collectionId, recordId: user.id, fileName: user.avatar)
    }

    /// App 启动时用保存的 token 换取最新的用户记录。
    func restoreSession() async {
        guard let savedToken = Keychain.read(account: Self.tokenAccount), let client else {
            phase = .loggedOut
            return
        }
        do {
            apply(try await client.authRefresh(token: savedToken))
        } catch {
            Keychain.delete(account: Self.tokenAccount)
            phase = .loggedOut
        }
    }

    func login(email: String, password: String) async throws {
        guard let client else {
            throw PocketBaseError(message: "Invalid server address. Check it and try again.")
        }
        apply(try await client.authWithPassword(identity: email, password: password))
        lastLoginEmail = email
    }

    func logout() {
        Keychain.delete(account: Self.tokenAccount)
        token = nil
        user = nil
        phase = .loggedOut
    }

    /// 把新的在线状态写回后端，成功后同步本地记录。
    func updateStatus(_ status: UserStatus) async {
        guard let user, let token, let client else { return }
        do {
            self.user = try await client.updateUser(
                id: user.id,
                fields: ["status": status.rawValue],
                token: token
            )
        } catch {
            // 状态更新失败时保留原状态即可，不打断使用
        }
    }

    private func apply(_ auth: AuthResponse) {
        user = auth.record
        token = auth.token
        Keychain.save(auth.token, account: Self.tokenAccount)
        phase = .loggedIn
    }
}
