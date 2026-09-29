import CoreData
import Foundation
import SwiftUI

/// The kinds of events the app tracks.
nonisolated enum EntryKind: String, CaseIterable, Identifiable, Codable {
    case feed
    case sleep
    case diaper
    case health
    /// A parent's pumping session (not a feed for the baby).
    case pump

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: String(localized: "Feed")
        case .sleep: String(localized: "Sleep")
        case .diaper: String(localized: "Diaper")
        case .health: String(localized: "Health")
        case .pump: String(localized: "Pumping")
        }
    }

    var symbol: String {
        switch self {
        case .feed: "drop.fill"
        case .sleep: "moon.zzz.fill"
        case .diaper: "sparkles"
        case .health: "cross.case.fill"
        case .pump: "drop.circle.fill"
        }
    }

    // Colors follow the app icon's tiles: pink feeding, periwinkle sleep, green diapers.

    /// Fill color for buttons and badges that show white content.
    /// Every shade has at least 4.5:1 contrast with white in both light and dark mode.
    var color: Color {
        switch self {
        case .feed: Color(red: 0.82, green: 0.20, blue: 0.49)    // #D2327D
        case .sleep: Color(red: 0.33, green: 0.32, blue: 0.82)   // #5452D1
        case .diaper: Color(red: 0.20, green: 0.53, blue: 0.22)  // #328737
        case .health: Color(red: 0.78, green: 0.16, blue: 0.16)  // #C62828
        case .pump: Color(red: 0.48, green: 0.25, blue: 0.77)    // #7B3FC4 (6.3:1 with white)
        }
    }

    /// Color for text, symbols and chart marks drawn directly on the system background.
    /// Uses the strong shade in light mode and a lighter one in dark mode so both meet 4.5:1.
    /// Feed, sleep and diaper were validated together as a chart palette for colorblind readers;
    /// charts also label each series, so color is never the only cue.
    var textColor: Color {
        switch self {
        case .feed: Color(light: 0xD2327D, dark: 0xE15FA0)
        case .sleep: Color(light: 0x5452D1, dark: 0x8583F0)
        case .diaper: Color(light: 0x328737, dark: 0x41AF50)
        case .health: Color(light: 0xC62828, dark: 0xFF6961)
        case .pump: Color(light: 0x7B3FC4, dark: 0xC3A3FF)
        }
    }

    /// Pastel tile background, like the icon's rounded tiles.
    /// `textColor` symbols on it are at least 3.9:1, and primary text is well above 4.5:1.
    var softColor: Color {
        switch self {
        case .feed: Color(light: 0xFFE3F0, dark: 0x4A1F37)
        case .sleep: Color(light: 0xE6E6FF, dark: 0x28275A)
        case .diaper: Color(light: 0xDFF5DD, dark: 0x1B3A21)
        case .health: Color(light: 0xFFE4E4, dark: 0x3D1C1C)
        case .pump: Color(light: 0xEFE6FF, dark: 0x2E2148)
        }
    }
}

extension Color {
    /// A color that switches between two hex values for light and dark appearance.
    nonisolated init(light: UInt32, dark: UInt32) {
        func uiColor(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light)
        })
    }
}

nonisolated enum Symptom: String, CaseIterable, Identifiable, Codable {
    case fever
    case vomit
    case diarrhea
    case cough
    case congestion
    case rash
    case fussiness
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fever: "Fever"
        case .vomit: "Vomit"
        case .diarrhea: "Diarrhea"
        case .cough: "Cough"
        case .congestion: "Congestion"
        case .rash: "Rash"
        case .fussiness: "Fussiness"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .fever: "thermometer.medium"
        case .vomit: "exclamationmark.bubble.fill"
        case .diarrhea: "toilet.fill"
        case .cough: "lungs.fill"
        case .congestion: "nose.fill"
        case .rash: "allergens.fill"
        case .fussiness: "face.dashed.fill"
        case .other: "cross.case.fill"
        }
    }
}

nonisolated enum Severity: String, CaseIterable, Identifiable, Codable {
    case mild
    case moderate
    case severe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }
}

nonisolated enum FeedType: String, CaseIterable, Identifiable, Codable {
    case breastLeft
    case breastRight
    case formula
    /// Expressed breast milk from a bottle. The raw value stays "bottle" for existing data.
    case bottle
    /// Solid food for babies starting to eat.
    case solids
    case breakfast
    case lunch
    case dinner
    case snack
    /// Milk from a cup, for toddlers.
    case cupMilk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breastLeft: "Breast (Left)"
        case .breastRight: "Breast (Right)"
        case .formula: "Formula"
        case .bottle: "Breast Milk Bottle"
        case .solids: "Solids"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        case .cupMilk: "Milk (Cup)"
        }
    }

    var isBreast: Bool { self == .breastLeft || self == .breastRight }

    /// Bottle and cup feeds record an amount.
    var hasAmount: Bool { self == .formula || self == .bottle || self == .cupMilk }

    /// Meals for toddlers and older children.
    static let meals: [FeedType] = [.breakfast, .lunch, .dinner, .snack]

    var isMeal: Bool { Self.meals.contains(self) }

    var symbol: String {
        switch self {
        case .breastLeft, .breastRight: "timer"
        case .formula: "drop.halffull"
        case .bottle: "drop.fill"
        case .solids: "carrot.fill"
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        case .cupMilk: "mug.fill"
        }
    }

    /// Feed types that make sense at a given age, in months (nil when the birthday isn't set).
    /// Breastfeeding is offered to 2 years and bottles to 18 months. Solids start around 6 months;
    /// from 12 months, toddlers get breakfast, lunch, dinner, snacks and milk from a cup.
    static func available(forMonths months: Int?) -> [FeedType] {
        guard let months else { return [.breastLeft, .breastRight, .formula, .bottle, .solids] }
        var types: [FeedType] = []
        if months < 24 { types += [.breastLeft, .breastRight] }
        if months < 18 { types += [.formula, .bottle] }
        if months >= 6 && months < 12 { types.append(.solids) }
        if months >= 12 { types += meals + [.cupMilk] }
        return types
    }

    /// "Left" / "Right" for breast feeds.
    var sideTitle: String? {
        switch self {
        case .breastLeft: "Left"
        case .breastRight: "Right"
        default: nil
        }
    }

    /// The other breast, used when switching sides or suggesting the next side.
    var otherSide: FeedType? {
        switch self {
        case .breastLeft: .breastRight
        case .breastRight: .breastLeft
        default: nil
        }
    }
}

nonisolated enum DiaperType: String, CaseIterable, Identifiable, Codable {
    case wet
    case dirty
    case both
    /// A successful trip to the potty, for toddlers who are potty training.
    case potty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wet: "Wet"
        case .dirty: "Poop"
        case .both: "Wet + Poop"
        case .potty: "Used Potty"
        }
    }

    /// Diaper types shown before potty training begins.
    static let diaperCases: [DiaperType] = [.wet, .dirty, .both]
}

/// Where the baby slept.
nonisolated enum SleepLocation: String, CaseIterable, Identifiable, Codable {
    case bassinet
    case crib
    case coSleeping
    case toddlerBed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bassinet: "Bassinet"
        case .crib: "Crib"
        case .coSleeping: "Co-sleeping"
        case .toddlerBed: "Toddler Bed"
        }
    }

    var symbol: String {
        switch self {
        case .bassinet: "basket.fill"
        case .crib: "square.grid.3x1.below.line.grid.1x2.fill"
        case .coSleeping: "bed.double.fill"
        case .toddlerBed: "bed.double.circle.fill"
        }
    }

    /// Bassinets are outgrown by about 5–6 months; toddler beds usually start after 18 months.
    static func available(forMonths months: Int?) -> [SleepLocation] {
        guard let months else { return [.bassinet, .crib, .coSleeping] }
        var locations: [SleepLocation] = []
        if months < 6 { locations.append(.bassinet) }
        locations += [.crib, .coSleeping]
        if months >= 18 { locations.append(.toddlerBed) }
        return locations
    }
}

// MARK: - Core Data model

/// The data model, defined in code so the app and the widget extension share one definition.
///
/// CloudKit requires every attribute to be optional or have a default, relationships to be
/// optional with inverses, and no unique constraints. Attribute names match the earlier
/// SwiftData model so existing data and iCloud records carry over.
nonisolated enum BabyDataModel {
    /// One model instance per process; Core Data requires entity descriptions to be unique.
    static let model: NSManagedObjectModel = {
        func attribute(_ name: String, _ type: NSAttributeDescription.AttributeType, default value: Any? = nil) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.type = type
            attribute.isOptional = true
            attribute.defaultValue = value
            return attribute
        }

        let baby = NSEntityDescription()
        baby.name = "Baby"
        baby.managedObjectClassName = NSStringFromClass(Baby.self)

        let entry = NSEntityDescription()
        entry.name = "BabyEntry"
        entry.managedObjectClassName = NSStringFromClass(BabyEntry.self)

        let entries = NSRelationshipDescription()
        entries.name = "entries"
        entries.destinationEntity = entry
        entries.minCount = 0
        entries.maxCount = 0 // to-many
        entries.deleteRule = .cascadeDeleteRule
        entries.isOptional = true

        let owner = NSRelationshipDescription()
        owner.name = "baby"
        owner.destinationEntity = baby
        owner.minCount = 0
        owner.maxCount = 1
        owner.deleteRule = .nullifyDeleteRule
        owner.isOptional = true

        entries.inverseRelationship = owner
        owner.inverseRelationship = entries

        // A parent's own daily plan (e.g. "Feed at 7:00"), shared with the baby.
        let schedule = NSEntityDescription()
        schedule.name = "ScheduleItem"
        schedule.managedObjectClassName = NSStringFromClass(ScheduleItem.self)

        let scheduleItems = NSRelationshipDescription()
        scheduleItems.name = "scheduleItems"
        scheduleItems.destinationEntity = schedule
        scheduleItems.minCount = 0
        scheduleItems.maxCount = 0 // to-many
        scheduleItems.deleteRule = .cascadeDeleteRule
        scheduleItems.isOptional = true

        let scheduleOwner = NSRelationshipDescription()
        scheduleOwner.name = "baby"
        scheduleOwner.destinationEntity = baby
        scheduleOwner.minCount = 0
        scheduleOwner.maxCount = 1
        scheduleOwner.deleteRule = .nullifyDeleteRule
        scheduleOwner.isOptional = true

        scheduleItems.inverseRelationship = scheduleOwner
        scheduleOwner.inverseRelationship = scheduleItems

        schedule.properties = [
            attribute("itemID", .uuid),
            attribute("kindRaw", .string, default: EntryKind.feed.rawValue),
            attribute("title", .string, default: ""),
            attribute("minuteOfDay", .integer16, default: 0),
            attribute("remind", .boolean, default: false),
            attribute("isEnabled", .boolean, default: true),
            attribute("createdAt", .date),
            scheduleOwner,
        ]

        baby.properties = [
            attribute("babyID", .uuid),
            attribute("name", .string, default: ""),
            attribute("birthday", .date),
            attribute("genderRaw", .string, default: BabyGender.both.rawValue),
            attribute("createdAt", .date),
            entries,
            scheduleItems,
        ]

        entry.properties = [
            attribute("entryID", .uuid),
            attribute("kindRaw", .string, default: EntryKind.feed.rawValue),
            attribute("timestamp", .date),
            attribute("endTime", .date),
            attribute("isTimerRunning", .boolean, default: false),
            attribute("feedTypeRaw", .string),
            attribute("amountML", .double),
            attribute("diaperTypeRaw", .string),
            attribute("sleepLocationRaw", .string),
            attribute("symptomRaw", .string),
            attribute("severityRaw", .string),
            attribute("temperatureC", .double),
            attribute("leftML", .double),
            attribute("rightML", .double),
            attribute("notes", .string, default: ""),
            owner,
        ]

        // Growth measurements (weight, length, head size), shared with the baby.
        let measurement = NSEntityDescription()
        measurement.name = "GrowthMeasurement"
        measurement.managedObjectClassName = NSStringFromClass(GrowthMeasurement.self)

        let measurements = NSRelationshipDescription()
        measurements.name = "measurements"
        measurements.destinationEntity = measurement
        measurements.minCount = 0
        measurements.maxCount = 0 // to-many
        measurements.deleteRule = .cascadeDeleteRule
        measurements.isOptional = true

        let measurementOwner = NSRelationshipDescription()
        measurementOwner.name = "baby"
        measurementOwner.destinationEntity = baby
        measurementOwner.minCount = 0
        measurementOwner.maxCount = 1
        measurementOwner.deleteRule = .nullifyDeleteRule
        measurementOwner.isOptional = true

        measurements.inverseRelationship = measurementOwner
        measurementOwner.inverseRelationship = measurements

        measurement.properties = [
            attribute("measurementID", .uuid),
            attribute("date", .date),
            attribute("weightKg", .double),
            attribute("lengthCm", .double),
            attribute("headCm", .double),
            attribute("notes", .string, default: ""),
            measurementOwner,
        ]
        baby.properties.append(measurements)

        let model = NSManagedObjectModel()
        model.entities = [baby, entry, schedule, measurement]
        return model
    }()
}

/// The theme and wording chosen for a baby.
nonisolated enum BabyGender: String, CaseIterable, Identifiable, Sendable {
    case girl
    case boy
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .girl: "Girl"
        case .boy: "Boy"
        case .both: "Both"
        }
    }

    var subtitle: String {
        switch self {
        case .girl: "Rosy pinks and lavender"
        case .boy: "Sky blues and lavender"
        case .both: "Lavender, pink and mint"
        }
    }
}

// MARK: - Baby

/// A baby profile. Each baby has its own entries and can be shared with a partner.
@objc(Baby)
nonisolated final class Baby: NSManagedObject, Identifiable {
    @NSManaged var babyID: UUID?
    @NSManaged var name: String?
    @NSManaged var birthday: Date?
    @NSManaged var genderRaw: String?
    @NSManaged var createdAt: Date?
    @NSManaged var entries: NSSet?
    @NSManaged var scheduleItems: NSSet?
    @NSManaged var measurements: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        babyID = UUID()
        createdAt = .now
    }

    convenience init(context: NSManagedObjectContext, name: String, birthday: Date?, gender: BabyGender) {
        self.init(context: context)
        self.name = name
        self.birthday = birthday
        self.gender = gender
    }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Baby" : trimmed
    }

    var gender: BabyGender {
        get { genderRaw.flatMap(BabyGender.init(rawValue:)) ?? .both }
        set { genderRaw = newValue.rawValue }
    }

    /// Birthday as seconds since 1970, or 0 when not set (the format `BabyAge` expects).
    var birthdayInterval: Double { birthday?.timeIntervalSince1970 ?? 0 }

    static func fetchAll() -> NSFetchRequest<Baby> {
        let request = NSFetchRequest<Baby>(entityName: "Baby")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }
}

// MARK: - Entry

/// A single logged event. Enum values are stored as raw strings so they persist reliably.
@objc(BabyEntry)
nonisolated final class BabyEntry: NSManagedObject, Identifiable {
    /// Stable identifier used by Live Activities and widgets to find this entry.
    @NSManaged var entryID: UUID
    @NSManaged var kindRaw: String
    @NSManaged var timestamp: Date
    /// End time for sleeps (nil while the baby is still sleeping) and optionally for breast feeds.
    @NSManaged var endTime: Date?
    /// True while a breastfeeding timer is running for this entry.
    @NSManaged var isTimerRunning: Bool
    @NSManaged var feedTypeRaw: String?
    @NSManaged var diaperTypeRaw: String?
    @NSManaged var sleepLocationRaw: String?
    @NSManaged var symptomRaw: String?
    @NSManaged var severityRaw: String?
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        entryID = UUID()
        timestamp = .now
        kindRaw = EntryKind.feed.rawValue
        notes = ""
    }

    /// Creates an entry for a baby. Entries for a shared baby go into the same (shared) store,
    /// so a partner sees them too.
    convenience init(
        context: NSManagedObjectContext,
        baby: Baby?,
        kind: EntryKind,
        timestamp: Date = .now,
        endTime: Date? = nil,
        isTimerRunning: Bool = false,
        feedType: FeedType? = nil,
        amountML: Double? = nil,
        diaperType: DiaperType? = nil,
        symptom: Symptom? = nil,
        severity: Severity? = nil,
        temperatureC: Double? = nil,
        notes: String = ""
    ) {
        self.init(context: context)
        self.kindRaw = kind.rawValue
        self.timestamp = timestamp
        self.endTime = endTime
        self.isTimerRunning = isTimerRunning
        self.feedTypeRaw = feedType?.rawValue
        self.amountML = amountML
        self.diaperTypeRaw = diaperType?.rawValue
        self.symptomRaw = symptom?.rawValue
        self.severityRaw = severity?.rawValue
        self.temperatureC = temperatureC
        self.notes = notes
        if let baby {
            self.baby = baby
            if let store = baby.objectID.persistentStore {
                context.assign(self, to: store)
            }
        }
    }

    // Optional numbers use key-value access because @NSManaged can't expose an optional Double.

    /// Bottle amount, always stored in millilitres and converted for display.
    var amountML: Double? {
        get { (value(forKey: "amountML") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "amountML") }
    }

    /// Pumped amount from each side, in millilitres.
    var leftML: Double? {
        get { (value(forKey: "leftML") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "leftML") }
    }

    var rightML: Double? {
        get { (value(forKey: "rightML") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "rightML") }
    }

    /// Body temperature, always stored in Celsius and converted for display.
    var temperatureC: Double? {
        get { (value(forKey: "temperatureC") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "temperatureC") }
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .feed }
        set { kindRaw = newValue.rawValue }
    }

    var feedType: FeedType? {
        get { feedTypeRaw.flatMap(FeedType.init(rawValue:)) }
        set { feedTypeRaw = newValue?.rawValue }
    }

    var diaperType: DiaperType? {
        get { diaperTypeRaw.flatMap(DiaperType.init(rawValue:)) }
        set { diaperTypeRaw = newValue?.rawValue }
    }

    var sleepLocation: SleepLocation? {
        get { sleepLocationRaw.flatMap(SleepLocation.init(rawValue:)) }
        set { sleepLocationRaw = newValue?.rawValue }
    }

    var symptom: Symptom? {
        get { symptomRaw.flatMap(Symptom.init(rawValue:)) }
        set { symptomRaw = newValue?.rawValue }
    }

    var severity: Severity? {
        get { severityRaw.flatMap(Severity.init(rawValue:)) }
        set { severityRaw = newValue?.rawValue }
    }

    /// Temperature formatted in the unit chosen in Settings (°C or °F).
    func formattedTemperature(in preference: TemperatureUnitPreference) -> String? {
        guard let temperatureC else { return nil }
        let unit: UnitTemperature = preference.usesFahrenheit ? .fahrenheit : .celsius
        return Measurement(value: temperatureC, unit: UnitTemperature.celsius)
            .converted(to: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    /// True for a sleep that has been started but not yet ended.
    var isOngoingSleep: Bool {
        kind == .sleep && endTime == nil
    }

    /// True for a breastfeeding session whose timer is still running.
    var isOngoingFeed: Bool {
        kind == .feed && isTimerRunning && endTime == nil
    }

    /// True for anything with a live timer (sleep or breastfeeding).
    var isInProgress: Bool {
        isOngoingSleep || isOngoingFeed
    }

    /// Duration in seconds, using "now" for anything still in progress.
    var duration: TimeInterval? {
        guard kind == .sleep || endTime != nil || isOngoingFeed else { return nil }
        return (endTime ?? .now).timeIntervalSince(timestamp)
    }

    /// Ends a running sleep or breastfeeding timer.
    func finish(at date: Date = .now) {
        endTime = max(date, timestamp)
        isTimerRunning = false
    }

    /// Short human-readable summary shown in lists.
    func detail(temperatureUnit: TemperatureUnitPreference, volumeUnit: VolumeUnitPreference) -> String {
        var parts: [String] = []
        switch kind {
        case .feed:
            if let feedType { parts.append(feedType.title) }
            if let amountML, amountML > 0 { parts.append(volumeUnit.format(milliliters: amountML)) }
            if isOngoingFeed {
                parts.append("Feeding…")
            } else if let duration {
                parts.append(Self.format(duration))
            }
        case .sleep:
            let start = timestamp.formatted(date: .omitted, time: .shortened)
            if isOngoingSleep {
                parts.append("\(start) – now")
                parts.append("Sleeping…")
            } else if let endTime, let duration {
                parts.append("\(start) – \(endTime.formatted(date: .omitted, time: .shortened))")
                parts.append(Self.format(duration))
            }
            if let sleepLocation { parts.append(sleepLocation.title) }
        case .diaper:
            if let diaperType { parts.append(diaperType.title) }
        case .health:
            if let symptom { parts.append(symptom.title) }
            if let temperature = formattedTemperature(in: temperatureUnit) { parts.append(temperature) }
            if let severity { parts.append(severity.title) }
        case .pump:
            let total = (leftML ?? 0) + (rightML ?? 0)
            if total > 0 { parts.append(volumeUnit.format(milliliters: total)) }
            var sides: [String] = []
            if let leftML, leftML > 0 { sides.append(String(localized: "L \(volumeUnit.format(milliliters: leftML))")) }
            if let rightML, rightML > 0 { sides.append(String(localized: "R \(volumeUnit.format(milliliters: rightML))")) }
            if !sides.isEmpty { parts.append(sides.joined(separator: " / ")) }
            if let endTime { parts.append(Self.format(endTime.timeIntervalSince(timestamp))) }
        }
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    static func format(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(interval, 0)) ?? ""
    }

    /// Entries for one baby, newest first.
    static func fetch(for baby: Baby?, kinds: [EntryKind]? = nil, limit: Int = 0) -> NSFetchRequest<BabyEntry> {
        let request = NSFetchRequest<BabyEntry>(entityName: "BabyEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        var predicates: [NSPredicate] = []
        if let baby {
            predicates.append(NSPredicate(format: "baby == %@", baby))
        }
        if let kinds {
            predicates.append(NSPredicate(format: "kindRaw IN %@", kinds.map(\.rawValue)))
        }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.fetchLimit = limit
        return request
    }
}

// MARK: - Schedule

/// One item in a parent's own daily schedule, repeated every day.
@objc(ScheduleItem)
nonisolated final class ScheduleItem: NSManagedObject, Identifiable {
    @NSManaged var itemID: UUID?
    @NSManaged var kindRaw: String
    @NSManaged var title: String
    /// Minutes after midnight, e.g. 450 for 7:30 AM.
    @NSManaged var minuteOfDay: Int16
    /// Send a notification at this time each day.
    @NSManaged var remind: Bool
    @NSManaged var isEnabled: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var baby: Baby?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        itemID = UUID()
        createdAt = .now
        kindRaw = EntryKind.feed.rawValue
        title = ""
        isEnabled = true
    }

    /// Creates an item for a baby, in the same (possibly shared) store as the baby.
    convenience init(context: NSManagedObjectContext, baby: Baby, kind: EntryKind, title: String, minuteOfDay: Int, remind: Bool = false) {
        self.init(context: context)
        self.kindRaw = kind.rawValue
        self.title = title
        self.minuteOfDay = Int16(clamping: minuteOfDay)
        self.remind = remind
        self.baby = baby
        if let store = baby.objectID.persistentStore {
            context.assign(self, to: store)
        }
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .feed }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    /// Today's (or another day's) occurrence of this item.
    func time(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(Int(minuteOfDay) * 60))
    }

    static func fetch(for baby: Baby) -> NSFetchRequest<ScheduleItem> {
        let request = NSFetchRequest<ScheduleItem>(entityName: "ScheduleItem")
        request.predicate = NSPredicate(format: "baby == %@", baby)
        request.sortDescriptors = [NSSortDescriptor(key: "minuteOfDay", ascending: true)]
        return request
    }
}

// MARK: - Growth

/// One growth check: any of weight, length and head size.
@objc(GrowthMeasurement)
nonisolated final class GrowthMeasurement: NSManagedObject, Identifiable {
    @NSManaged var measurementID: UUID?
    @NSManaged var date: Date?
    @NSManaged var notes: String
    @NSManaged var baby: Baby?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        measurementID = UUID()
        date = .now
        notes = ""
    }

    /// Creates a measurement in the same (possibly shared) store as the baby.
    convenience init(context: NSManagedObjectContext, baby: Baby, date: Date) {
        self.init(context: context)
        self.date = date
        self.baby = baby
        if let store = baby.objectID.persistentStore {
            context.assign(self, to: store)
        }
    }

    // Optional numbers use key-value access because @NSManaged can't expose an optional Double.
    var weightKg: Double? {
        get { (value(forKey: "weightKg") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "weightKg") }
    }

    var lengthCm: Double? {
        get { (value(forKey: "lengthCm") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "lengthCm") }
    }

    var headCm: Double? {
        get { (value(forKey: "headCm") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "headCm") }
    }

    static func fetch(for baby: Baby) -> NSFetchRequest<GrowthMeasurement> {
        let request = NSFetchRequest<GrowthMeasurement>(entityName: "GrowthMeasurement")
        request.predicate = NSPredicate(format: "baby == %@", baby)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return request
    }
}
