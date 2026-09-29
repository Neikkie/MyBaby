import CoreData
import FoundationModels
import SwiftUI
import UserNotifications

// MARK: - Today card

/// "What's Next" on Today: the next few things due, predicted or from the parent's own schedule.
struct WhatsNextCard: View {
    @ObservedObject var baby: Baby
    let entries: [BabyEntry]
    let todaysEntries: [BabyEntry]
    let onTap: (EntryKind) -> Void
    let onOpenHistory: () -> Void

    @FetchRequest private var schedule: FetchedResults<ScheduleItem>

    init(baby: Baby, entries: [BabyEntry], todaysEntries: [BabyEntry],
         onTap: @escaping (EntryKind) -> Void, onOpenHistory: @escaping () -> Void) {
        self.baby = baby
        self.entries = entries
        self.todaysEntries = todaysEntries
        self.onTap = onTap
        self.onOpenHistory = onOpenHistory
        _schedule = FetchRequest(fetchRequest: ScheduleItem.fetch(for: baby))
    }

    var body: some View {
        Card {
            HStack {
                Text("What's Next")
                    .font(.headline)
                    .fontDesign(.rounded)
                Spacer()
                NavigationLink {
                    DayPlanView(baby: baby)
                } label: {
                    Text("See Plan")
                        .font(.subheadline.weight(.semibold))
                }
            }

            TimelineView(.everyMinute) { context in
                let age = BabyAge(birthdayInterval: baby.birthdayInterval)
                let predictor = SchedulePredictor(entries: entries, schedule: Array(schedule), age: age, now: context.date)
                let upcoming = predictor.plan().items.filter { !$0.isDone }
                // One row per schedule: feeding, sleep and diapers, each with what's next and what follows.
                VStack(spacing: 0) {
                    ForEach([EntryKind.feed, .sleep, .diaper]) { kind in
                        let items = upcoming.filter { $0.kind == kind }
                        ScheduleLane(
                            kind: kind,
                            label: TileStage.forKind(kind, age: age).label,
                            next: items.first,
                            then: items.dropFirst().first,
                            now: context.date
                        ) { onTap(kind) }
                        if kind != .diaper {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }

            if !todaysEntries.isEmpty {
                Divider()
                Button(action: onOpenHistory) {
                    HStack(spacing: 6) {
                        Text("Today")
                            .fontWeight(.semibold)
                        Text(Self.summary(of: todaysEntries))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentShape(.rect)
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityLabel("Today: \(Self.summary(of: todaysEntries))")
                .accessibilityHint("Opens History")
            }
        }
    }

    /// "3 feeds · 1h 30m sleep · 2 diapers"
    static func summary(of entries: [BabyEntry]) -> String {
        let feeds = WhatsNextPlanner.sessionCount(entries.filter { $0.kind == .feed }.map(\.timestamp))
        let sleep = entries.filter { $0.kind == .sleep }.compactMap(\.duration).reduce(0, +)
        let diapers = entries.filter { $0.kind == .diaper }.count
        var parts: [String] = []
        if feeds > 0 { parts.append(feeds == 1 ? "1 feed" : "\(feeds) feeds") }
        if sleep > 0 { parts.append("\(BabyEntry.format(sleep)) sleep") }
        if diapers > 0 { parts.append(diapers == 1 ? "1 diaper" : "\(diapers) diapers") }
        return parts.joined(separator: " · ")
    }
}

/// One of the three schedules on Today: the next feed, sleep or diaper change, and the one after.
private struct ScheduleLane: View {
    let kind: EntryKind
    let label: String
    let next: PlannedItem?
    let then: PlannedItem?
    let now: Date
    let action: () -> Void

    private var isDue: Bool {
        guard let next else { return false }
        return next.isRunning || next.time.timeIntervalSince(now) < 10 * 60
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.headline)
                    .foregroundStyle(kind.textColor)
                    .frame(width: 44, height: 44)
                    .background(kind.softColor, in: .rect(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                        if next?.source == .schedule {
                            Text("Plan")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .foregroundStyle(kind.textColor)
                                .background(kind.softColor, in: .capsule)
                        }
                    }
                    if let next {
                        Text(status(for: next))
                            .font(.caption)
                            .foregroundStyle(isDue ? kind.textColor : .secondary)
                            .lineLimit(1)
                    } else {
                        Text("Log one to see the schedule")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let next {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(next.isRunning ? "Now" : next.time.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(isDue ? kind.textColor : .primary)
                        if let then {
                            Text("then \(then.time.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens quick options to log")
    }

    /// "Next feed · in 40m", "Bedtime · due now", "Asleep · likely waking in 20m".
    private func status(for item: PlannedItem) -> String {
        if item.isRunning {
            return item.kind == .sleep ? "Asleep · likely waking \(WhatsNextPlanner.dueText(for: item.time, now: now))" : item.title
        }
        return "\(item.title) · \(WhatsNextPlanner.dueText(for: item.time, now: now))"
    }

    private var accessibilityText: String {
        guard let next else { return "\(label): nothing scheduled yet" }
        var text = "\(label): \(status(for: next)), \(next.time.formatted(date: .omitted, time: .shortened))"
        if let then { text += ", then \(then.time.formatted(date: .omitted, time: .shortened))" }
        return text
    }
}

/// One planned item: time, icon, what it is, and when it's due.
struct PlanRow: View {
    let item: PlannedItem
    let now: Date
    var isCompact = false
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 12) {
            Text(item.time, format: .dateTime.hour().minute())
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .frame(width: 72, alignment: .leading)

            Image(systemName: item.isDone ? "checkmark" : item.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.kind.textColor)
                .frame(width: 34, height: 34)
                .background(item.kind.softColor, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(item.isDone)
                    if item.source == .schedule {
                        Text("Plan")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .foregroundStyle(item.kind.textColor)
                            .background(item.kind.softColor, in: .capsule)
                    }
                }
                Text(isCompact ? dueText : "\(dueText) · \(item.reason)")
                    .font(.caption)
                    .foregroundStyle(isDue ? item.kind.textColor : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.time.formatted(date: .omitted, time: .shortened)), \(dueText)")

        if let action {
            Button(action: action) { content }
                .buttonStyle(SquishButtonStyle())
        } else {
            content
        }
    }

    private var isDue: Bool {
        !item.isDone && (item.isRunning || item.time.timeIntervalSince(now) < 10 * 60)
    }

    private var dueText: String {
        if item.isDone { return "Done" }
        if item.isRunning { return item.title == "Feeding now" ? item.reason : "In progress · \(WhatsNextPlanner.dueText(for: item.time, now: now))" }
        return WhatsNextPlanner.dueText(for: item.time, now: now)
    }
}

// MARK: - Full plan

/// The rest of the day, why it's predicted that way, an Apple Intelligence summary, and the parent's schedule.
struct DayPlanView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var entries: FetchedResults<BabyEntry>
    @FetchRequest private var schedule: FetchedResults<ScheduleItem>

    init(baby: Baby) {
        self.baby = baby
        _entries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby, limit: 600))
        _schedule = FetchRequest(fetchRequest: ScheduleItem.fetch(for: baby))
    }

    private var age: BabyAge? { BabyAge(birthdayInterval: baby.birthdayInterval) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let predictor = SchedulePredictor(entries: Array(entries), schedule: Array(schedule), age: age, now: context.date)
            let plan = predictor.plan()
            List {
                Section {
                    AIInsightCard(facts: Self.facts(for: baby, age: age, summary: plan.summary, items: plan.items))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    let upcoming = plan.items.filter { !$0.isDone }
                    if upcoming.isEmpty {
                        Text("Nothing predicted yet. Keep logging and \(baby.displayName)'s rhythm will show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { item in
                        PlanRow(item: item, now: context.date)
                    }
                } header: {
                    Text("Next 12 Hours")
                } footer: {
                    Text("Predictions are estimates from \(baby.displayName)'s log and what's typical at this age. Every baby is different.")
                }

                let done = plan.items.filter(\.isDone)
                if !done.isEmpty {
                    Section("Done Today") {
                        ForEach(done) { item in
                            PlanRow(item: item, now: context.date)
                        }
                    }
                }

                Section {
                    PatternRows(summary: plan.summary, age: age)
                } header: {
                    Text("What We've Learned")
                } footer: {
                    Text(plan.summary.daysOfData >= 5
                         ? "Based on \(plan.summary.daysOfData) days of logs."
                         : "Based on \(plan.summary.daysOfData) day\(plan.summary.daysOfData == 1 ? "" : "s") of logs. Predictions get more personal after about 5 days.")
                }

                Section {
                    NavigationLink {
                        ScheduleEditorView(baby: baby)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Schedule")
                                Text(schedule.isEmpty ? "Create your own daily plan" : "\(schedule.count) item\(schedule.count == 1 ? "" : "s") · replaces predictions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar.badge.clock")
                        }
                    }
                }
            }
            .themedBackground()
        }
        .navigationTitle("\(baby.displayName)'s Day")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Plain facts for Apple Intelligence to summarize. The numbers come from the predictor, not the model.
    static func facts(for baby: Baby, age: BabyAge?, summary: PatternSummary, items: [PlannedItem]) -> String {
        var lines: [String] = ["Baby: \(baby.displayName)."]
        if let age { lines.append("Age: \(age.weeksDescription) (\(age.stageName.lowercased())).") }
        lines.append("Days of logs: \(summary.daysOfData).")
        if let feeds = summary.feedsPerDay { lines.append("Feeds per day: about \(Int(feeds.rounded())).") }
        if let gap = summary.dayFeedGap { lines.append("Daytime feeds about every \(BabyEntry.format(gap)).") }
        if let sleep = summary.sleepPerDay { lines.append("Sleep logged per day: about \(BabyEntry.format(sleep)).") }
        if let nap = summary.napLength { lines.append("Naps last about \(BabyEntry.format(nap)).") }
        if let window = summary.wakeWindow { lines.append("Awake about \(BabyEntry.format(window)) between sleeps.") }
        if let bedtime = summary.bedtimeMinute {
            let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(bedtime * 60))
            lines.append("Usual bedtime: \(date.formatted(date: .omitted, time: .shortened)).")
        }
        if let next = items.first(where: { !$0.isDone && !$0.isRunning }) {
            lines.append("Next up: \(next.title) around \(next.time.formatted(date: .omitted, time: .shortened)).")
        }
        return lines.joined(separator: "\n")
    }
}

/// Plain-language rows showing what the predictor has learned.
private struct PatternRows: View {
    let summary: PatternSummary
    let age: BabyAge?

    var body: some View {
        LabeledContent("Confidence") {
            Text(summary.confidence.rawValue)
                .foregroundStyle(summary.confidence == .confident ? EntryKind.diaper.textColor : .secondary)
        }
        if let gap = summary.dayFeedGap {
            LabeledContent("Feeds (daytime)", value: "every \(BabyEntry.format(gap))")
        }
        if let gap = summary.nightFeedGap {
            LabeledContent("Feeds (night)", value: "every \(BabyEntry.format(gap))")
        }
        if let window = summary.wakeWindow {
            LabeledContent("Awake time", value: BabyEntry.format(window))
        }
        if let nap = summary.napLength {
            LabeledContent("Typical nap", value: BabyEntry.format(nap))
        }
        if let bedtime = summary.bedtimeMinute {
            LabeledContent("Usual bedtime",
                           value: Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(bedtime * 60))
                .formatted(date: .omitted, time: .shortened))
        }
        if let sleep = summary.sleepPerDay {
            LabeledContent("Sleep per day", value: BabyEntry.format(sleep))
        }
        if let gap = summary.diaperGap {
            LabeledContent("Diaper changes", value: "every \(BabyEntry.format(gap))")
        }
    }
}

// MARK: - Apple Intelligence

/// A short daily summary written by the on-device model from the predictor's facts.
@Generable
struct DailyInsight {
    @Guide(description: "A warm headline of at most six words")
    var headline: String
    @Guide(description: "One or two short sentences describing the baby's recent routine, using only the facts given")
    var summary: String
    @Guide(description: "One gentle, practical, non-medical tip for today, in one sentence")
    var tip: String
}

private struct AIInsightCard: View {
    let facts: String

    @State private var insight: DailyInsight?
    @State private var failed = false
    @Environment(\.appTheme) private var theme

    private let model = SystemLanguageModel.default

    var body: some View {
        switch model.availability {
        case .available:
            VStack(alignment: .leading, spacing: 10) {
                Label("Today's Insight", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                if let insight {
                    Text(insight.headline)
                        .font(.title3.bold())
                        .fontDesign(.rounded)
                    Text(insight.summary)
                        .font(.subheadline)
                    Label(insight.tip, systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if failed {
                    Text("Couldn't write today's insight. Your predictions below are still up to date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Thinking about today…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Written by Apple Intelligence on your device. May be inaccurate; not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 22, style: .continuous))
            .task(id: facts) { await generate() }
            .animation(.smooth, value: insight?.headline)
        default:
            // Apple Intelligence isn't available on this device; the predictions work without it.
            EmptyView()
        }
    }

    private func generate() async {
        failed = false
        let session = LanguageModelSession(instructions: """
            You help parents understand their baby's daily routine. Use only the facts provided and never invent numbers. \
            Be warm, encouraging and brief. Never give medical advice or diagnoses; if something could be a concern, \
            suggest checking with their pediatrician.
            """)
        do {
            let response = try await session.respond(to: facts, generating: DailyInsight.self)
            insight = response.content
        } catch {
            failed = true
        }
    }
}

// MARK: - Schedule editor

/// The parent's own daily schedule. Items repeat every day and can remind you.
struct ScheduleEditorView: View {
    @ObservedObject var baby: Baby
    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var items: FetchedResults<ScheduleItem>
    @FetchRequest private var entries: FetchedResults<BabyEntry>

    @State private var editing: ScheduleItem?
    @State private var isAdding = false
    @State private var isConfirmingReplace = false

    init(baby: Baby) {
        self.baby = baby
        _items = FetchRequest(fetchRequest: ScheduleItem.fetch(for: baby))
        _entries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby, limit: 600))
    }

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("No Schedule Yet", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("Add your own times, or start from a schedule suggested from \(baby.displayName)'s rhythm.")
                    }
                }
                ForEach(items) { item in
                    Button { editing = item } label: {
                        ScheduleRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            withAnimation {
                                context.delete(item)
                                save()
                            }
                        }
                    }
                }
            } footer: {
                if !items.isEmpty {
                    Text("Your schedule replaces predictions for the same kind of activity. It's shared with anyone \(baby.displayName)'s log is shared with.")
                }
            }

            Section {
                Button("Suggest a Schedule", systemImage: "sparkles") {
                    if items.isEmpty { fillFromSuggestion() } else { isConfirmingReplace = true }
                }
            } footer: {
                Text("Builds a day from \(baby.displayName)'s logged patterns and age. You can edit anything afterwards.")
            }
        }
        .themedBackground()
        .navigationTitle("My Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            ScheduleItemSheet(baby: baby, item: nil, onSave: save)
        }
        .sheet(item: $editing) { item in
            ScheduleItemSheet(baby: baby, item: item, onSave: save)
        }
        .confirmationDialog("Replace your schedule with a suggested one?", isPresented: $isConfirmingReplace, titleVisibility: .visible) {
            Button("Replace Schedule", role: .destructive) { fillFromSuggestion() }
        }
    }

    private func fillFromSuggestion() {
        withAnimation {
            items.forEach(context.delete)
            let predictor = SchedulePredictor(entries: Array(entries), schedule: [], age: BabyAge(birthdayInterval: baby.birthdayInterval))
            for suggestion in predictor.suggestedDay() {
                _ = ScheduleItem(context: context, baby: baby, kind: suggestion.kind, title: suggestion.title, minuteOfDay: suggestion.minute)
            }
            save()
        }
    }

    private func save() {
        try? context.save()
        ScheduleReminders.sync(for: baby)
    }
}

private struct ScheduleRow: View {
    @ObservedObject var item: ScheduleItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.time(on: .now), format: .dateTime.hour().minute())
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 72, alignment: .leading)
            Image(systemName: item.kind.symbol)
                .foregroundStyle(item.kind.textColor)
                .frame(width: 32, height: 32)
                .background(item.kind.softColor, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            Text(item.displayTitle)
                .font(.body.weight(.medium))
            Spacer()
            if item.remind {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Reminder on")
            }
        }
        .contentShape(.rect)
    }
}

/// Add or edit one schedule item.
private struct ScheduleItemSheet: View {
    @ObservedObject var baby: Baby
    let item: ScheduleItem?
    let onSave: () -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: EntryKind
    @State private var title: String
    @State private var time: Date
    @State private var remind: Bool

    init(baby: Baby, item: ScheduleItem?, onSave: @escaping () -> Void) {
        self.baby = baby
        self.item = item
        self.onSave = onSave
        _kind = State(initialValue: item?.kind ?? .feed)
        _title = State(initialValue: item?.title ?? "")
        _time = State(initialValue: item?.time(on: .now) ?? .now)
        _remind = State(initialValue: item?.remind ?? false)
    }

    private var suggestions: [String] {
        let isToddler = (BabyAge(birthdayInterval: baby.birthdayInterval)?.months ?? 0) >= 12
        switch kind {
        case .feed: return isToddler ? ["Breakfast", "Snack", "Lunch", "Dinner", "Milk"] : ["Feed", "Bottle", "Breastfeed"]
        case .sleep: return ["Nap", "Bedtime", "Wake up", "Quiet time"]
        default: return ["Diaper check", "Potty break"]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach([EntryKind.feed, .sleep, .diaper]) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("Name (optional)", text: $title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { withAnimation(.snappy) { title = suggestion } }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .tint(kind.textColor)
                            }
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Remind Me", isOn: $remind)
                } footer: {
                    Text("Repeats every day.")
                }
            }
            .navigationTitle(item == nil ? "New Schedule Item" : "Edit Schedule Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                }
            }
            .onChange(of: remind) { _, isOn in
                if isOn { Task { _ = await FeedReminderScheduler.requestAuthorization() } }
            }
        }
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if let item {
            item.kind = kind
            item.title = title
            item.minuteOfDay = Int16(minute)
            item.remind = remind
        } else {
            _ = ScheduleItem(context: context, baby: baby, kind: kind, title: title, minuteOfDay: minute, remind: remind)
        }
        onSave()
        dismiss()
    }
}

// MARK: - Reminders

/// Daily repeating notifications for schedule items with "Remind Me" on.
enum ScheduleReminders {
    private static func prefix(for baby: Baby) -> String {
        "schedule-\(baby.babyID?.uuidString ?? "baby")-"
    }

    static func sync(for baby: Baby) {
        let center = UNUserNotificationCenter.current()
        let prefix = prefix(for: baby)
        let items = ((baby.scheduleItems as? Set<ScheduleItem>) ?? []).filter { $0.remind && $0.isEnabled }
        let requests: [UNNotificationRequest] = items.map { item in
            let content = UNMutableNotificationContent()
            content.title = item.displayTitle
            content.body = "Time for \(baby.displayName)'s \(item.displayTitle.lowercased())."
            content.sound = .default
            var components = DateComponents()
            components.hour = Int(item.minuteOfDay) / 60
            components.minute = Int(item.minuteOfDay) % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            return UNNotificationRequest(identifier: prefix + (item.itemID?.uuidString ?? UUID().uuidString), content: content, trigger: trigger)
        }

        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for request in requests { center.add(request) }
        }
    }

    /// Cancels every schedule reminder for a baby that's being deleted.
    static func removeAll(for baby: Baby) {
        let center = UNUserNotificationCenter.current()
        let prefix = prefix(for: baby)
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }
}

// MARK: - Previews

/// A week of realistic logs for a 10-week-old, so predictions have something to learn from.
@MainActor
private let planPreviewStore: PersistenceController = {
    let persistence = PersistenceController(inMemory: true)
    let context = persistence.viewContext
    let baby = Baby(context: context, name: "Ava", birthday: .now.addingTimeInterval(-10 * 7 * 86_400), gender: .girl)
    let hour: TimeInterval = 3600
    let today = Calendar.current.startOfDay(for: .now)
    for dayOffset in 0..<7 {
        let day = today.addingTimeInterval(-Double(dayOffset) * 24 * hour)
        // Feeds roughly every 3 hours, from 6 AM.
        for feed in stride(from: 6.0, to: 23, by: 3.0) {
            let time = day.addingTimeInterval((feed + Double(dayOffset % 3) * 0.1) * hour)
            if time < .now.addingTimeInterval(-2 * hour) {
                _ = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: time, feedType: .formula, amountML: 120)
            }
        }
        // Naps after about 80 minutes awake, and a 7:30 PM bedtime.
        for nap in [8.3, 11.0, 14.0, 16.8] {
            let start = day.addingTimeInterval(nap * hour)
            if start < .now.addingTimeInterval(-3 * hour) {
                _ = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: start, endTime: start.addingTimeInterval(0.8 * hour))
            }
        }
        let bedtime = day.addingTimeInterval(-4.5 * hour)
        _ = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: bedtime, endTime: day.addingTimeInterval(6 * hour))
        for diaper in stride(from: 6.5, to: 20, by: 3.5) where day.addingTimeInterval(diaper * hour) < .now {
            _ = BabyEntry(context: context, baby: baby, kind: .diaper, timestamp: day.addingTimeInterval(diaper * hour), diaperType: .wet)
        }
    }
    persistence.save()
    return persistence
}()

#Preview("Day Plan") {
    NavigationStack {
        DayPlanView(baby: PreviewStore.firstBaby(in: planPreviewStore))
    }
    .environment(\.managedObjectContext, planPreviewStore.viewContext)
}

#Preview("Today with a week of logs") {
    TodayView(baby: PreviewStore.firstBaby(in: planPreviewStore))
        .environment(TabRouter())
        .environment(\.managedObjectContext, planPreviewStore.viewContext)
        .environment(\.appTheme, .girl)
}

#Preview("Schedule") {
    NavigationStack {
        ScheduleEditorView(baby: PreviewStore.firstBaby(in: planPreviewStore))
    }
    .environment(\.managedObjectContext, planPreviewStore.viewContext)
}
