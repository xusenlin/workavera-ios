import SwiftUI
import WidgetKit

/// Everything the widget shows for one entry, derived from the snapshot.
private struct AgendaPresentation {
    struct Row: Identifiable {
        let item: AgendaWidgetItem
        /// The day the row is listed under (today for events already in progress).
        let dayKey: String

        var id: String { item.id }
    }

    let calendar: Calendar
    let today: Date
    let todayKey: String
    let markedDays: Set<String>
    let rows: [Row]
    let nextUp: Row?
    let updatedAt: Date?

    init(entry: AgendaWidgetEntry) {
        var calendar = entry.snapshot?.calendar ?? Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        let formatter = AgendaWidgetSnapshot.dayFormatter(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: entry.date)
        let weekKeys = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map(formatter.string(from:))
        }
        let todayKey = weekKeys.first ?? formatter.string(from: today)
        let weekEndKey = weekKeys.last ?? todayKey

        let items = (entry.snapshot?.items ?? []).filter(entry.content.includes)
        var rows: [Row] = []
        var nextUp: Row?
        for item in items {
            if let dayKey = item.dayKeys.first(where: { $0 >= todayKey && $0 <= weekEndKey }) {
                rows.append(Row(item: item, dayKey: dayKey))
            } else if nextUp == nil, item.firstDayKey > weekEndKey {
                nextUp = Row(item: item, dayKey: item.firstDayKey)
            }
        }

        self.calendar = calendar
        self.today = today
        self.todayKey = todayKey
        self.markedDays = Set(items.flatMap(\.dayKeys))
        self.rows = rows.sorted { $0.dayKey < $1.dayKey }
        self.nextUp = nextUp
        self.updatedAt = entry.snapshot?.updatedAt
    }

    func date(forKey key: String) -> Date? {
        AgendaWidgetSnapshot.dayFormatter(timeZone: calendar.timeZone).date(from: key)
    }

    func text(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    func dayLabel(forKey key: String) -> String {
        guard let date = date(forKey: key) else { return key }
        let days = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case 2..<7: return text(date, template: "EEE")
        default: return text(date, template: "MMMd")
        }
    }

    func subtitle(for row: Row) -> String {
        let item = row.item
        var parts: [String] = []
        switch item.kind {
        case .task:
            parts.append(String(localized: "Due \(dayLabel(forKey: row.dayKey))"))
        case .event:
            parts.append(dayLabel(forKey: row.dayKey))
            if item.allDay {
                parts.append(String(localized: "All day"))
            } else if let start = item.startAt, row.dayKey == item.firstDayKey {
                parts.append(text(start, template: "jmm"))
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
        HStack(alignment: .top, spacing: isLarge ? 14 : 12) {
            VStack(alignment: .leading, spacing: isLarge ? 10 : 4) {
                if isLarge {
                    TodayHeader(presentation: presentation)
                }
                MonthGrid(presentation: presentation, isLarge: isLarge)
            }
            .frame(width: isLarge ? 150 : 128, alignment: .leading)

            AgendaList(
                presentation: presentation,
                status: entry.status,
                maxRows: isLarge ? 9 : 3
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TodayHeader: View {
    let presentation: AgendaPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.text(presentation.today, template: "EEEE"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text(presentation.text(presentation.today, template: "d"))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
        }
    }
}

private struct MonthGrid: View {
    let presentation: AgendaPresentation
    let isLarge: Bool

    private var calendar: Calendar { presentation.calendar }

    /// Leading blanks, then each day of the month, padded to whole weeks.
    private var cells: [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: presentation.today),
              let days = calendar.range(of: .day, in: .month, for: presentation.today) else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in days {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: month.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        let cells = cells
        let cellHeight: CGFloat = isLarge ? 22 : 14
        VStack(alignment: .leading, spacing: isLarge ? 6 : 3) {
            Text(presentation.text(presentation.today, template: isLarge ? "MMMMyyyy" : "MMMM"))
                .font(isLarge ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(isLarge ? .primary : Color.red)

            Grid(horizontalSpacing: 0, verticalSpacing: isLarge ? 3 : 1) {
                GridRow {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: isLarge ? 10 : 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<(cells.count / 7), id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            DayCell(
                                date: cells[week * 7 + column],
                                presentation: presentation,
                                isLarge: isLarge
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: cellHeight)
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date?
    let presentation: AgendaPresentation
    let isLarge: Bool

    var body: some View {
        if let date {
            let key = AgendaWidgetSnapshot.dayFormatter(timeZone: presentation.calendar.timeZone).string(from: date)
            let isToday = key == presentation.todayKey
            let isPast = key < presentation.todayKey
            let isMarked = presentation.markedDays.contains(key)
            let size: CGFloat = isLarge ? 18 : 12
            VStack(spacing: isLarge ? 1 : 0) {
                Text("\(presentation.calendar.component(.day, from: date))")
                    .font(.system(size: isLarge ? 11 : 8.5, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color(uiColor: .systemBackground) : (isPast ? Color.secondary : Color.primary))
                    .frame(width: size, height: size)
                    .background {
                        if isToday { Circle().fill(Color.red) }
                    }
                Circle()
                    .fill(isMarked ? Color.secondary : Color.clear)
                    .frame(width: isLarge ? 3.5 : 2.5, height: isLarge ? 3.5 : 2.5)
            }
        } else {
            Color.clear
        }
    }
}

private struct AgendaList: View {
    let presentation: AgendaPresentation
    let status: AgendaWidgetEntry.Status
    let maxRows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            switch status {
            case .signedOut:
                message(String(localized: "Open Workavera to sign in."), systemImage: "person.crop.circle.badge.exclamationmark")
            case .unavailable:
                message(String(localized: "Couldn't reach your server."), systemImage: "wifi.exclamationmark")
            case .ready:
                if presentation.rows.isEmpty {
                    emptyWeek
                } else {
                    rows
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Next 7 Days")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let updatedAt = presentation.updatedAt {
                Text(presentation.text(updatedAt, template: "jmm"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Button(intent: RefreshAgendaIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Refresh"))
        }
    }

    private var rows: some View {
        let visible = presentation.rows.prefix(maxRows)
        let hidden = presentation.rows.count - visible.count
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(visible) { row in
                AgendaRow(row: row, presentation: presentation)
            }
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 9)
            }
        }
    }

    private var emptyWeek: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Nothing in the next 7 days", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let next = presentation.nextUp {
                Text("Next up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                AgendaRow(row: next, presentation: presentation)
            }
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct AgendaRow: View {
    let row: AgendaPresentation.Row
    let presentation: AgendaPresentation

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(presentation.tint(for: row.item))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if row.item.kind == .task {
                        Image(systemName: "circle")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(row.item.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                Text(presentation.subtitle(for: row))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 26)
    }
}
