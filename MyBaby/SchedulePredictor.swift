import CoreData
import Foundation

/// Something expected in the coming hours: predicted from the baby's patterns, or from the parent's own schedule.
struct PlannedItem: Identifiable, Hashable {
    enum Source: Hashable {
        case predicted
        case schedule
    }

    let id: String
    let kind: EntryKind
    let title: String
    let time: Date
    /// For naps: the end of the likely window.
    var windowEnd: Date?
    let source: Source
    /// Short explanation, e.g. "About every 2h 50m lately".
    let reason: String
    /// Already logged (schedule items only).
    var isDone = false
    /// Happening right now (e.g. asleep, expecting to wake).
    var isRunning = false
}

/// What the predictor learned from the log, shown so parents can see why it suggests what it does.
struct PatternSummary {
    enum Confidence: String {
        case starting = "Just getting started"
        case learning = "Learning"
        case confident = "Knows the rhythm"
    }

    var daysOfData = 0
    var feedsPerDay: Double?
    var dayFeedGap: TimeInterval?
    var nightFeedGap: TimeInterval?
    var napLength: TimeInterval?
    var wakeWindow: TimeInterval?
    var napsPerDay: Double?
    var sleepPerDay: TimeInterval?
    /// Minutes after midnight; may exceed 1440 for after-midnight bedtimes.
    var bedtimeMinute: Int?
    var wakeUpMinute: Int?
    var diapersPerDay: Double?
    var diaperGap: TimeInterval?
    var confidence: Confidence = .starting
}

/// On-device pattern analysis that predicts the rest of the day.
///
/// It learns the baby's own rhythm from the last two weeks of entries — feeding gaps (day and night
/// separately), nap lengths, awake time between sleeps, bedtime and wake-up time, meal times for
/// toddlers — and blends that with what's typical at the baby's age. The more days logged, the more
/// the baby's own pattern wins over the age defaults.
struct SchedulePredictor {
    let entries: [BabyEntry]          // newest first
    let schedule: [ScheduleItem]
    let age: BabyAge?
    var now: Date = .now
    /// How far ahead to plan.
    var horizon: TimeInterval = 12 * 3600

    private var calendar: Calendar { .current }
    private var months: Int { age?.months ?? 0 }
    private var isToddler: Bool { months >= 12 }

    // MARK: Learning

    /// Entries from the last 14 days, oldest first.
    private var recent: [BabyEntry] {
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        return entries.filter { $0.timestamp >= cutoff }.reversed()
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func isDaytime(_ date: Date) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 6 && hour < 19
    }

    /// Milk-feed sessions (back-to-back sides merged), oldest first.
    private var feedSessions: [Date] {
        let starts = recent
            .filter { $0.kind == .feed && !($0.feedType?.isMeal ?? false) && $0.feedType != .solids }
            .map(\.timestamp)
        var sessions: [Date] = []
        for start in starts where sessions.last.map({ start.timeIntervalSince($0) >= 30 * 60 }) ?? true {
            sessions.append(start)
        }
        return sessions
    }

    private var finishedSleeps: [BabyEntry] {
        recent.filter { $0.kind == .sleep && $0.endTime != nil && ($0.duration ?? 0) >= 10 * 60 }
    }

    /// A sleep is "night" sleep if it starts in the evening or night and lasts at least 3 hours.
    private func isNightSleep(_ sleep: BabyEntry) -> Bool {
        let hour = calendar.component(.hour, from: sleep.timestamp)
        return (hour >= 18 || hour < 5) && (sleep.duration ?? 0) >= 3 * 3600
    }

    func learn() -> PatternSummary {
        var summary = PatternSummary()
        let days = Set(recent.map { calendar.startOfDay(for: $0.timestamp) })
        summary.daysOfData = days.count
        summary.confidence = days.count >= 5 ? .confident : days.count >= 2 ? .learning : .starting
        let dayCount = Double(max(days.count, 1))

        // Feeds: gaps between sessions, split by time of day.
        let sessions = feedSessions
        var dayGaps: [Double] = []
        var nightGaps: [Double] = []
        for (earlier, later) in zip(sessions, sessions.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            guard gap > 45 * 60, gap < 9 * 3600 else { continue }
            if isDaytime(earlier) { dayGaps.append(gap) } else { nightGaps.append(gap) }
        }
        if dayGaps.count >= 3 { summary.dayFeedGap = median(dayGaps) }
        if nightGaps.count >= 2 { summary.nightFeedGap = median(nightGaps) }
        if !sessions.isEmpty { summary.feedsPerDay = Double(sessions.count) / dayCount }

        // Sleep: nap lengths, awake time before sleeping, bedtime and wake-up.
        let sleeps = finishedSleeps
        let naps = sleeps.filter { !isNightSleep($0) }
        let nights = sleeps.filter(isNightSleep)
        if naps.count >= 3 { summary.napLength = median(naps.compactMap(\.duration)) }
        if !naps.isEmpty { summary.napsPerDay = Double(naps.count) / dayCount }
        if !sleeps.isEmpty { summary.sleepPerDay = sleeps.compactMap(\.duration).reduce(0, +) / dayCount }

        var windows: [Double] = []
        for (earlier, later) in zip(sleeps, sleeps.dropFirst()) {
            guard let wake = earlier.endTime else { continue }
            let awake = later.timestamp.timeIntervalSince(wake)
            if awake > 20 * 60, awake < 6 * 3600, isDaytime(wake) { windows.append(awake) }
        }
        if windows.count >= 3 { summary.wakeWindow = median(windows) }

        if nights.count >= 2 {
            let bedtimes = nights.map { sleep -> Double in
                let minute = minuteOfDay(sleep.timestamp)
                return Double(minute < 5 * 60 ? minute + 1440 : minute)
            }
            summary.bedtimeMinute = median(bedtimes).map { Int($0) }
            summary.wakeUpMinute = median(nights.compactMap { $0.endTime.map { Double(minuteOfDay($0)) } }).map { Int($0) }
        }

        let diapers = recent.filter { $0.kind == .diaper }
        if !diapers.isEmpty { summary.diapersPerDay = Double(diapers.count) / dayCount }
        // Gaps between daytime changes (overnight stretches would skew it).
        let diaperGaps = zip(diapers, diapers.dropFirst()).compactMap { earlier, later -> Double? in
            let gap = later.timestamp.timeIntervalSince(earlier.timestamp)
            return gap > 30 * 60 && gap < 6 * 3600 && isDaytime(earlier.timestamp) ? gap : nil
        }
        if diaperGaps.count >= 3 { summary.diaperGap = median(diaperGaps) }
        return summary
    }

    // MARK: Age defaults

    private var ageFeedGap: TimeInterval {
        WhatsNextPlanner(entries: [], age: age, now: now).typicalFeedInterval
    }

    private var ageWakeWindow: ClosedRange<Double> {
        WhatsNextPlanner(entries: [], age: age, now: now).wakeWindow
    }

    private var ageNapLength: TimeInterval {
        switch months {
        case ..<4: 45 * 60
        case ..<12: 60 * 60
        default: 90 * 60
        }
    }

    private var ageNapsPerDay: Int {
        switch months {
        case ..<3: 5
        case ..<6: 4
        case ..<9: 3
        case ..<15: 2
        case ..<36: 1
        default: 0
        }
    }

    /// Typical time between changes: newborns need changing often; toddlers in potty training
    /// are usually offered the potty about every two hours.
    private var ageDiaperGap: TimeInterval {
        switch months {
        case ..<3: 2.5 * 3600
        case ..<12: 3 * 3600
        case ..<24: 3.5 * 3600
        default: 2 * 3600
        }
    }

    /// Newborns don't have a set bedtime yet; after that, an evening bedtime is typical.
    private var ageBedtimeMinute: Int? { months < 3 ? nil : 19 * 60 + 30 }

    // MARK: Blending

    /// The baby's learned value, trusted more as days of data build up, kept within a sensible range.
    private func blend(learned: Double?, typical: Double, range: ClosedRange<Double>, days: Int) -> Double {
        guard let learned else { return typical }
        let weight = min(Double(days) / 5, 1) * 0.7 + 0.3
        let mixed = learned * weight + typical * (1 - weight)
        return min(max(mixed, range.lowerBound), range.upperBound)
    }

    private func feedGap(at date: Date, _ summary: PatternSummary) -> TimeInterval {
        let typical = ageFeedGap
        if isDaytime(date) {
            return blend(learned: summary.dayFeedGap, typical: typical, range: typical * 0.6...typical * 1.5, days: summary.daysOfData)
        }
        // Night feeds are usually a little further apart.
        return blend(learned: summary.nightFeedGap ?? summary.dayFeedGap.map { $0 * 1.2 },
                     typical: typical * 1.2, range: typical * 0.7...typical * 2, days: summary.daysOfData)
    }

    private func wakeWindow(_ summary: PatternSummary) -> TimeInterval {
        let range = ageWakeWindow
        let typical = (range.lowerBound + range.upperBound) / 2 * 60
        return blend(learned: summary.wakeWindow, typical: typical,
                     range: range.lowerBound * 60 * 0.75...range.upperBound * 60 * 1.25, days: summary.daysOfData)
    }

    private func napLength(_ summary: PatternSummary) -> TimeInterval {
        blend(learned: summary.napLength, typical: ageNapLength, range: 20 * 60...3 * 3600, days: summary.daysOfData)
    }

    private func bedtime(_ summary: PatternSummary) -> Date? {
        let minute = summary.bedtimeMinute.map { m -> Int in
            let typical = Double(ageBedtimeMinute ?? m)
            return Int(blend(learned: Double(m), typical: typical, range: 17 * 60...24 * 60, days: summary.daysOfData))
        } ?? ageBedtimeMinute
        guard let minute else { return nil }
        let today = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minute * 60))
        // After tonight's bedtime (or deep in the night), look at tomorrow's.
        return today < now.addingTimeInterval(-2 * 3600) ? today.addingTimeInterval(86_400) : today
    }

    // MARK: Planning

    func plan() -> (items: [PlannedItem], summary: PatternSummary) {
        let summary = learn()
        var items: [PlannedItem] = []
        let end = now.addingTimeInterval(horizon)
        let learnedFrom = summary.daysOfData >= 2 ? "lately" : "for this age"

        // Feeds: chained from the last feed using the learned gap for each time of day.
        if !isToddler, let last = feedSessions.last ?? entries.first(where: { $0.kind == .feed })?.timestamp {
            if let feeding = entries.first(where: \.isOngoingFeed) {
                items.append(PlannedItem(id: "feed-now", kind: .feed, title: "Feeding now", time: feeding.timestamp,
                                         source: .predicted, reason: feeding.feedType?.sideTitle.map { "\($0) side" } ?? "", isRunning: true))
            }
            // Each feed is explained by the gap that led to it.
            var gap = feedGap(at: last, summary)
            var time = last.addingTimeInterval(gap)
            // If a feed is already overdue, show it as due now rather than in the past.
            if time < now { time = now }
            var count = 0
            while time < end, count < 4 {
                items.append(PlannedItem(
                    id: "feed-\(count)", kind: .feed, title: count == 0 ? "Next feed" : "Feed", time: time,
                    source: .predicted, reason: "About every \(BabyEntry.format(gap)) \(learnedFrom)"
                ))
                gap = feedGap(at: time, summary)
                time = time.addingTimeInterval(gap)
                count += 1
            }
        }

        // Toddlers: meals at their usual times.
        if isToddler {
            let defaults: [(FeedType, Int)] = [(.breakfast, 450), (.snack, 600), (.lunch, 720), (.snack, 900), (.dinner, 1050)]
            var snackIndex = 0
            for (meal, defaultMinute) in defaults {
                let learnedMinutes = recent.filter { $0.feedType == meal }.map { Double(minuteOfDay($0.timestamp)) }
                var minute = median(learnedMinutes).map(Int.init) ?? defaultMinute
                if meal == .snack {
                    // Two snacks: keep the learned one near the default it's closest to.
                    minute = learnedMinutes.count >= 4 ? minute + (snackIndex == 0 ? -150 : 150) : defaultMinute
                    snackIndex += 1
                }
                let time = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minute * 60))
                let loggedToday = entries.contains { $0.feedType == meal && calendar.isDateInToday($0.timestamp)
                    && abs($0.timestamp.timeIntervalSince(time)) < 2 * 3600 }
                guard !loggedToday, time > now.addingTimeInterval(-45 * 60), time < end else { continue }
                items.append(PlannedItem(id: "meal-\(meal.rawValue)-\(minute)", kind: .feed, title: meal.title, time: time,
                                         source: .predicted, reason: learnedMinutes.count >= 3 ? "Usual time" : "Typical time"))
            }
        }

        // Sleep: wake-up if sleeping, then naps chained by awake time, then bedtime.
        let bedtimeDate = bedtime(summary)
        let window = wakeWindow(summary)
        let nap = napLength(summary)
        var napsLeft = max(ageNapsPerDay - entries.filter {
            $0.kind == .sleep && calendar.isDateInToday($0.timestamp) && !isNightSleep($0)
        }.count, 0)

        var cursor: Date?
        if let sleeping = entries.first(where: \.isOngoingSleep) {
            let isNight = !isDaytime(sleeping.timestamp)
            let expected = isNight
                ? summary.wakeUpMinute.map { calendar.startOfDay(for: now).addingTimeInterval(TimeInterval($0 * 60)) }
                    .flatMap { $0 > now ? $0 : nil } ?? sleeping.timestamp.addingTimeInterval(10 * 3600)
                : sleeping.timestamp.addingTimeInterval(nap)
            items.append(PlannedItem(id: "wake", kind: .sleep, title: "Likely waking", time: max(expected, now),
                                     source: .predicted,
                                     reason: isNight ? "Usual wake-up" : "Naps last about \(BabyEntry.format(nap)) \(learnedFrom)",
                                     isRunning: true))
            cursor = max(expected, now)
        } else if let lastWake = entries.first(where: { $0.kind == .sleep && $0.endTime != nil })?.endTime {
            cursor = lastWake
        }

        if var wake = cursor {
            var index = 0
            while napsLeft > 0, index < 4 {
                var start = wake.addingTimeInterval(window)
                if start < now { start = now }
                if let bedtimeDate, start.addingTimeInterval(nap) > bedtimeDate.addingTimeInterval(-30 * 60) { break }
                guard start < end else { break }
                items.append(PlannedItem(
                    id: "nap-\(index)", kind: .sleep, title: index == 0 ? "Next nap" : "Nap", time: start,
                    windowEnd: start.addingTimeInterval(20 * 60), source: .predicted,
                    reason: "After about \(BabyEntry.format(window)) awake"
                ))
                wake = start.addingTimeInterval(nap)
                napsLeft -= 1
                index += 1
            }
        }
        let isAsleep = entries.contains(where: \.isOngoingSleep)
        if let bedtimeDate, !isAsleep, bedtimeDate > now.addingTimeInterval(-2 * 3600), bedtimeDate < end {
            let usual = bedtimeDate.formatted(date: .omitted, time: .shortened)
            let reason = summary.bedtimeMinute != nil ? "Usual bedtime" : "Typical bedtime for this age"
            // Past the usual bedtime and still awake: it's due now.
            items.append(PlannedItem(id: "bedtime", kind: .sleep, title: "Bedtime", time: max(bedtimeDate, now),
                                     source: .predicted, reason: bedtimeDate < now ? "\(reason) was \(usual)" : reason))
        }

        // Diaper changes (or potty breaks), chained from the last one. Overnight changes happen with
        // night feeds, so they aren't scheduled separately between bedtime and morning.
        let isPotty = months >= 24
        let diaperGap = blend(learned: summary.diaperGap, typical: ageDiaperGap,
                              range: ageDiaperGap * 0.6...ageDiaperGap * 1.6, days: summary.daysOfData)
        if let lastDiaper = entries.first(where: { $0.kind == .diaper })?.timestamp {
            var time = lastDiaper.addingTimeInterval(diaperGap)
            if time < now { time = now }
            var count = 0
            while time < end, count < 3 {
                let hour = calendar.component(.hour, from: time)
                let isNight = months >= 3 && (hour >= 22 || hour < 6)
                if !isNight {
                    items.append(PlannedItem(
                        id: "diaper-\(count)", kind: .diaper,
                        title: isPotty ? "Potty break" : (count == 0 ? "Next change" : "Diaper change"),
                        time: time, source: .predicted,
                        reason: "About every \(BabyEntry.format(diaperGap)) \(learnedFrom)"
                    ))
                    count += 1
                }
                time = time.addingTimeInterval(isNight ? 3600 : diaperGap)
            }
        }

        // The parent's own schedule wins over predictions of the same kind.
        let scheduled = scheduledItems(until: end)
        let scheduledKinds = Set(scheduled.map(\.kind))
        items.removeAll { $0.source == .predicted && !$0.isRunning && scheduledKinds.contains($0.kind) }
        items += scheduled

        return (items.sorted { $0.time < $1.time }, summary)
    }

    /// Today's occurrences of the parent's schedule (plus early ones tomorrow within the horizon).
    private func scheduledItems(until end: Date) -> [PlannedItem] {
        schedule.filter(\.isEnabled).compactMap { item in
            var time = item.time(on: now)
            if time < now.addingTimeInterval(-45 * 60) { time = item.time(on: now.addingTimeInterval(86_400)) }
            guard time < end else { return nil }
            let done = entries.contains {
                $0.kind == item.kind && abs($0.timestamp.timeIntervalSince(item.time(on: now))) < 60 * 60
            }
            return PlannedItem(id: "schedule-\(item.itemID?.uuidString ?? item.objectID.uriRepresentation().absoluteString)",
                               kind: item.kind, title: item.displayTitle, time: time, source: .schedule,
                               reason: "Your schedule", isDone: done && calendar.isDateInToday(time))
        }
    }

    // MARK: Suggested schedule

    /// A full day built from what's been learned, used to start a custom schedule.
    func suggestedDay() -> [(kind: EntryKind, title: String, minute: Int)] {
        let summary = learn()
        let wakeUp = summary.wakeUpMinute ?? 7 * 60
        let bed = summary.bedtimeMinute ?? ageBedtimeMinute ?? 19 * 60 + 30
        var day: [(EntryKind, String, Int)] = [(.sleep, "Wake up", wakeUp)]

        if isToddler {
            day += [(.feed, "Breakfast", wakeUp + 30), (.feed, "Snack", 600), (.feed, "Lunch", 720),
                    (.feed, "Snack", 900), (.feed, "Dinner", 1050)]
        } else {
            let gap = Int(feedGap(at: calendar.startOfDay(for: now).addingTimeInterval(12 * 3600), summary) / 60)
            var minute = wakeUp
            while minute < bed {
                day.append((.feed, "Feed", minute))
                minute += max(gap, 60)
            }
        }

        let window = Int(wakeWindow(summary) / 60)
        let napMinutes = Int(napLength(summary) / 60)
        var minute = wakeUp + window
        for index in 0..<ageNapsPerDay where minute + napMinutes < bed - 30 {
            day.append((.sleep, ageNapsPerDay > 1 ? "Nap \(index + 1)" : "Nap", minute))
            minute += napMinutes + window
        }
        day.append((.sleep, "Bedtime", min(bed, 1439)))
        return day.sorted { $0.2 < $1.2 }.map { (kind: $0.0, title: $0.1, minute: $0.2) }
    }
}
