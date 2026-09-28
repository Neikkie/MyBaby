import ActivityKit
import AppIntents
import Foundation
import CoreData
import WidgetKit

/// Live Activity shown on the Lock Screen and in the Dynamic Island
/// while a sleep or breastfeeding timer is running.
/// Marked `nonisolated` because the app target defaults to main-actor isolation,
/// but ActivityKit uses this plain data type from background contexts.
nonisolated struct BabyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        /// "Left" / "Right" for breastfeeding; nil for sleep.
        var side: String?
    }

    /// Matches `BabyEntry.entryID` of the entry being timed.
    var entryID: UUID
    var kindRaw: String
    var babyName: String

    var kind: EntryKind { EntryKind(rawValue: kindRaw) ?? .sleep }
}

/// Starts, updates and ends Live Activities to mirror running timers.
@MainActor
enum BabyActivityController {
    static func start(for entry: BabyEntry) {
        guard entry.isInProgress, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(entryID: entry.entryID)

        let attributes = BabyActivityAttributes(
            entryID: entry.entryID,
            kindRaw: entry.kindRaw,
            babyName: entry.baby?.displayName ?? ""
        )
        let state = BabyActivityAttributes.ContentState(startDate: entry.timestamp, side: entry.feedType?.sideTitle)
        _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
    }

    static func end(entryID: UUID) {
        for activity in Activity<BabyActivityAttributes>.activities where activity.attributes.entryID == entryID {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Makes the set of Live Activities match the entries that are currently in progress,
    /// e.g. after a timer was stopped on another device and synced here.
    static func sync(with inProgress: [BabyEntry]) {
        let runningIDs = Set(inProgress.map(\.entryID))
        for activity in Activity<BabyActivityAttributes>.activities where !runningIDs.contains(activity.attributes.entryID) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let activeIDs = Set(Activity<BabyActivityAttributes>.activities.map(\.attributes.entryID))
        for entry in inProgress where !activeIDs.contains(entry.entryID) {
            start(for: entry)
        }
    }
}

/// "Wake Up" / "Stop" button on the Live Activity. Runs in the app's process.
struct FinishTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"
    static let description = IntentDescription("Ends the running sleep or feed timer.")

    @Parameter(title: "Entry ID")
    var entryID: String

    init() {}

    init(entryID: UUID) {
        self.entryID = entryID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: entryID) else { return .result() }
        let persistence = PersistenceController.shared
        let request = NSFetchRequest<BabyEntry>(entityName: "BabyEntry")
        request.predicate = NSPredicate(format: "entryID == %@", id as CVarArg)
        request.fetchLimit = 1
        if let entry = try persistence.viewContext.fetch(request).first {
            entry.finish()
            persistence.save()
        }
        BabyActivityController.end(entryID: id)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// One-tap diaper logging from the Home Screen widget.
struct LogDiaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Diaper"
    static let description = IntentDescription("Logs a diaper change right now.")

    @Parameter(title: "Type")
    var type: DiaperTypeEntity

    init() {}

    init(type: DiaperType) {
        self.type = DiaperTypeEntity(type)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let persistence = PersistenceController.shared
        let context = persistence.viewContext
        _ = BabyEntry(context: context, baby: SelectedBaby.resolve(in: context), kind: .diaper, diaperType: type.diaperType)
        persistence.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// App Intents wrapper for `DiaperType`, so it can be an intent parameter.
enum DiaperTypeEntity: String, AppEnum {
    case wet
    case dirty
    case both

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diaper Type"
    static let caseDisplayRepresentations: [DiaperTypeEntity: DisplayRepresentation] = [
        .wet: "Wet",
        .dirty: "Poop",
        .both: "Wet + Poop",
    ]

    init(_ type: DiaperType) {
        self = DiaperTypeEntity(rawValue: type.rawValue) ?? .wet
    }

    var diaperType: DiaperType {
        DiaperType(rawValue: rawValue) ?? .wet
    }
}
