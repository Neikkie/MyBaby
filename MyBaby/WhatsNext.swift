import SwiftUI

/// Estimates for the Today screen's "What's Next" section.
///
/// These are simple, transparent rules — the baby's own recent rhythm first,
/// falling back to typical ranges for their age — not medical guidance.
struct WhatsNextPlanner {
    let entries: [BabyEntry]   // newest first
    let age: BabyAge?
    var now: Date = .now

    // MARK: Feeds

    /// Start times of feeding sessions, newest first. Back-to-back entries within
    /// 30 minutes (such as switching breasts) count as one session.
    var feedSessionStarts: [Date] {
        let starts = entries.filter { $0.kind == .feed }.map(\.timestamp).sorted()
        var sessions: [Date] = []
        for start in starts {
            if let last = sessions.last, start.timeIntervalSince(last) < 30 * 60 { continue }
            sessions.append(start)
        }
        return sessions.reversed()
    }

    /// Typical time between feeds for the baby's age, used until there's enough history.
    var typicalFeedInterval: TimeInterval {
        guard let age else { return 3 * 3600 }
        switch age.weeks {
        case ..<4: return 2.5 * 3600
        case ..<12: return 3 * 3600
        case ..<26: return 3.5 * 3600
        default: return 4 * 3600
        }
    }

    /// Median gap between the last few feeds in the past two days, or the age-typical interval.
    var feedInterval: (interval: TimeInterval, isFromHistory: Bool) {
        let recent = feedSessionStarts.filter { now.timeIntervalSince($0) < 48 * 3600 }.prefix(9)
        let gaps = zip(recent, recent.dropFirst()).map { $0.timeIntervalSince($1) }.sorted()
        guard gaps.count >= 3 else { return (typicalFeedInterval, false) }
        let median = gaps[gaps.count / 2]
        return (min(max(median, 3600), 6 * 3600), true)
    }

    var nextFeed: Date? {
        feedSessionStarts.first.map { $0.addingTimeInterval(feedInterval.interval) }
    }

    /// The breast to start on next: the opposite of the last side used.
    var suggestedSide: FeedType? {
        entries.first { $0.kind == .feed && $0.feedType?.isBreast == true }?.feedType?.otherSide
    }

    // MARK: Sleep

    /// Typical awake time between sleeps for the baby's age (a range, in minutes).
    var wakeWindow: ClosedRange<Double> {
        guard let age else { return 60...120 }
        switch age.weeks {
        case ..<4: return 35...60
        case ..<8: return 45...75
        case ..<12: return 60...90
        case ..<16: return 75...120
        case ..<26: return 105...150
        case ..<35: return 120...180
        case ..<52: return 150...240
        case ..<78: return 180...300
        default: return 300...360
        }
    }

    var ongoingSleep: BabyEntry? {
        entries.first { $0.isOngoingSleep }
    }

    /// When the baby last woke up, if there's a finished sleep.
    var lastWake: Date? {
        entries.first { $0.kind == .sleep && $0.endTime != nil }?.endTime
    }

    /// Window in which the next sleep is likely, based on the wake window.
    var nextSleepWindow: ClosedRange<Date>? {
        guard ongoingSleep == nil, let lastWake else { return nil }
        let start = lastWake.addingTimeInterval(wakeWindow.lowerBound * 60)
        let end = lastWake.addingTimeInterval(wakeWindow.upperBound * 60)
        return start...end
    }

    // MARK: Diapers

    /// Wet (including mixed) diapers logged today.
    var wetDiapersToday: Int {
        entries.filter {
            $0.kind == .diaper && Calendar.current.isDate($0.timestamp, inSameDayAs: now)
                && ($0.diaperType == .wet || $0.diaperType == .both)
        }.count
    }

    /// Show the wet-diaper goal for young babies, when it's a useful sign of feeding.
    /// Babies are commonly expected to have 6 or more wet diapers a day after the first week.
    var showsWetDiaperGoal: Bool {
        guard let age else { return false }
        return age.days >= 7 && age.weeks < 26
    }
}

extension WhatsNextPlanner {
    /// "in 25 min", "due now" or "20 min overdue".
    static func dueText(for date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes > 1 { return "in \(BabyEntry.format(TimeInterval(minutes * 60)))" }
        if minutes >= -5 { return "due now" }
        return "\(BabyEntry.format(TimeInterval(-minutes * 60))) overdue"
    }
}
