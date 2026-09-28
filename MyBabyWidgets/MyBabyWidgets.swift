import WidgetKit
import SwiftUI
import CoreData
import AppIntents

// MARK: - Timeline

/// What the widgets show: the most recent feed, sleep and diaper.
struct SinceLastEntry: TimelineEntry {
    let date: Date
    var lastFeed: Date?
    var lastSleepEnd: Date?
    var lastDiaper: Date?
    /// Start of a sleep that's still going.
    var sleepingSince: Date?
    /// Start of a breastfeeding timer that's still running, and its side.
    var feedingSince: Date?
    var feedingSide: String?

    static let placeholder = SinceLastEntry(
        date: .now,
        lastFeed: .now.addingTimeInterval(-5400),
        lastSleepEnd: .now.addingTimeInterval(-3600),
        lastDiaper: .now.addingTimeInterval(-1800)
    )
}

struct SinceLastProvider: TimelineProvider {
    func placeholder(in context: Context) -> SinceLastEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SinceLastEntry) -> Void) {
        completion(context.isPreview ? .placeholder : Self.loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SinceLastEntry>) -> Void) {
        // Relative times update on their own; refresh occasionally to pick up synced changes.
        let entry = Self.loadEntry()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    /// Reads the selected baby's latest activity on a background context.
    static func loadEntry() -> SinceLastEntry {
        let context = PersistenceController.shared.container.newBackgroundContext()
        var result = SinceLastEntry(date: .now)
        context.performAndWait {
            let baby = SelectedBaby.resolve(in: context)
            let entries = (try? context.fetch(BabyEntry.fetch(for: baby, limit: 200))) ?? []

            let lastFeed = entries.first { $0.kind == .feed }
            let lastSleep = entries.first { $0.kind == .sleep }
            let ongoingFeed = entries.first { $0.isOngoingFeed }

            result = SinceLastEntry(
                date: .now,
                lastFeed: lastFeed?.timestamp,
                lastSleepEnd: lastSleep?.endTime,
                lastDiaper: entries.first { $0.kind == .diaper }?.timestamp,
                sleepingSince: lastSleep?.isOngoingSleep == true ? lastSleep?.timestamp : nil,
                feedingSince: ongoingFeed?.timestamp,
                feedingSide: ongoingFeed?.feedType?.sideTitle
            )
        }
        return result
    }
}

// MARK: - Views

/// One "Feed · 1 hr, 20 min" line, or a running timer if something is in progress.
private struct SinceLastLine: View {
    let kind: EntryKind
    let date: Date?
    var runningSince: Date?
    var runningLabel: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.textColor)
                .widgetAccentable()
                .frame(width: 18)
            if let runningSince {
                Text(runningLabel ?? kind.title)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                Text(runningSince, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text(kind.title)
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                if let date {
                    Text(date, style: .relative)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct SinceLastList: View {
    let entry: SinceLastEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SinceLastLine(
                kind: .feed,
                date: entry.lastFeed,
                runningSince: entry.feedingSince,
                runningLabel: entry.feedingSide.map { "Feeding \($0)" }
            )
            SinceLastLine(
                kind: .sleep,
                date: entry.lastSleepEnd,
                runningSince: entry.sleepingSince,
                runningLabel: "Asleep"
            )
            SinceLastLine(kind: .diaper, date: entry.lastDiaper)
        }
    }
}

/// Wet / Poop buttons that log a diaper without opening the app.
private struct DiaperButtons: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach([DiaperType.wet, .dirty]) { type in
                Button(intent: LogDiaperIntent(type: type)) {
                    Label(type.title, systemImage: type == .wet ? "drop" : "circle.dotted")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(EntryKind.diaper.color)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct SinceLastWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SinceLastEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                SinceLastLine(kind: .feed, date: entry.lastFeed, runningSince: entry.feedingSince, runningLabel: "Feeding")
                SinceLastLine(kind: .sleep, date: entry.lastSleepEnd, runningSince: entry.sleepingSince, runningLabel: "Asleep")
                SinceLastLine(kind: .diaper, date: entry.lastDiaper)
            }
        case .accessoryInline:
            if let lastFeed = entry.lastFeed {
                Label {
                    Text("Fed \(lastFeed, style: .relative) ago")
                } icon: {
                    Image(systemName: EntryKind.feed.symbol)
                }
            } else {
                Label("No feeds yet", systemImage: EntryKind.feed.symbol)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Since Last")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    SinceLastList(entry: entry)
                }
                DiaperButtons()
                    .frame(width: 110)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Since Last")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                SinceLastList(entry: entry)
                Spacer(minLength: 0)
            }
        }
    }
}

struct SinceLastWidget: Widget {
    let kind = "SinceLastWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SinceLastProvider()) { entry in
            SinceLastWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Since Last")
        .description("See how long it's been since the last feed, sleep and diaper.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    SinceLastWidget()
} timeline: {
    SinceLastEntry.placeholder
    SinceLastEntry(date: .now, lastFeed: .now.addingTimeInterval(-600), lastDiaper: .now.addingTimeInterval(-900),
                   sleepingSince: .now.addingTimeInterval(-1500))
}

#Preview("Medium", as: .systemMedium) {
    SinceLastWidget()
} timeline: {
    SinceLastEntry.placeholder
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    SinceLastWidget()
} timeline: {
    SinceLastEntry.placeholder
}
