import SwiftUI
import WidgetKit

/// Everything the widget shows for one entry, derived from the snapshot.
private struct AgendaPresentation {
    struct Row: Identifiable {
        let item: AgendaWidgetItem
        /// The day the row is listed under (today for events already in progress).
        let dayKey: String
        let date: Date

        var id: String { item.id }
    }

    let calendar: Calendar
    let today: Date
    let rows: [Row]
    let updatedAt: Date?
    /// Eight rows need a tighter layout than six to fit.
    let isDense: Bool

    init(entry: AgendaWidgetEntry) {
        let calendar = entry.snapshot?.calendar ?? Calendar(identifier: .gregorian)
        let formatter = AgendaWidgetSnapshot.dayFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: entry.date)
        let todayKey = formatter.string(from: today)

        // Snapshot items are already in day order; take the first upcoming ones.
        var rows: [Row] = []
        for item in entry.snapshot?.items ?? [] where entry.content.includes(item) {
            guard let dayKey = item.dayKeys.first(where: { $0 >= todayKey }),
                  let date = formatter.date(from: dayKey) else { continue }
            rows.append(Row(item: item, dayKey: dayKey, date: date))
            if rows.count == entry.itemCount.count { break }
        }

        self.calendar = calendar
        self.today = today
        self.rows = rows
        self.updatedAt = entry.snapshot?.updatedAt
        self.isDense = entry.itemCount == .eight
    }

    /// The user's system language. `Locale.current` follows the extension's own
    /// localizations, so it falls back to English for languages the widget
    /// isn't translated into; dates should still read in the user's language.
    private static let userLocale = Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? .current

    func isToday(_ row: Row) -> Bool {
        calendar.isDate(row.date, inSameDayAs: today)
    }

    func text(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.userLocale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// "Today" / "Tomorrow" in the user's language, otherwise e.g. "Wed, 10/21".
    func dateLabel(for row: Row) -> String {
        let days = calendar.dateComponents([.day], from: today, to: row.date).day ?? 0
        guard days < 2 else { return text(row.date, template: "MdEEE") }
        let formatter = DateFormatter()
        formatter.locale = Self.userLocale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: row.date)
    }

    /// Start time for a timed event on its first day; nil otherwise.
    func startTime(for row: Row) -> String? {
        guard row.item.kind == .event, !row.item.allDay,
              let start = row.item.startAt, row.dayKey == row.item.firstDayKey else { return nil }
        return text(start, template: "jmm")
    }

    func subtitle(for row: Row) -> String {
        let item = row.item
        var parts: [String] = []
        switch item.kind {
        case .task:
            parts.append(String(localized: "Due"))
        case .event:
            if let start = startTime(for: row) {
                parts.append(start)
            } else {
                parts.append(String(localized: "All day"))
            }
        }
        if !item.detail.isEmpty { parts.append(item.detail) }
        return parts.joined(separator: " · ")
    }

    func tint(for item: AgendaWidgetItem) -> Color {
        switch item.kind {
        case .event: EventColor(rawValue: item.tint)?.color ?? .blue
        case .task: TaskPriority(rawValue: item.tint)?.color ?? .gray
        }
    }
}

struct AgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaWidgetEntry

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        let presentation = AgendaPresentation(entry: entry)
        VStack(alignment: .leading, spacing: presentation.isDense ? (isLarge ? 10 : 5) : (isLarge ? 12 : 7)) {
            AgendaHeader(presentation: presentation, isLarge: isLarge)
            switch entry.status {
            case .signedOut:
                message(String(localized: "Open Workavera to sign in."), systemImage: "person.crop.circle.badge.exclamationmark")
            case .unavailable:
                message(String(localized: "Couldn't reach your server."), systemImage: "wifi.exclamationmark")
            case .ready where presentation.rows.isEmpty:
                message(String(localized: "Nothing coming up."), systemImage: "checkmark.circle")
            case .ready:
                if isLarge {
                    LargeAgendaList(presentation: presentation)
                } else {
                    CompactAgendaList(presentation: presentation)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Eight rows on medium only fit with slightly tighter vertical margins.
        .padding(.horizontal, 16)
        .padding(.vertical, isLarge || !presentation.isDense ? 16 : 10)
        .widgetURL(AgendaWidgetStore.calendarURL)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct AgendaHeader: View {
    let presentation: AgendaPresentation
    let isLarge: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "Workavera")
                    .font(isLarge ? .headline : .caption.weight(.semibold))
                Text(presentation.text(presentation.today, template: "MMMdEEE"))
                    .font(isLarge ? .subheadline : .caption2)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 2)
            if let updatedAt = presentation.updatedAt {
                Text(presentation.text(updatedAt, template: "jmm"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Link(destination: AgendaWidgetStore.chatURL) {
                    HeaderButtonLabel(systemName: "sparkles", tint: .purple, isLarge: isLarge)
                }
                .accessibilityLabel(Text("Open Chat"))
                Button(intent: RefreshAgendaIntent()) {
                    HeaderButtonLabel(systemName: "arrow.clockwise", tint: .secondary, isLarge: isLarge)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Refresh"))
            }
            // Let the buttons reach into the margins so they are easy to hit
            // without pushing the list down.
            .padding(.vertical, -5)
        }
    }
}

/// A round, comfortably sized tap target for the header actions.
private struct HeaderButtonLabel: View {
    let systemName: String
    let tint: Color
    let isLarge: Bool

    var body: some View {
        let size: CGFloat = isLarge ? 34 : 30
        Image(systemName: systemName)
            .font(.system(size: isLarge ? 15 : 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.14)))
            .contentShape(Circle())
    }
}

/// Medium: one line per item — date, color bar, title, start time.
private struct CompactAgendaList: View {
    let presentation: AgendaPresentation

    var body: some View {
        let dense = presentation.isDense
        VStack(alignment: .leading, spacing: dense ? 2 : 3) {
            ForEach(presentation.rows) { row in
                HStack(spacing: 6) {
                    Text(presentation.dateLabel(for: row))
                        .font(.system(size: dense ? 10.5 : 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(presentation.isToday(row) ? Color.red : Color.secondary)
                        .lineLimit(1)
                        .frame(width: 70, alignment: .leading)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(presentation.tint(for: row.item))
                        .frame(width: 3, height: dense ? 11 : 12)
                    TitleText(item: row.item, font: .system(size: dense ? 12 : 13))
                    Spacer(minLength: 4)
                    if let time = presentation.startTime(for: row) {
                        Text(time)
                            .font(.system(size: dense ? 10.5 : 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: dense ? 13.5 : 15)
            }
        }
    }
}

/// Large: a date badge and two lines per item.
private struct LargeAgendaList: View {
    let presentation: AgendaPresentation

    var body: some View {
        let dense = presentation.isDense
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 46)
                }
                HStack(spacing: 10) {
                    VStack(spacing: 0) {
                        Text(verbatim: "\(presentation.calendar.component(.day, from: row.date))")
                            .font(.system(size: dense ? 18 : 20, weight: .semibold))
                            .monospacedDigit()
                        Text(presentation.text(row.date, template: "EEE"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(presentation.isToday(row) ? Color.red : Color.primary)
                    .frame(width: 36)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(presentation.tint(for: row.item))
                        .frame(width: 3, height: dense ? 26 : 30)
                    VStack(alignment: .leading, spacing: dense ? 1 : 2) {
                        TitleText(item: row.item, font: dense ? .footnote.weight(.medium) : .subheadline.weight(.medium))
                        Text(presentation.subtitle(for: row))
                            .font(dense ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: dense ? 37 : 46)
            }
        }
    }
}

/// The item title, with a to-do circle in front of tasks.
private struct TitleText: View {
    let item: AgendaWidgetItem
    let font: Font

    var body: some View {
        HStack(spacing: 3) {
            if item.kind == .task {
                Image(systemName: "circle")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(font)
                .lineLimit(1)
        }
    }
}
