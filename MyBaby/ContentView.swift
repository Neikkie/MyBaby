import CoreData
import SwiftUI
import WidgetKit

struct ContentView: View {
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(SelectedBaby.storageKey, store: SelectedBaby.defaults) private var selectedBabyID = ""
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @FetchRequest(fetchRequest: BabyEntry.fetch(for: nil, limit: 1)) private var anyEntry: FetchedResults<BabyEntry>
    @State private var router = TabRouter()

    /// The baby being shown; falls back to the first one.
    private var currentBaby: Baby? {
        babies.first { $0.babyID?.uuidString == selectedBabyID } ?? babies.first
    }

    /// Health and History stay hidden until there's something in them, keeping a fresh start simple.
    private var hasData: Bool { !anyEntry.isEmpty }

    var body: some View {
        let theme = (currentBaby?.gender ?? .both).theme
        Group {
            if let baby = currentBaby {
                tabs(for: baby)
                    // Switching babies rebuilds each screen with that baby's entries.
                    .id(baby.objectID)
            } else {
                // Before onboarding finishes there's no baby yet.
                Color.clear.background { ThemedBackground() }
            }
        }
        .environment(router)
        .onChange(of: hasData) { _, hasData in
            // If everything is deleted while on a hidden tab, go back to Today.
            if !hasData, router.selected == .health || router.selected == .history {
                router.selected = .today
            }
        }
        .background { DataChangeObserver(baby: currentBaby) }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding || babies.isEmpty },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        // Each baby's theme colors the whole app.
        .environment(\.appTheme, theme)
        .tint(theme.accent)
    }

    private func tabs(for baby: Baby) -> some View {
        TabView(selection: $router.selected) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView(baby: baby)
            }
            if hasData {
                Tab("Health", systemImage: EntryKind.health.symbol, value: AppTab.health) {
                    HealthView(baby: baby)
                }
                Tab("History", systemImage: "list.bullet.rectangle.fill", value: AppTab.history) {
                    HistoryView(baby: baby)
                }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView(baby: baby)
            }
        }
        // Shows a tab bar on iPhone and a sidebar option on iPad.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Watches the data (including changes synced from other devices) and keeps
/// widgets, Live Activities and feed reminders up to date.
private struct DataChangeObserver: View {
    let baby: Baby?

    @FetchRequest(fetchRequest: BabyEntry.fetch(for: nil, limit: 200)) private var entries: FetchedResults<BabyEntry>
    @Environment(\.scenePhase) private var scenePhase

    /// Changes whenever an entry that matters to widgets or timers changes.
    private var signature: Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        hasher.combine(baby?.babyID)
        for entry in entries.prefix(50) {
            hasher.combine(entry.entryID)
            hasher.combine(entry.timestamp)
            hasher.combine(entry.endTime)
            hasher.combine(entry.isTimerRunning)
            hasher.combine(entry.kindRaw)
        }
        return hasher.finalize()
    }

    var body: some View {
        Color.clear
            .task(id: signature) {
                // Brief debounce so rapid edits cause one update.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                WidgetCenter.shared.reloadAllTimelines()
                BabyActivityController.sync(with: entries.filter(\.isInProgress))
                let lastFeed = entries.first { $0.kind == .feed && $0.baby == baby }?.timestamp
                await FeedReminderScheduler.reschedule(lastFeed: lastFeed, babyName: baby?.name ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    BabyActivityController.sync(with: entries.filter(\.isInProgress))
                }
            }
    }
}

/// Feeds, sleep and diaper counts for today.
struct TodayTotalsView: View {
    let entries: [BabyEntry]
    @AppStorage(SettingsKey.volumeUnit) private var volumeUnit: VolumeUnitPreference = .system

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let feeds = entries.filter { $0.kind == .feed }
        let bottleML = feeds.compactMap(\.amountML).reduce(0, +)
        let sleepTime = entries
            .filter { $0.kind == .sleep }
            .compactMap(\.duration)
            .reduce(0, +)
        let diapers = entries.filter { $0.kind == .diaper }
        let poops = diapers.filter { $0.diaperType == .dirty || $0.diaperType == .both }.count
        let wets = diapers.filter { $0.diaperType == .wet || $0.diaperType == .both }.count

        let totals = Group {
            TotalView(
                title: "Feeds",
                value: "\(feeds.count)",
                caption: bottleML > 0 ? "\(volumeUnit.format(milliliters: bottleML)) by bottle" : nil,
                color: EntryKind.feed.textColor
            )
            TotalView(
                title: "Sleep",
                value: sleepTime > 0 ? BabyEntry.format(sleepTime) : "0m",
                caption: nil,
                color: EntryKind.sleep.textColor
            )
            TotalView(
                title: "Diapers",
                value: "\(diapers.count)",
                caption: "\(wets) wet · \(poops) poop",
                color: EntryKind.diaper.textColor
            )
        }

        // Stack vertically at accessibility text sizes.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { totals }
            } else {
                HStack(alignment: .top) { totals }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TotalView: View {
    let title: String
    let value: String
    let caption: String?
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Health

/// Symptom log (fever, vomit, etc.) with the latest temperature reading.
struct HealthView: View {
    let baby: Baby
    @FetchRequest private var entries: FetchedResults<BabyEntry>

    init(baby: Baby) {
        self.baby = baby
        _entries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby, kinds: [.health]))
    }

    @AppStorage(SettingsKey.temperatureUnit) private var temperatureUnit: TemperatureUnitPreference = .system

    @State private var isAdding = false
    @State private var editingEntry: BabyEntry?

    private var latestTemperature: BabyEntry? {
        entries.first { $0.temperatureC != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if let latestTemperature, let formatted = latestTemperature.formattedTemperature(in: temperatureUnit) {
                    Section("Latest Temperature") {
                        LatestTemperatureRow(entry: latestTemperature, formattedTemperature: formatted)
                    }
                }

                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            SymptomRow(entry: entry)
                                .entryActions(entry: entry, onEdit: { editingEntry = entry })
                        }
                    } header: {
                        Text("Symptoms")
                    } footer: {
                        Text("My Baby doesn't provide medical advice. Contact your pediatrician if you're worried, or emergency services in an emergency.")
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Symptoms Logged", systemImage: EntryKind.health.symbol)
                    } description: {
                        Text("Keep track of fevers, vomiting and other symptoms to share with your doctor.")
                    } actions: {
                        Button("Log Symptom") { isAdding = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .themedBackground()
            .funNavigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Log Symptom", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                EntryFormView(kind: .health, baby: baby)
            }
            .sheet(item: $editingEntry) { entry in
                EntryFormView(entry: entry)
            }
        }
    }
}

struct LatestTemperatureRow: View {
    @ObservedObject var entry: BabyEntry
    let formattedTemperature: String

    private var isFever: Bool { (entry.temperatureC ?? 0) >= 38 }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(formattedTemperature, systemImage: "thermometer.medium")
                .font(.title2.bold())
                .foregroundStyle(isFever ? EntryKind.health.textColor : .primary)

            // Text label as well as color, so the state isn't conveyed by color alone.
            if isFever {
                Text("Fever")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(EntryKind.health.color, in: .capsule)
            }

            Spacer()

            RelativeTimeText(date: entry.timestamp)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SymptomRow: View {
    @ObservedObject var entry: BabyEntry
    @AppStorage(SettingsKey.temperatureUnit) private var temperatureUnit: TemperatureUnitPreference = .system

    var body: some View {
        let symptom = entry.symptom ?? .other
        let details = [entry.formattedTemperature(in: temperatureUnit), entry.severity?.title, entry.notes.isEmpty ? nil : entry.notes]
            .compactMap { $0 }
            .joined(separator: " · ")

        EntryRowLayout(
            symbol: symptom.symbol,
            color: EntryKind.health.textColor,
            softColor: EntryKind.health.softColor,
            title: symptom.title,
            detail: details,
            time: entry.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        )
    }
}

// MARK: - Components

struct EntryRow: View {
    @ObservedObject var entry: BabyEntry
    @AppStorage(SettingsKey.temperatureUnit) private var temperatureUnit: TemperatureUnitPreference = .system
    @AppStorage(SettingsKey.volumeUnit) private var volumeUnit: VolumeUnitPreference = .system

    var body: some View {
        EntryRowLayout(
            symbol: entry.kind.symbol,
            color: entry.kind.textColor,
            softColor: entry.kind.softColor,
            title: entry.kind.title,
            detail: entry.detail(temperatureUnit: temperatureUnit, volumeUnit: volumeUnit),
            time: entry.timestamp.formatted(date: .omitted, time: .shortened)
        )
    }
}

/// Shared row layout: pastel icon tile, title and detail, and a trailing time.
/// Adapts to a stacked layout at accessibility text sizes.
struct EntryRowLayout: View {
    let symbol: String
    let color: Color
    let softColor: Color
    let title: String
    let detail: String
    let time: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: iconSize, height: iconSize)
                .background(softColor, in: .rect(cornerRadius: iconSize * 0.32, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    Text(time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
                Text(time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Adds tap-to-edit, swipe actions and a context menu to an entry row.
private struct EntryActionsModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var context
    let entry: BabyEntry
    let onEdit: () -> Void

    func body(content: Content) -> some View {
        Button(action: onEdit) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityHint("Double-tap to edit")
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { deleteEntry() }
        }
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil", action: onEdit)
                .tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive) { deleteEntry() }
        }
    }

    private func deleteEntry() {
        withAnimation {
            context.delete(entry)
            try? context.save()
        }
    }
}

extension View {
    func entryActions(entry: BabyEntry, onEdit: @escaping () -> Void) -> some View {
        modifier(EntryActionsModifier(entry: entry, onEdit: onEdit))
    }
}

/// Concise "30 min. ago" text that refreshes every minute.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
        }
    }
}

/// Preview data stacks, created once and kept alive for the whole preview session.
@MainActor
enum PreviewStore {
    static let empty: PersistenceController = {
        UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        let persistence = PersistenceController(inMemory: true)
        _ = Baby(context: persistence.viewContext, name: "", birthday: .now.addingTimeInterval(-10 * 7 * 86_400), gender: .both)
        persistence.save()
        return persistence
    }()

    static let sampleDay: PersistenceController = {
        UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        let baby = Baby(context: context, name: "Ava", birthday: .now.addingTimeInterval(-10 * 7 * 86_400), gender: .girl)
        _ = Baby(context: context, name: "Leo", birthday: .now.addingTimeInterval(-10 * 7 * 86_400), gender: .boy)
        let hour: TimeInterval = 3600
        _ = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: .now.addingTimeInterval(-0.5 * hour), feedType: .formula, amountML: 120)
        _ = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: .now.addingTimeInterval(-420), isTimerRunning: true, feedType: .breastLeft)
        _ = BabyEntry(context: context, baby: baby, kind: .diaper, timestamp: .now.addingTimeInterval(-1 * hour), diaperType: .both)
        _ = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: .now.addingTimeInterval(-3 * hour), endTime: .now.addingTimeInterval(-1.5 * hour))
        _ = BabyEntry(context: context, baby: baby, kind: .health, timestamp: .now.addingTimeInterval(-2 * hour), symptom: .fever, severity: .mild, temperatureC: 38.2)
        persistence.save()
        SelectedBaby.id = baby.babyID
        return persistence
    }()

    /// The first baby in a preview store.
    static func firstBaby(in persistence: PersistenceController) -> Baby {
        (try? persistence.viewContext.fetch(Baby.fetchAll()))!.first!
    }
}

#Preview("Empty") {
    ContentView()
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}

#Preview("Sample Day") {
    ContentView()
        .environment(\.managedObjectContext, PreviewStore.sampleDay.viewContext)
}
