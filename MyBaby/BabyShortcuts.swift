import AppIntents
import CoreData
import WidgetKit

// Siri and Shortcuts: hands-free logging for when both hands are full of baby.

// MARK: - Baby parameter

/// A baby that Siri and Shortcuts can pick, e.g. "Log a diaper for Mia".
nonisolated struct BabyEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Baby"
    static let defaultQuery = BabyQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct BabyQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BabyEntity] {
        allBabies().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [BabyEntity] {
        allBabies()
    }

    /// Defaults to the baby currently shown in the app.
    @MainActor
    func defaultResult() async -> BabyEntity? {
        SelectedBaby.resolve(in: PersistenceController.shared.viewContext).flatMap(BabyEntity.init)
    }

    @MainActor
    private func allBabies() -> [BabyEntity] {
        let babies = (try? PersistenceController.shared.viewContext.fetch(Baby.fetchAll())) ?? []
        return babies.compactMap(BabyEntity.init)
    }
}

extension BabyEntity {
    init?(_ baby: Baby) {
        guard let id = baby.babyID else { return nil }
        self.init(id: id, name: baby.displayName)
    }
}

/// Shared helpers for the intents below.
@MainActor
private enum IntentStore {
    static var context: NSManagedObjectContext { PersistenceController.shared.viewContext }

    /// The chosen baby, or the one shown in the app.
    static func baby(_ entity: BabyEntity?) throws -> Baby {
        let babies = (try? context.fetch(Baby.fetchAll())) ?? []
        if let entity, let match = babies.first(where: { $0.babyID == entity.id }) { return match }
        guard let baby = SelectedBaby.resolve(in: context) else { throw IntentError.noBaby }
        return baby
    }

    static func ongoing(_ kind: EntryKind, for baby: Baby) -> BabyEntry? {
        let entries = (try? context.fetch(BabyEntry.fetch(for: baby, kinds: [kind], limit: 20))) ?? []
        return entries.first(where: \.isInProgress)
    }

    static func latest(_ kind: EntryKind, for baby: Baby) -> BabyEntry? {
        (try? context.fetch(BabyEntry.fetch(for: baby, kinds: [kind], limit: 1)))?.first
    }

    static func save() {
        PersistenceController.shared.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var volumeUnit: VolumeUnitPreference {
        VolumeUnitPreference(rawValue: UserDefaults.standard.string(forKey: SettingsKey.volumeUnit) ?? "") ?? .system
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noBaby

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noBaby: "Open myBaby and add your baby first."
        }
    }
}

// MARK: - Feeds

enum BottleContent: String, AppEnum {
    case formula
    case breastMilk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bottle"
    static let caseDisplayRepresentations: [BottleContent: DisplayRepresentation] = [
        .formula: "Formula",
        .breastMilk: "Breast Milk",
    ]

    var feedType: FeedType { self == .formula ? .formula : .bottle }
}

struct LogBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Bottle"
    static let description = IntentDescription("Logs a bottle of formula or breast milk.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @Parameter(title: "Bottle", default: .formula)
    var content: BottleContent

    @Parameter(title: "Amount", defaultUnit: .fluidOunces, defaultUnitAdjustForLocale: true)
    var amount: Measurement<UnitVolume>?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) of \(\.$content) for \(\.$baby)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        let milliliters = amount?.converted(to: .milliliters).value
        _ = BabyEntry(context: IntentStore.context, baby: baby, kind: .feed, feedType: content.feedType, amountML: milliliters)
        IntentStore.save()
        if let milliliters {
            let amountText = IntentStore.volumeUnit.format(milliliters: milliliters)
            return .result(dialog: "Logged \(amountText) for \(baby.displayName).")
        }
        return .result(dialog: "Logged a bottle for \(baby.displayName).")
    }
}

enum BreastSide: String, AppEnum {
    case left
    case right

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Side"
    static let caseDisplayRepresentations: [BreastSide: DisplayRepresentation] = [
        .left: "Left",
        .right: "Right",
    ]

    var feedType: FeedType { self == .left ? .breastLeft : .breastRight }
}

struct StartBreastfeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Breastfeeding"
    static let description = IntentDescription("Starts a breastfeeding timer. Leave the side empty to use the side after last time.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @Parameter(title: "Side")
    var side: BreastSide?

    static var parameterSummary: some ParameterSummary {
        Summary("Start breastfeeding \(\.$baby) on \(\.$side)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        if IntentStore.ongoing(.feed, for: baby) != nil {
            return .result(dialog: "A feed timer is already running for \(baby.displayName).")
        }
        // Same "next side" logic as the app: the opposite of the last breast feed.
        let lastSide = ((try? IntentStore.context.fetch(BabyEntry.fetch(for: baby, kinds: [.feed], limit: 30))) ?? [])
            .first { $0.feedType?.isBreast == true }?.feedType
        let feedType = side?.feedType ?? lastSide?.otherSide ?? .breastLeft
        let entry = BabyEntry(context: IntentStore.context, baby: baby, kind: .feed, isTimerRunning: true, feedType: feedType)
        IntentStore.save()
        BabyActivityController.start(for: entry)
        return .result(dialog: "Started the \(feedType.sideTitle ?? "") side for \(baby.displayName).")
    }
}

struct StopFeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Breastfeeding"
    static let description = IntentDescription("Stops the running breastfeeding timer.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        guard let entry = IntentStore.ongoing(.feed, for: baby) else {
            return .result(dialog: "There's no feed timer running for \(baby.displayName).")
        }
        entry.finish()
        IntentStore.save()
        BabyActivityController.end(entryID: entry.entryID)
        let length = BabyEntry.format(entry.duration ?? 0)
        return .result(dialog: "Saved a \(length) feed for \(baby.displayName).")
    }
}

// MARK: - Sleep

struct StartSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Sleep"
    static let description = IntentDescription("Starts a sleep timer.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        if IntentStore.ongoing(.sleep, for: baby) != nil {
            return .result(dialog: "\(baby.displayName) is already asleep.")
        }
        let entry = BabyEntry(context: IntentStore.context, baby: baby, kind: .sleep)
        IntentStore.save()
        BabyActivityController.start(for: entry)
        return .result(dialog: "Sweet dreams, \(baby.displayName). Sleep timer started.")
    }
}

struct EndSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "End Sleep"
    static let description = IntentDescription("Ends the running sleep timer when the baby wakes up.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        guard let entry = IntentStore.ongoing(.sleep, for: baby) else {
            return .result(dialog: "\(baby.displayName) isn't asleep right now.")
        }
        entry.finish()
        IntentStore.save()
        BabyActivityController.end(entryID: entry.entryID)
        let length = BabyEntry.format(entry.duration ?? 0)
        return .result(dialog: "\(baby.displayName) slept for \(length).")
    }
}

// MARK: - Diapers

struct LogDiaperChangeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Diaper Change"
    static let description = IntentDescription("Logs a wet, poopy or mixed diaper.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @Parameter(title: "Type", default: .wet)
    var type: DiaperTypeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$type) diaper for \(\.$baby)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        _ = BabyEntry(context: IntentStore.context, baby: baby, kind: .diaper, diaperType: type.diaperType)
        IntentStore.save()
        return .result(dialog: "Logged a \(type.diaperType.title.lowercased()) diaper for \(baby.displayName).")
    }
}

// MARK: - Status

/// "When did Mia last eat?" answers with the last feed, sleep and diaper.
struct BabyStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check on Baby"
    static let description = IntentDescription("Tells you when your baby last ate, slept and had a diaper change.")

    @Parameter(title: "Baby")
    var baby: BabyEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let baby = try IntentStore.baby(baby)
        let name = baby.displayName
        var sentences: [String] = []

        if let feed = IntentStore.latest(.feed, for: baby) {
            let when = feed.timestamp.formatted(.relative(presentation: .named))
            sentences.append(String(localized: "\(name) last ate \(when)."))
        } else {
            sentences.append(String(localized: "No feeds logged for \(name) yet."))
        }

        if let sleep = IntentStore.ongoing(.sleep, for: baby) {
            sentences.append(String(localized: "Asleep for \(BabyEntry.format(sleep.duration ?? 0))."))
        } else if let sleep = IntentStore.latest(.sleep, for: baby), let end = sleep.endTime {
            sentences.append(String(localized: "Woke up \(end.formatted(.relative(presentation: .named)))."))
        }

        if let diaper = IntentStore.latest(.diaper, for: baby) {
            sentences.append(String(localized: "Last diaper \(diaper.timestamp.formatted(.relative(presentation: .named)))."))
        }

        return .result(dialog: IntentDialog(stringLiteral: sentences.joined(separator: " ")))
    }
}

// MARK: - App Shortcuts

/// Phrases that work with Siri straight after install, no setup needed.
struct BabyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BabyStatusIntent(),
            phrases: [
                "Check on my baby in \(.applicationName)",
                "When did my baby last eat in \(.applicationName)",
                "When did \(\.$baby) last eat in \(.applicationName)",
                "How is \(\.$baby) doing in \(.applicationName)",
            ],
            shortTitle: "Check on Baby",
            systemImageName: "heart.text.square.fill"
        )
        AppShortcut(
            intent: LogBottleIntent(),
            phrases: [
                "Log a bottle in \(.applicationName)",
                "Log a \(\.$content) bottle in \(.applicationName)",
                "Log a bottle for \(\.$baby) in \(.applicationName)",
            ],
            shortTitle: "Log a Bottle",
            systemImageName: "waterbottle.fill"
        )
        AppShortcut(
            intent: StartBreastfeedIntent(),
            phrases: [
                "Start breastfeeding in \(.applicationName)",
                "Start a feed in \(.applicationName)",
                "Start breastfeeding \(\.$baby) in \(.applicationName)",
            ],
            shortTitle: "Start Breastfeeding",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StopFeedIntent(),
            phrases: [
                "Stop breastfeeding in \(.applicationName)",
                "Stop the feed in \(.applicationName)",
            ],
            shortTitle: "Stop Breastfeeding",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: StartSleepIntent(),
            phrases: [
                "Start sleep in \(.applicationName)",
                "Baby is asleep in \(.applicationName)",
                "\(\.$baby) is asleep in \(.applicationName)",
            ],
            shortTitle: "Start Sleep",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: EndSleepIntent(),
            phrases: [
                "End sleep in \(.applicationName)",
                "Baby is awake in \(.applicationName)",
                "\(\.$baby) woke up in \(.applicationName)",
            ],
            shortTitle: "End Sleep",
            systemImageName: "sun.horizon.fill"
        )
        AppShortcut(
            intent: LogDiaperChangeIntent(),
            phrases: [
                "Log a diaper in \(.applicationName)",
                "Log a \(\.$type) diaper in \(.applicationName)",
                "Log a diaper for \(\.$baby) in \(.applicationName)",
            ],
            shortTitle: "Log a Diaper",
            systemImageName: "heart.circle.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .pink
}
