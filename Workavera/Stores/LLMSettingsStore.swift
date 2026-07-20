import Foundation
import Observation

@MainActor
@Observable
final class LLMSettingsStore {
    private(set) var models: [LLMModelConfiguration] = []
    private(set) var shareTargets: [LLMShareTarget] = []
    private(set) var isLoadingModels = false
    private(set) var isLoadingTargets = false
    private(set) var hasLoadedModels = false
    private(set) var errorMessage: String?
    private(set) var mutatingModelIDs: Set<String> = []
    private(set) var isSharing = false

    private var cachedUserID: String?
    private var loadSequence = 0

    var shareableModels: [LLMModelConfiguration] {
        models.filter { !$0.isSharedCopy }
    }

    func reset() {
        loadSequence += 1
        models = []
        shareTargets = []
        isLoadingModels = false
        isLoadingTargets = false
        hasLoadedModels = false
        errorMessage = nil
        mutatingModelIDs = []
        isSharing = false
        cachedUserID = nil
    }

    func loadModelsIfNeeded(using auth: AuthStore) async {
        guard prepareCache(for: auth), !hasLoadedModels, !isLoadingModels else { return }
        await refreshModels(using: auth)
    }

    func refreshModels(using auth: AuthStore) async {
        guard prepareCache(for: auth) else { return }
        loadSequence += 1
        let sequence = loadSequence
        isLoadingModels = true
        defer {
            if sequence == loadSequence { isLoadingModels = false }
        }
        do {
            let loaded = try await auth.loadLLMModels()
            guard sequence == loadSequence else { return }
            models = loaded
            hasLoadedModels = true
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard sequence == loadSequence else { return }
            hasLoadedModels = true
            errorMessage = error.localizedDescription
        }
    }

    func loadShareTargets(using auth: AuthStore) async {
        guard prepareCache(for: auth), !isLoadingTargets else { return }
        isLoadingTargets = true
        defer { isLoadingTargets = false }
        do {
            shareTargets = try await auth.loadLLMShareTargets()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(_ input: LLMModelInput, using auth: AuthStore) async throws {
        do {
            let created = try await auth.createLLMModel(input: input)
            upsert(created)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func update(
        _ model: LLMModelConfiguration,
        input: LLMModelInput,
        using auth: AuthStore
    ) async throws {
        guard !mutatingModelIDs.contains(model.id) else { return }
        mutatingModelIDs.insert(model.id)
        defer { mutatingModelIDs.remove(model.id) }
        do {
            upsert(try await auth.updateLLMModel(id: model.id, input: input))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ model: LLMModelConfiguration, using auth: AuthStore) async -> Bool {
        guard !mutatingModelIDs.contains(model.id) else { return false }
        mutatingModelIDs.insert(model.id)
        defer { mutatingModelIDs.remove(model.id) }
        do {
            try await auth.deleteLLMModel(id: model.id)
            models.removeAll { $0.id == model.id }
            await refreshModels(using: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setDefault(_ model: LLMModelConfiguration, using auth: AuthStore) async {
        guard !model.isDefault, !mutatingModelIDs.contains(model.id) else { return }
        mutatingModelIDs.insert(model.id)
        defer { mutatingModelIDs.remove(model.id) }
        do {
            _ = try await auth.setDefaultLLMModel(id: model.id)
            for index in models.indices {
                models[index].isDefault = models[index].id == model.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func share(
        model: LLMModelConfiguration,
        userIDs: [String],
        using auth: AuthStore
    ) async throws -> Int {
        guard !model.isSharedCopy, !userIDs.isEmpty, !isSharing else { return 0 }
        isSharing = true
        defer { isSharing = false }
        do {
            let count = try await auth.shareLLMModel(id: model.id, userIDs: userIDs)
            errorMessage = nil
            return count
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func upsert(_ model: LLMModelConfiguration) {
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index] = model
        } else {
            models.append(model)
        }
        models.sort { $0.created < $1.created }
    }

    @discardableResult
    private func prepareCache(for auth: AuthStore) -> Bool {
        guard let userID = auth.user?.id else {
            if cachedUserID != nil { reset() }
            return false
        }
        guard cachedUserID != userID else { return true }
        reset()
        cachedUserID = userID
        return true
    }
}
