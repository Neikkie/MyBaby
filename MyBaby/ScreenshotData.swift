import CoreData
import Foundation

/// Fills the simulator with a realistic few days of logs for App Store screenshots.
///
/// Launch in the simulator with `-screenshots` to replace all data with the sample baby,
/// and optionally `-screenshotTab history` (today, health, history or settings) to open a tab.
/// Only compiled into Debug simulator builds, so it never ships.
enum ScreenshotData {
    static var isEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-screenshots")
        #else
        false
        #endif
    }

    /// The tab to open first, from `-screenshotTab`.
    static var requestedTab: AppTab? {
        guard isEnabled else { return nil }
        switch UserDefaults.standard.string(forKey: "screenshotTab") {
        case "health": return .health
        case "history": return .history
        case "settings": return .settings
        default: return .today
        }
    }

    @MainActor
    static func seedIfRequested(_ persistence: PersistenceController) {
        #if DEBUG && targetEnvironment(simulator)
        guard isEnabled else { return }
        let context = persistence.viewContext

        // Start from a clean slate each launch so every screenshot run looks the same.
        for entity in ["BabyEntry", "ScheduleItem", "GrowthMeasurement", "Baby"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            (try? context.fetch(request))?.forEach(context.delete)
        }

        let calendar = Calendar.current
        let birthday = calendar.date(byAdding: .day, value: -75, to: .now) ?? .now
        let baby = Baby(context: context, name: "Ava", birthday: birthday, gender: .girl)
        _ = Baby(context: context, name: "Leo", birthday: calendar.date(byAdding: .year, value: -2, to: .now), gender: .boy)

        let hour: TimeInterval = 3600
        let startOfToday = calendar.startOfDay(for: .now)

        // Three days of feeds, sleeps and diapers ending shortly before now.
        for dayOffset in 0..<3 {
            let day = startOfToday.addingTimeInterval(-Double(dayOffset) * 24 * hour)
            let feedHours: [Double] = [0.5, 3.5, 6.5, 9.5, 12.5, 15.5, 18.5, 21.5]
            for (index, feedHour) in feedHours.enumerated() {
                let time = day.addingTimeInterval(feedHour * hour + Double(index % 3) * 600)
                guard time < .now.addingTimeInterval(-0.4 * hour) else { continue }
                let type: FeedType = index.isMultiple(of: 3) ? .formula : (index.isMultiple(of: 2) ? .breastLeft : .breastRight)
                let isBreast = type == .breastLeft || type == .breastRight
                _ = BabyEntry(
                    context: context, baby: baby, kind: .feed, timestamp: time,
                    endTime: isBreast ? time.addingTimeInterval(15 * 60) : nil,
                    feedType: type, amountML: isBreast ? nil : 120
                )

                // A nap follows most feeds, with a longer stretch overnight.
                let napStart = time.addingTimeInterval(0.6 * hour)
                let napLength = (feedHour >= 21 || feedHour < 3) ? 2.6 * hour : 1.4 * hour
                if napStart.addingTimeInterval(napLength) < .now {
                    _ = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: napStart, endTime: napStart.addingTimeInterval(napLength))
                }

                let diaperTime = time.addingTimeInterval(0.3 * hour)
                if diaperTime < .now {
                    let diaper: DiaperType = index.isMultiple(of: 3) ? .both : (index.isMultiple(of: 2) ? .dirty : .wet)
                    _ = BabyEntry(context: context, baby: baby, kind: .diaper, timestamp: diaperTime, diaperType: diaper)
                }
            }
        }

        _ = BabyEntry(
            context: context, baby: baby, kind: .health, timestamp: .now.addingTimeInterval(-26 * hour),
            symptom: .congestion, severity: .mild, notes: "Stuffy after nap, used saline drops"
        )
        _ = BabyEntry(
            context: context, baby: baby, kind: .health, timestamp: .now.addingTimeInterval(-5 * hour),
            symptom: .fever, severity: .mild, temperatureC: 37.9
        )

        for (days, kg, cm, head) in [(0.0, 3.4, 50.5, 34.5), (14, 3.9, 52.0, 35.8), (42, 4.9, 55.5, 37.6), (70, 5.6, 58.1, 38.7)] {
            let measurement = GrowthMeasurement(context: context, baby: baby, date: birthday.addingTimeInterval(days * 24 * hour))
            measurement.weightKg = kg
            measurement.lengthCm = cm
            measurement.headCm = head
        }

        _ = ScheduleItem(context: context, baby: baby, kind: .feed, title: "Morning feed", minuteOfDay: 7 * 60, remind: true)
        _ = ScheduleItem(context: context, baby: baby, kind: .sleep, title: "Bedtime", minuteOfDay: 19 * 60 + 30, remind: true)

        persistence.save()
        SelectedBaby.id = baby.babyID
        UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        #endif
    }
}
