import Foundation

struct AIConsentStore {
    private let defaults: UserDefaults

    private static let keyPrefix = "workavera.aiConsent."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isAuthorized(userID: String, modelID: String) -> Bool {
        defaults.bool(forKey: authorizationKey(userID: userID, modelID: modelID))
    }

    func authorize(userID: String, modelID: String) {
        defaults.set(true, forKey: authorizationKey(userID: userID, modelID: modelID))
    }

    private func authorizationKey(userID: String, modelID: String) -> String {
        "\(Self.keyPrefix)\(userID).\(modelID)"
    }
}
