import Foundation
import Observation

/// Drives the Discover sheet: subscriptions the user owns, the candidates a
/// fetch brings back, and the summaries requested before anything is kept
/// (web app reading-discover store).
@MainActor
@Observable
final class ReadingDiscoverStore {
    private static let languageDefaultsKey = "workavera.reading.discover.language"

    private(set) var sources: [ReadingSource] = []
    private(set) var candidates: [DiscoverCandidate] = []
    private(set) var failures: [DiscoverFailure] = []
    /// Summaries keyed by candidate URL, matching the web panel.
    private(set) var summaries: [String: CandidateSummary] = [:]
    private(set) var isLoadingSources = false
    private(set) var isFetching = false
    private(set) var hasFetched = false
    private(set) var isSavingSource = false
    private(set) var summarizingURL: String?
    private(set) var savingURL: String?
    private(set) var savedCount = 0
    private(set) var errorMessage: String?

    /// The language candidates are summarized into; persisted across launches.
    private(set) var language: SummaryLanguage

    private let defaults: UserDefaults

    var enabledSources: [ReadingSource] {
        sources.filter(\.enabled)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = SummaryLanguage(rawValue: defaults.string(forKey: Self.languageDefaultsKey) ?? "")
            ?? .english
    }

    func reset() {
        sources = []
        candidates = []
        failures = []
        summaries = [:]
        isLoadingSources = false
        isFetching = false
        hasFetched = false
        isSavingSource = false
        summarizingURL = nil
        savingURL = nil
        savedCount = 0
        errorMessage = nil
    }

    func loadSources(using auth: AuthStore) async {
        guard !isLoadingSources else { return }
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let loaded = try await auth.loadReadingSources()
            sources = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSource(_ input: ReadingSourceInput, using auth: AuthStore) async throws {
        guard !isSavingSource else { return }
        isSavingSource = true
        defer { isSavingSource = false }
        do {
            try await auth.createReadingSource(input: input)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
        await loadSources(using: auth)
    }

    func updateSource(id: String, input: ReadingSourceInput, using auth: AuthStore) async throws {
        guard !isSavingSource else { return }
        isSavingSource = true
        defer { isSavingSource = false }
        do {
            try await auth.updateReadingSource(id: id, input: input)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
        await loadSources(using: auth)
    }

    func setSourceEnabled(id: String, enabled: Bool, using auth: AuthStore) async {
        do {
            try await auth.setReadingSourceEnabled(id: id, enabled: enabled)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await loadSources(using: auth)
    }

    func deleteSource(id: String, using auth: AuthStore) async {
        do {
            try await auth.deleteReadingSource(id: id)
            candidates.removeAll { $0.sourceID == id }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await loadSources(using: auth)
    }

    func setLanguage(_ newLanguage: SummaryLanguage) {
        language = newLanguage
        defaults.set(newLanguage.rawValue, forKey: Self.languageDefaultsKey)
    }

    /// Reads every enabled subscription and returns candidates that are not
    /// stored yet, so each one can be weighed before anything is kept. The
    /// enable toggle on a subscription is the selection: there is no second
    /// switch for the same choice.
    func discover(using auth: AuthStore) async {
        guard !isFetching, !enabledSources.isEmpty else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let result = try await auth.discoverReadingCandidates(
                sourceIDs: enabledSources.map(\.id)
            )
            candidates = result.items
            failures = result.failures
            summaries = [:]
            hasFetched = true
            errorMessage = nil
            // The sources carry a fresh fetch time and error now.
            await loadSources(using: auth)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func summarize(_ candidate: DiscoverCandidate, using auth: AuthStore) async {
        guard summarizingURL == nil else { return }
        summarizingURL = candidate.url
        defer { summarizingURL = nil }
        do {
            let summary = try await auth.summarizeReadingCandidate(
                url: candidate.url,
                title: candidate.title,
                language: language.rawValue
            )
            summaries[candidate.url] = summary
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps one candidate as an ordinary reading item, carrying the summary
    /// the user asked for along with it.
    func save(_ candidate: DiscoverCandidate, using auth: AuthStore) async {
        guard savingURL == nil, !candidate.alreadySaved else { return }
        savingURL = candidate.url
        defer { savingURL = nil }
        let summary = summaries[candidate.url]
        var input = ReadingItemInput(
            url: candidate.url,
            title: String(candidate.title.prefix(240)),
            description: candidate.description,
            tags: candidate.language.isEmpty ? [] : [candidate.language]
        )
        input.summary = summary?.summary ?? ""
        input.keyPoints = summary?.keyPoints ?? []
        input.summaryLanguage = summary?.language ?? ""
        do {
            _ = try await auth.createReadingItem(input: input)
            if let index = candidates.firstIndex(where: { $0.url == candidate.url }) {
                candidates[index].alreadySaved = true
            }
            savedCount += 1
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes the reading list once the sheet closes, instead of after
    /// every kept candidate.
    func flushSaved(into reading: ReadingStore, using auth: AuthStore) async {
        guard savedCount > 0 else { return }
        savedCount = 0
        await reading.refresh(using: auth, page: 0)
    }

    func clearError() {
        errorMessage = nil
    }
}
