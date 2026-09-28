import CoreData
import Foundation
import SwiftData

/// One-time move from the earlier SwiftData store (and app-wide baby settings) to Core Data.
@MainActor
enum LegacyImport {
    private static let doneKey = "didImportLegacyStore"

    /// The earlier SwiftData model, used only to read old data. Its entity is also named
    /// "BabyEntry", matching the store on disk.
    enum Legacy {
        @Model
        final class BabyEntry {
            var entryID: UUID = UUID()
            var kindRaw: String = "feed"
            var timestamp: Date = Date.now
            var endTime: Date?
            var isTimerRunning: Bool = false
            var feedTypeRaw: String?
            var amountML: Double?
            var diaperTypeRaw: String?
            var sleepLocationRaw: String?
            var symptomRaw: String?
            var severityRaw: String?
            var temperatureC: Double?
            var notes: String = ""

            init() {}
        }
    }

    static func runIfNeeded(_ persistence: PersistenceController) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let context = persistence.viewContext
        let legacyURL = legacyStoreURL()
        let hadProfile = defaults.bool(forKey: SettingsKey.hasCompletedOnboarding)
        guard legacyURL != nil || hadProfile else { return }

        // The single baby from before becomes the first baby profile.
        let existing = (try? context.fetch(Baby.fetchAll())) ?? []
        let baby = existing.first ?? {
            let birthday = defaults.double(forKey: SettingsKey.babyBirthday)
            return Baby(
                context: context,
                name: defaults.string(forKey: SettingsKey.babyName) ?? "",
                birthday: birthday == 0 ? nil : Date(timeIntervalSince1970: birthday),
                gender: defaults.string(forKey: SettingsKey.babyGender).flatMap(BabyGender.init(rawValue:)) ?? .both
            )
        }()
        SelectedBaby.id = baby.babyID

        if let legacyURL, let old = try? ModelContainer(
            for: Legacy.BabyEntry.self,
            configurations: ModelConfiguration(url: legacyURL, cloudKitDatabase: .none)
        ) {
            let oldEntries = (try? old.mainContext.fetch(FetchDescriptor<Legacy.BabyEntry>())) ?? []
            for old in oldEntries {
                let entry = BabyEntry(context: context, baby: baby, kind: EntryKind(rawValue: old.kindRaw) ?? .feed)
                entry.entryID = old.entryID
                entry.timestamp = old.timestamp
                entry.endTime = old.endTime
                entry.isTimerRunning = old.isTimerRunning
                entry.feedTypeRaw = old.feedTypeRaw
                entry.amountML = old.amountML
                entry.diaperTypeRaw = old.diaperTypeRaw
                entry.sleepLocationRaw = old.sleepLocationRaw
                entry.symptomRaw = old.symptomRaw
                entry.severityRaw = old.severityRaw
                entry.temperatureC = old.temperatureC
                entry.notes = old.notes
            }
        }
        persistence.save()

        // Keep the old files, renamed, in case they're ever needed again.
        if let legacyURL {
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(filePath: legacyURL.path() + suffix)
                try? FileManager.default.moveItem(at: url, to: URL(filePath: url.path() + ".imported"))
            }
        }
    }

    /// Where earlier versions kept their data: the App Group, or before that the app's own folder.
    private static func legacyStoreURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupID) {
            candidates.append(group.appending(path: "MyBaby.store"))
        }
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appending(path: "default.store"))
        }
        return candidates.first { fileManager.fileExists(atPath: $0.path()) }
    }
}
