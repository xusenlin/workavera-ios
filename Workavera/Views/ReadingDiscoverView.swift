import SwiftUI

/// Discover sheet: fetch what the subscriptions are showing right now,
/// summarize anything worth a closer look, and keep only what is wanted
/// (web app ReadingDiscoverDialog).
struct ReadingDiscoverView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ReadingStore.self) private var reading
    @Environment(ReadingDiscoverStore.self) private var discover
    @Environment(\.dismiss) private var dismiss

    @State private var editorInput: ReadingSourceInput?
    @State private var editingSourceID: String?
    @State private var deleteTarget: ReadingSource?

    var body: some View {
        NavigationStack {
            List {
                if let error = discover.errorMessage {
                    Section {
                        InlineErrorBanner(message: error) {
                            Task { await discover.loadSources(using: auth) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                fetchSection
                if !discover.failures.isEmpty {
                    failuresSection
                }
                candidatesSection
                subscriptionsSection
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await discover.loadSources(using: auth)
            }
        }
        // The sheet leaves through this path alone, so kept candidates refresh
        // the reading list here instead of after every save.
        .onDisappear {
            Task { await discover.flushSaved(into: reading, using: auth) }
        }
        .sheet(item: editorBinding) { draft in
            SourceEditorSheet(
                initial: draft.input,
                editing: draft.id != nil,
                isSaving: discover.isSavingSource
            ) { input in
                if let id = draft.id {
                    try await discover.updateSource(id: id, input: input, using: auth)
                } else {
                    try await discover.createSource(input, using: auth)
                }
            }
        }
        .alert("Remove subscription?", isPresented: deletePresented) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Remove", role: .destructive) {
                guard let source = deleteTarget else { return }
                deleteTarget = nil
                Task { await discover.deleteSource(id: source.id, using: auth) }
            }
        } message: {
            Text("“\(deleteTarget?.name ?? "")” stops feeding Discover. Reading items already kept are not affected.")
        }
    }

    // MARK: - Fetch controls

    private var fetchSection: some View {
        Section {
            if discover.sources.isEmpty {
                Text("No subscriptions yet. Add one below to start fetching.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Summary Language", selection: languageBinding) {
                ForEach(SummaryLanguage.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Button {
                Task { await discover.discover(using: auth) }
            } label: {
                HStack(spacing: 6) {
                    Spacer()
                    if discover.isFetching {
                        ProgressView().controlSize(.small)
                        Text("Fetching…")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Fetch")
                    }
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
            }
            .disabled(discover.isFetching || discover.enabledSources.isEmpty)
        } footer: {
            // The enable toggle on a subscription is the selection: fetch
            // reads every subscription switched on below.
            if !discover.sources.isEmpty {
                Text("Fetch reads every subscription enabled below (\(discover.enabledSources.count) of \(discover.sources.count)).")
            }
        }
    }

    private var languageBinding: Binding<SummaryLanguage> {
        Binding(get: { discover.language }, set: { discover.setLanguage($0) })
    }

    // MARK: - Failures

    /// A broken feed or a GitHub redesign surfaces here rather than emptying
    /// the panel silently.
    private var failuresSection: some View {
        Section {
            ForEach(discover.failures) { failure in
                Label {
                    Text("**\(failure.sourceName)**: \(failure.message)")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Candidates

    @ViewBuilder
    private var candidatesSection: some View {
        Section("Candidates") {
            if discover.isFetching && discover.candidates.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Fetching subscriptions…")
                        .foregroundStyle(.secondary)
                }
            } else if discover.candidates.isEmpty {
                Text(
                    discover.hasFetched
                        ? "Nothing came back from the selected subscriptions."
                        : "Pick your subscriptions and fetch to see what is out there."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(discover.candidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        summary: discover.summaries[candidate.url],
                        isSummarizing: discover.summarizingURL == candidate.url,
                        isSaving: discover.savingURL == candidate.url,
                        onSummarize: {
                            Task { await discover.summarize(candidate, using: auth) }
                        },
                        onSave: {
                            Task { await discover.save(candidate, using: auth) }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Subscriptions

    private var subscriptionsSection: some View {
        Section {
            ForEach(discover.sources) { source in
                SourceRow(
                    source: source,
                    onToggle: { enabled in
                        Task { await discover.setSourceEnabled(id: source.id, enabled: enabled, using: auth) }
                    },
                    onEdit: {
                        editingSourceID = source.id
                        editorInput = ReadingSourceInput(
                            name: source.name,
                            kind: source.kind,
                            url: source.url,
                            language: source.language,
                            since: source.since,
                            enabled: source.enabled
                        )
                    }
                )
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) {
                        deleteTarget = source
                    }
                }
            }

            Button {
                editingSourceID = nil
                editorInput = ReadingSourceInput()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Subscription")
                }
            }
            .disabled(discover.isSavingSource)
        } header: {
            Text("Subscriptions")
        } footer: {
            if discover.isLoadingSources {
                Text("Loading subscriptions…")
            }
        }
    }

    // MARK: - Sheet & alert plumbing

    private struct EditorDraft: Identifiable {
        let id: String?
        let input: ReadingSourceInput
    }

    private var editorBinding: Binding<EditorDraft?> {
        Binding(
            get: {
                editorInput.map { EditorDraft(id: editingSourceID, input: $0) }
            },
            set: { newValue in
                if newValue == nil {
                    editorInput = nil
                    editingSourceID = nil
                }
            }
        )
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }
}

// MARK: - Candidate card

private struct CandidateRow: View {
    let candidate: DiscoverCandidate
    let summary: CandidateSummary?
    let isSummarizing: Bool
    let isSaving: Bool
    let onSummarize: () -> Void
    let onSave: () -> Void

    /// Source, star movement and language as one "a · b · c" line.
    private var metaText: String {
        var parts = [candidate.sourceName]
        if candidate.periodStars > 0 {
            let period = TrendingSince(rawValue: candidate.starsPeriod)?.label ?? ""
            parts.append("★ +\(candidate.periodStars.formatted()) \(period)".trimmingCharacters(in: .whitespaces))
        }
        if candidate.stars > 0 {
            parts.append("\(candidate.stars.formatted()) stars")
        }
        if !candidate.language.isEmpty {
            parts.append(candidate.language)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = URL(string: candidate.url) {
                Link(candidate.title, destination: url)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(candidate.title)
                    .font(.subheadline.weight(.medium))
            }

            // One composed line: separate labels each wrapped onto their own
            // line once the row filled up.
            Text(metaText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !candidate.description.isEmpty {
                Text(candidate.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let summary {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.summary)
                        .font(.caption)
                    if !summary.keyPoints.isEmpty {
                        ForEach(summary.keyPoints, id: \.self) { point in
                            Label(point, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }

            // Text-only actions: the section above already says which language
            // summaries come in, and "Add" is enough next to a reading list.
            HStack(spacing: 10) {
                if candidate.alreadySaved {
                    Text("Added")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button(summary == nil ? "Summarize" : "Summarize Again", action: onSummarize)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSummarizing || isSaving)
                        .overlay {
                            if isSummarizing { ProgressView().controlSize(.mini) }
                        }
                    Button("Add", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSaving || isSummarizing)
                        .overlay {
                            if isSaving {
                                ProgressView().controlSize(.mini)
                                    .tint(Color(.systemBackground))
                            }
                        }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        // Stretch the row separator to the card's leading edge; the default
        // guide follows the indented content and draws it half width.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// A bullet list row: a small dot followed by the text.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 6) {
            configuration.icon
                .font(.system(size: 4))
                .padding(.top, 5)
            configuration.title
        }
    }
}

// MARK: - Subscription row

private struct SourceRow: View {
    let source: ReadingSource
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !source.lastError.isEmpty {
                        Text(source.lastError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if let fetched = source.lastFetchedAt {
                        Text("Fetched \(fetched.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("Enabled", isOn: enabledBinding)
                .labelsHidden()
        }
    }

    private var subtitle: String {
        switch source.kind {
        case .rss:
            return source.url
        case .githubTrending:
            return "GitHub Trending · \(source.language) · \(source.since.label)"
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { source.enabled }, set: onToggle)
    }
}

// MARK: - Subscription editor

private struct SourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editing: Bool
    let isSaving: Bool
    let onSubmit: (ReadingSourceInput) async throws -> Void

    @State private var input: ReadingSourceInput
    @State private var errorMessage: String?

    init(
        initial: ReadingSourceInput,
        editing: Bool,
        isSaving: Bool,
        onSubmit: @escaping (ReadingSourceInput) async throws -> Void
    ) {
        _input = State(initialValue: initial)
        self.editing = editing
        self.isSaving = isSaving
        self.onSubmit = onSubmit
    }

    private var isValid: Bool {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return false }
        switch input.kind {
        case .rss:
            return URL(string: input.url.trimmingCharacters(in: .whitespacesAndNewlines))?.host() != nil
        case .githubTrending:
            return !input.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $input.name)
                    Picker("Kind", selection: $input.kind) {
                        ForEach(ReadingSourceKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                }

                switch input.kind {
                case .rss:
                    Section {
                        TextField("Feed URL", text: $input.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("An RSS or Atom feed address.")
                    }
                case .githubTrending:
                    Section {
                        TextField("Language (e.g. go, typescript)", text: $input.language)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("Period", selection: $input.since) {
                            ForEach(TrendingSince.allCases) { since in
                                Text(since.label).tag(since)
                            }
                        }
                    } footer: {
                        Text("GitHub's trending board for one language.")
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $input.enabled)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editing ? "Edit Subscription" : "Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing ? "Save" : "Add") {
                        Task {
                            do {
                                try await onSubmit(input)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
