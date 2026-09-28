import SwiftUI
import CoreData
import Charts

/// The span of time the History screen summarizes.
enum OverviewPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// Every activity for a day, week or month: totals, charts and the full log.
struct HistoryView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var fetchedEntries: FetchedResults<BabyEntry>

    private var entries: [BabyEntry] { Array(fetchedEntries) }

    @State private var period: OverviewPeriod = .day
    /// Any date inside the period being shown.
    @State private var anchor = Date.now
    @State private var filter: EntryKind?
    @State private var editingEntry: BabyEntry?

    init(baby: Baby, period: OverviewPeriod = .day) {
        self.baby = baby
        _fetchedEntries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby))
        _period = State(initialValue: period)
    }

    private var calendar: Calendar { .current }

    private var interval: DateInterval {
        calendar.dateInterval(of: period.component, for: anchor) ?? DateInterval(start: anchor, duration: 86_400)
    }

    private var isCurrentPeriod: Bool {
        interval.contains(.now)
    }

    /// Entries that start in the period, plus sleeps that run into it from before.
    private var periodEntries: [BabyEntry] {
        entries.filter { entry in
            if interval.contains(entry.timestamp) { return true }
            if entry.kind == .sleep, entry.timestamp < interval.start {
                return (entry.endTime ?? .now) > interval.start
            }
            return false
        }
    }

    /// Entries grouped by calendar day for the log, newest day first.
    private var groupedEntries: [(day: Date, entries: [BabyEntry])] {
        let filtered = periodEntries.filter { (filter == nil || $0.kind == filter) && interval.contains($0.timestamp) }
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.timestamp) }
        return groups
            .map { (day: $0.key, entries: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(OverviewPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    PeriodNavigator(
                        title: periodTitle,
                        canGoForward: !isCurrentPeriod,
                        onBack: { move(by: -1) },
                        onForward: { move(by: 1) },
                        onToday: isCurrentPeriod ? nil : { anchor = .now }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }

                let summary = PeriodSummary(entries: periodEntries, interval: interval)

                if period == .day {
                    Section("Totals") {
                        TodayTotalsView(entries: periodEntries.filter { interval.contains($0.timestamp) })
                    }
                    Section {
                        DayTimelineChart(entries: periodEntries, interval: interval)
                    } header: {
                        Text("Timeline")
                    } footer: {
                        Text("Bars show sleeps and timed feeds. Dots show feeds and diapers.")
                    }
                } else {
                    Section("Daily Average") {
                        HStack(alignment: .top) {
                            TotalView(title: "Feeds", value: summary.averageFeeds, caption: "per day",
                                      color: EntryKind.feed.textColor)
                            TotalView(title: "Sleep", value: summary.averageSleep, caption: "per day",
                                      color: EntryKind.sleep.textColor)
                            TotalView(title: "Diapers", value: summary.averageDiapers, caption: "per day",
                                      color: EntryKind.diaper.textColor)
                        }
                        .padding(.vertical, 4)
                    }

                    // One chart per measure: they have different units, so they never share an axis.
                    Section("Feeds per Day") {
                        DailyBarChart(summary: summary, kind: .feed, unit: "feeds") { $0.feeds }
                    }
                    Section("Sleep per Day") {
                        DailyBarChart(summary: summary, kind: .sleep, unit: "hours") { $0.sleepHours }
                    }
                    Section("Diapers per Day") {
                        DailyBarChart(summary: summary, kind: .diaper, unit: "diapers") { Double($0.diapers) }
                    }
                }

                if groupedEntries.isEmpty {
                    Section {
                        ContentUnavailableView(
                            filter.map { "No \($0.title) Entries" } ?? "No Entries",
                            systemImage: filter?.symbol ?? "tray",
                            description: Text("Nothing was logged in this \(period.rawValue.lowercased()).")
                        )
                    }
                } else {
                    ForEach(groupedEntries, id: \.day) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                EntryRow(entry: entry)
                                    .entryActions(entry: entry, onEdit: { editingEntry = entry })
                            }
                        } header: {
                            Text(group.day, format: .dateTime.weekday(.wide).month().day())
                        }
                    }
                }
            }
            .themedBackground()
            .funNavigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Show in Log", selection: $filter) {
                            Label("All Entries", systemImage: "square.stack").tag(EntryKind?.none)
                            ForEach(EntryKind.allCases) { kind in
                                Label(kind.title, systemImage: kind.symbol).tag(EntryKind?.some(kind))
                            }
                        }
                    } label: {
                        // Filled symbol signals that a filter is active.
                        Label(
                            "Filter",
                            systemImage: filter == nil
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                EntryFormView(entry: entry)
            }
        }
    }

    private var periodTitle: String {
        switch period {
        case .day:
            if calendar.isDateInToday(anchor) { return "Today" }
            if calendar.isDateInYesterday(anchor) { return "Yesterday" }
            return anchor.formatted(.dateTime.weekday(.wide).month().day())
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        }
    }

    private func move(by value: Int) {
        guard let next = calendar.date(byAdding: period.component, value: value, to: anchor) else { return }
        withAnimation { anchor = min(next, .now) }
    }
}

/// "‹  Sep 21 – 27  ›" with an optional "Today" shortcut.
private struct PeriodNavigator: View {
    let title: String
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onToday: (() -> Void)?

    var body: some View {
        HStack {
            Button("Previous", systemImage: "chevron.left", action: onBack)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            Spacer()
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                if let onToday {
                    Button("Back to Today", action: onToday)
                        .font(.caption)
                }
            }
            Spacer()
            Button("Next", systemImage: "chevron.right", action: onForward)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!canGoForward)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}

// MARK: - Summary math

/// Per-day totals for a week or month.
struct DaySummary: Identifiable {
    let day: Date
    var feeds: Double = 0
    var sleepHours: Double = 0
    var diapers: Int = 0

    var id: Date { day }
}

struct PeriodSummary {
    /// Every day in the period, including future days (which stay empty) so charts keep a stable axis.
    let days: [DaySummary]
    let interval: DateInterval

    init(entries: [BabyEntry], interval: DateInterval) {
        self.interval = interval
        let calendar = Calendar.current
        var days: [DaySummary] = []
        var day = interval.start
        while day < interval.end {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let dayInterval = DateInterval(start: day, end: dayEnd)
            var summary = DaySummary(day: day)

            let feedStarts = entries
                .filter { $0.kind == .feed && dayInterval.contains($0.timestamp) }
                .map(\.timestamp)
            summary.feeds = Double(WhatsNextPlanner.sessionCount(feedStarts))

            // Sleep is split at midnight so each day gets the hours actually slept in it.
            summary.sleepHours = entries
                .filter { $0.kind == .sleep }
                .reduce(0) { total, sleep in
                    let sleepInterval = DateInterval(start: sleep.timestamp, end: max(sleep.endTime ?? .now, sleep.timestamp))
                    return total + (sleepInterval.intersection(with: dayInterval)?.duration ?? 0) / 3600
                }

            summary.diapers = entries.filter { $0.kind == .diaper && dayInterval.contains($0.timestamp) }.count
            days.append(summary)
            day = dayEnd
        }
        self.days = days
    }

    /// Days up to and including today, so averages aren't diluted by the future.
    private var elapsedDays: [DaySummary] {
        days.filter { $0.day <= .now }
    }

    private var dayCount: Double { Double(max(elapsedDays.count, 1)) }

    var averageFeeds: String {
        (elapsedDays.map(\.feeds).reduce(0, +) / dayCount).formatted(.number.precision(.fractionLength(0...1)))
    }

    var averageSleep: String {
        BabyEntry.format(elapsedDays.map(\.sleepHours).reduce(0, +) / dayCount * 3600)
    }

    var averageDiapers: String {
        (Double(elapsedDays.map(\.diapers).reduce(0, +)) / dayCount).formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension WhatsNextPlanner {
    /// Number of feeding sessions, merging entries less than 30 minutes apart (such as switching sides).
    static func sessionCount(_ starts: [Date]) -> Int {
        var count = 0
        var last: Date?
        for start in starts.sorted() {
            if let last, start.timeIntervalSince(last) < 30 * 60 { continue }
            count += 1
            last = start
        }
        return count
    }
}

// MARK: - Charts

/// A single-measure bar chart with one bar per day and a tap/drag tooltip.
private struct DailyBarChart: View {
    let summary: PeriodSummary
    let kind: EntryKind
    let unit: String
    let value: (DaySummary) -> Double

    @State private var selectedDay: Date?

    private var days: [DaySummary] { summary.days }

    private var selected: DaySummary? {
        guard let selectedDay else { return nil }
        return days.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private func formatted(_ amount: Double) -> String {
        kind == .sleep
            ? BabyEntry.format(amount * 3600)
            : "\(amount.formatted(.number.precision(.fractionLength(0)))) \(unit)"
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value(unit.capitalized, value(day)),
                    width: .ratio(0.6)
                )
                .cornerRadius(4, style: .continuous)
                .foregroundStyle(kind.textColor)
                .opacity(selected == nil || selected?.id == day.id ? 1 : 0.35)
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                .accessibilityValue(formatted(value(day)))
            }

            if let selected {
                RuleMark(x: .value("Day", selected.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(selected.day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatted(value(selected)))
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartXScale(domain: summary.interval.start...summary.interval.end)
        .chartXAxis {
            // Every day for a week; weekly ticks for a month so labels don't collide.
            AxisMarks(values: .stride(by: .day, count: days.count > 7 ? 7 : 1)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(format: days.count > 7 ? .dateTime.day() : .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel()
            }
        }
        .frame(height: 160)
        .padding(.top, 28) // Room for the tooltip above the tallest bar.
        .padding(.vertical, 4)
    }
}

/// One day on a 24-hour axis, with a lane each for feeds, sleep and diapers.
private struct DayTimelineChart: View {
    let entries: [BabyEntry]
    let interval: DateInterval

    private struct Span: Identifiable {
        let id: UUID
        let lane: EntryKind
        let start: Date
        let end: Date
    }

    private struct Point: Identifiable {
        let id: UUID
        let lane: EntryKind
        let time: Date
    }

    private var spans: [Span] {
        entries.compactMap { entry in
            guard entry.kind == .sleep || (entry.kind == .feed && (entry.endTime != nil || entry.isOngoingFeed)) else { return nil }
            let start = max(entry.timestamp, interval.start)
            let end = min(entry.endTime ?? .now, interval.end)
            guard end > start else { return nil }
            // Very short feeds still get a visible bar.
            return Span(id: entry.entryID, lane: entry.kind, start: start, end: max(end, start.addingTimeInterval(8 * 60)))
        }
    }

    private var points: [Point] {
        entries.compactMap { entry in
            guard interval.contains(entry.timestamp) else { return nil }
            let isUntimedFeed = entry.kind == .feed && entry.endTime == nil && !entry.isOngoingFeed
            guard isUntimedFeed || entry.kind == .diaper else { return nil }
            return Point(id: entry.entryID, lane: entry.kind, time: entry.timestamp)
        }
    }

    private static let lanes: [EntryKind] = [.feed, .sleep, .diaper]

    var body: some View {
        Chart {
            ForEach(spans) { span in
                BarMark(
                    xStart: .value("Start", span.start),
                    xEnd: .value("End", span.end),
                    y: .value("Activity", span.lane.title),
                    height: .fixed(14)
                )
                .cornerRadius(4, style: .continuous)
                .foregroundStyle(span.lane.textColor)
                .accessibilityLabel(span.lane.title)
                .accessibilityValue("\(span.start.formatted(date: .omitted, time: .shortened)) to \(span.end.formatted(date: .omitted, time: .shortened))")
            }
            ForEach(points) { point in
                PointMark(
                    x: .value("Time", point.time),
                    y: .value("Activity", point.lane.title)
                )
                .symbolSize(90)
                .foregroundStyle(point.lane.textColor)
                .accessibilityLabel(point.lane.title)
                .accessibilityValue(point.time.formatted(date: .omitted, time: .shortened))
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: Self.lanes.map(\.title))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            // Lane names identify each row, so color isn't the only cue.
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
            }
        }
        .frame(height: 150)
        .padding(.vertical, 8)
    }
}

/// Created once so the preview never reads from a released store.
@MainActor
private let sampleHistoryStore: PersistenceController = {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let baby = Baby(context: context, name: "Ava", birthday: .now.addingTimeInterval(-10 * 7 * 86_400), gender: .girl)
    let hour: TimeInterval = 3600
    let start = Calendar.current.startOfDay(for: .now)
    for dayOffset in 1..<8 {
        let day = start.addingTimeInterval(-Double(dayOffset) * 24 * hour)
        for feed in stride(from: 1.0, to: 23, by: 3) {
            _ = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: day.addingTimeInterval(feed * hour), feedType: .formula, amountML: 120)
        }
        for diaper in stride(from: 2.0, to: 22, by: 4) {
            _ = BabyEntry(context: context, baby: baby, kind: .diaper, timestamp: day.addingTimeInterval(diaper * hour), diaperType: .wet)
        }
        _ = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: day.addingTimeInterval(9 * hour), endTime: day.addingTimeInterval(10.5 * hour))
        _ = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: day.addingTimeInterval(13 * hour), endTime: day.addingTimeInterval(15 * hour))
    }
    persistence.save()
    return persistence
}()

#Preview("Day") {
    HistoryView(baby: PreviewStore.firstBaby(in: sampleHistoryStore))
        .environment(\.managedObjectContext, sampleHistoryStore.viewContext)
}

#Preview("Week") {
    HistoryView(baby: PreviewStore.firstBaby(in: sampleHistoryStore), period: .week)
        .environment(\.managedObjectContext, sampleHistoryStore.viewContext)
}
