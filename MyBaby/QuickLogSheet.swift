import CoreData
import SwiftUI

/// A small, friendly sheet with just the choices that matter for one kind of entry.
/// Tapping an option animates a checkmark, logs it, and closes.
struct QuickLogSheet: View {
    let kind: EntryKind
    @ObservedObject var baby: Baby
    let onLogged: (LogConfirmation) -> Void
    let onMoreDetails: () -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var fetchedEntries: FetchedResults<BabyEntry>
    @AppStorage(SettingsKey.volumeUnit) private var volumeUnit: VolumeUnitPreference = .system

    /// The option just chosen; shows its checkmark before the sheet closes.
    @State private var chosen: String?
    /// Formula, breast-milk bottle or cup of milk waiting for an amount.
    @State private var bottleType: FeedType?
    @State private var amount: Double = 0
    @State private var sleepLocation: SleepLocation?

    // Custom times: "now" unless the parent changes them.
    @State private var isChangingTime: Bool
    @State private var startTime = Date.now
    @State private var hasEndTime = false
    @State private var endTime = Date.now

    init(kind: EntryKind, baby: Baby, startsWithCustomTime: Bool = false,
         onLogged: @escaping (LogConfirmation) -> Void, onMoreDetails: @escaping () -> Void) {
        self.kind = kind
        _isChangingTime = State(initialValue: startsWithCustomTime)
        self.baby = baby
        self.onLogged = onLogged
        self.onMoreDetails = onMoreDetails
        _fetchedEntries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby, limit: 100))
    }

    private var entries: [BabyEntry] { Array(fetchedEntries) }
    private var age: BabyAge? { BabyAge(birthdayInterval: baby.birthdayInterval) }

    /// Only the feeding options that fit the baby's age.
    private var feedTypes: [FeedType] { FeedType.available(forMonths: age?.months) }

    private var ongoing: BabyEntry? { entries.first { $0.kind == kind && $0.isInProgress } }

    private var suggestedSide: FeedType {
        entries.first { $0.kind == .feed && $0.feedType?.isBreast == true }?.feedType?.otherSide ?? .breastLeft
    }

    /// Breastfeeding and sleep can be logged with an end time (a finished session) instead of a timer.
    private var allowsEndTime: Bool { kind == .sleep || (kind == .feed && feedTypes.contains(.breastLeft)) }

    /// The chosen start, or now.
    private var start: Date { isChangingTime ? startTime : .now }
    /// The chosen end, if a finished session is being logged.
    private var end: Date? { isChangingTime && hasEndTime && allowsEndTime ? max(endTime, startTime) : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if ongoing == nil {
                    TimeAdjuster(
                        isChanging: $isChangingTime,
                        start: $startTime,
                        hasEnd: $hasEndTime,
                        end: $endTime,
                        allowsEnd: allowsEndTime,
                        kind: kind
                    )
                }

                switch kind {
                case .feed: feedOptions
                case .sleep: sleepOptions
                default: diaperOptions
                }

                Button(action: onMoreDetails) {
                    Label("Add with more details…", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.success, trigger: chosen)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: bottleType)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: isChangingTime)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: hasEndTime)
        .onAppear {
            // Default to where the baby slept last time, if that's still age-appropriate.
            let last = entries.first { $0.kind == .sleep && $0.sleepLocation != nil }?.sleepLocation
            let options = SleepLocation.available(forMonths: age?.months)
            sleepLocation = last.flatMap { options.contains($0) ? $0 : nil } ?? options.first
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.title2)
                .foregroundStyle(kind.textColor)
                .frame(width: 48, height: 48)
                .background(kind.softColor, in: .rect(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                Text(baby.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch kind {
        case .feed: ongoing == nil ? "Log a Feed" : "Feeding"
        case .sleep: ongoing == nil ? "Log Sleep" : "Sleeping"
        default: TileStage.forKind(.diaper, age: age).isPottyStage ? "Potty Time" : "Log a Diaper"
        }
    }

    // MARK: Feed

    @ViewBuilder
    private var feedOptions: some View {
        if let ongoing, let side = ongoing.feedType {
            RunningTimer(start: ongoing.timestamp, label: "\(side.sideTitle ?? "") side", kind: .feed)
            HStack(spacing: 12) {
                if let other = side.otherSide {
                    OptionButton(id: "switch", title: "Switch to \(other.sideTitle ?? "")", symbol: "arrow.left.arrow.right",
                                 kind: .feed, chosen: chosen) {
                        switchSide(of: ongoing, to: other)
                    }
                }
                OptionButton(id: "stop", title: "Stop", symbol: "stop.fill", kind: .feed, chosen: chosen, isProminent: true) {
                    finish(ongoing, message: "Feed saved")
                }
            }
        } else {
            if feedTypes.contains(.breastLeft) {
                SectionLabel(end == nil ? "Breastfeeding timer" : "Breastfeeding")
                HStack(spacing: 12) {
                    ForEach([FeedType.breastLeft, .breastRight]) { side in
                        OptionButton(
                            id: side.rawValue,
                            title: end == nil ? "Start \(side.sideTitle ?? "")" : "\(side.sideTitle ?? "") Side",
                            symbol: "timer",
                            badge: side == suggestedSide ? "Next" : nil,
                            kind: .feed,
                            chosen: chosen
                        ) {
                            startFeed(side)
                        }
                    }
                }
            }

            if feedTypes.contains(.formula) {
                SectionLabel("Bottle")
                HStack(spacing: 12) {
                    OptionButton(id: "formula", title: "Formula", symbol: "drop.halffull", kind: .feed,
                                 chosen: bottleType == .formula ? "formula" : chosen) {
                        chooseBottle(.formula)
                    }
                    OptionButton(id: "milk", title: "Breast Milk", symbol: "drop.fill", kind: .feed,
                                 chosen: bottleType == .bottle ? "milk" : chosen) {
                        chooseBottle(.bottle)
                    }
                }
            }

            if let bottleType, bottleType != .cupMilk {
                AmountPicker(amount: $amount, unit: volumeUnit, buttonTitle: "Log Bottle") {
                    logBottle(bottleType)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if feedTypes.contains(.breakfast) {
                // Toddlers and older: meals, snacks and milk from a cup.
                SectionLabel("Meals")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(FeedType.meals) { meal in
                        OptionButton(id: meal.rawValue, title: meal.title, symbol: meal.symbol, kind: .feed, chosen: chosen) {
                            logFood(meal)
                        }
                    }
                }
                OptionButton(id: "cupMilk", title: "Milk (Cup)", symbol: "mug.fill", kind: .feed,
                             chosen: bottleType == .cupMilk ? "cupMilk" : chosen) {
                    chooseBottle(.cupMilk)
                }
                if bottleType == .cupMilk {
                    AmountPicker(amount: $amount, unit: volumeUnit, buttonTitle: "Log Milk") {
                        logBottle(.cupMilk)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else if feedTypes.contains(.solids) {
                SectionLabel("Food")
                OptionButton(id: "solids", title: "Solids", symbol: "carrot.fill", kind: .feed, chosen: chosen) {
                    logFood(.solids)
                }
            }
        }
    }

    // MARK: Sleep

    @ViewBuilder
    private var sleepOptions: some View {
        if let ongoing {
            RunningTimer(start: ongoing.timestamp, label: "Asleep", kind: .sleep)
            OptionButton(id: "wake", title: "Wake Up", symbol: "sun.horizon.fill", kind: .sleep, chosen: chosen, isProminent: true) {
                finish(ongoing, message: "Sleep saved")
            }
        } else {
            SectionLabel("Where?")
            LocationChips(
                options: SleepLocation.available(forMonths: age?.months),
                selection: $sleepLocation
            )
            OptionButton(
                id: "start",
                title: end != nil ? "Log Sleep" : isChangingTime ? "Start Sleep" : "Start Sleep Now",
                symbol: "moon.zzz.fill",
                kind: .sleep,
                chosen: chosen,
                isProminent: true
            ) {
                let entry = BabyEntry(context: context, baby: baby, kind: .sleep, timestamp: start, endTime: end)
                entry.sleepLocation = sleepLocation
                let message = end != nil
                    ? "Sleep logged · \(BabyEntry.format((end ?? start).timeIntervalSince(start)))"
                    : sleepLocation.map { "Sleep started · \($0.title)" } ?? "Sleep started"
                insert(entry, message: message, id: "start")
            }
            if (age?.months ?? 0) < 12 {
                Text("Safe sleep: on their back, on a firm, flat surface with no loose bedding.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Diaper

    @ViewBuilder
    private var diaperOptions: some View {
        // Potty-training toddlers get a "Used Potty" option first.
        if TileStage.forKind(.diaper, age: age).isPottyStage {
            OptionButton(id: DiaperType.potty.rawValue, title: "Used the Potty!", symbol: "toilet.fill",
                         kind: .diaper, chosen: chosen, isProminent: true) {
                insert(BabyEntry(context: context, baby: baby, kind: .diaper, timestamp: start, diaperType: .potty),
                       message: "Potty success logged 🎉")
            }
            SectionLabel("Diaper or accident")
        }
        HStack(spacing: 12) {
            ForEach(DiaperType.diaperCases) { type in
                OptionButton(
                    id: type.rawValue,
                    title: type.title,
                    symbol: type == .wet ? "drop.fill" : type == .dirty ? "circle.dotted" : "sparkles",
                    kind: .diaper,
                    chosen: chosen
                ) {
                    insert(BabyEntry(context: context, baby: baby, kind: .diaper, timestamp: start, diaperType: type),
                           message: "\(type.title) diaper logged")
                }
            }
        }
    }

    // MARK: Actions

    /// Saves, shows the checkmark briefly, then closes and reports what happened.
    private func complete(_ id: String, confirmation: LogConfirmation) {
        try? context.save()
        withAnimation(.spring(duration: 0.35, bounce: 0.5)) { chosen = id }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            dismiss()
            onLogged(confirmation)
        }
    }

    private func insert(_ entry: BabyEntry, message: String, id: String? = nil) {
        let context = context
        complete(id ?? entry.feedType?.rawValue ?? entry.diaperType?.rawValue ?? "start",
                 confirmation: LogConfirmation(kind: kind, message: message) {
            context.delete(entry)
            try? context.save()
        })
    }

    private func startFeed(_ side: FeedType) {
        if let end {
            // A finished feed with the times the parent entered.
            let entry = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: start, endTime: end, feedType: side)
            insert(entry, message: "\(side.sideTitle ?? "") side logged · \(BabyEntry.format(end.timeIntervalSince(start)))", id: side.rawValue)
        } else {
            let entry = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: start, isTimerRunning: true, feedType: side)
            insert(entry, message: "\(side.sideTitle ?? "") side timer started", id: side.rawValue)
        }
    }

    private func switchSide(of entry: BabyEntry, to other: FeedType) {
        let context = context
        entry.finish()
        let next = BabyEntry(context: context, baby: baby, kind: .feed, isTimerRunning: true, feedType: other)
        complete("switch", confirmation: LogConfirmation(kind: .feed, message: "Switched to \(other.sideTitle ?? "")") {
            context.delete(next)
            entry.endTime = nil
            entry.isTimerRunning = true
            try? context.save()
        })
    }

    private func finish(_ entry: BabyEntry, message: String) {
        let context = context
        let wasTimer = entry.isTimerRunning
        entry.finish()
        complete(entry.kind == .sleep ? "wake" : "stop", confirmation: LogConfirmation(kind: kind, message: message) {
            entry.endTime = nil
            entry.isTimerRunning = wasTimer
            try? context.save()
        })
    }

    private func logFood(_ type: FeedType) {
        insert(BabyEntry(context: context, baby: baby, kind: .feed, timestamp: start, feedType: type),
               message: "\(type.title) logged", id: type.rawValue)
    }

    private func chooseBottle(_ type: FeedType) {
        // Start from the last amount of the same kind of bottle, or a typical amount.
        let lastML = entries.first { $0.feedType == type }?.amountML ?? 90
        amount = volumeUnit.toDisplay(milliliters: lastML)
        bottleType = bottleType == type ? nil : type
    }

    private func logBottle(_ type: FeedType) {
        let ml = volumeUnit.toMilliliters(amount)
        let entry = BabyEntry(context: context, baby: baby, kind: .feed, timestamp: start, feedType: type, amountML: ml)
        let name = switch type {
        case .formula: "formula"
        case .cupMilk: "milk"
        default: "breast milk"
        }
        insert(entry, message: "\(volumeUnit.format(milliliters: ml)) \(name) logged",
               id: type == .formula ? "formula" : type == .cupMilk ? "cupMilk" : "milk")
    }
}

/// "Now" by default, with an easy way to set a different start, and an end for timed things.
private struct TimeAdjuster: View {
    @Binding var isChanging: Bool
    @Binding var start: Date
    @Binding var hasEnd: Bool
    @Binding var end: Date
    let allowsEnd: Bool
    let kind: EntryKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if !isChanging {
                    start = .now
                    end = .now
                }
                isChanging.toggle()
            } label: {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(kind.textColor)
                    Text(isChanging ? "Custom time" : "Now")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(isChanging ? "Use Now" : "Change Time")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(kind.softColor.opacity(0.6), in: .rect(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(SquishButtonStyle())

            if isChanging {
                VStack(spacing: 8) {
                    DatePicker(allowsEnd ? "Started" : "Time", selection: $start, in: ...Date.now)
                    if allowsEnd {
                        Toggle("Add end time", isOn: $hasEnd)
                        if hasEnd {
                            DatePicker("Ended", selection: $end, in: start...Date.now)
                            if end > start {
                                LabeledContent("Duration", value: BabyEntry.format(end.timeIntervalSince(start)))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
                .padding(14)
                .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Pieces

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, -8)
    }
}

/// A big pastel choice that springs when pressed and shows a bouncing checkmark when chosen.
private struct OptionButton: View {
    let id: String
    let title: String
    let symbol: String
    var badge: String?
    let kind: EntryKind
    let chosen: String?
    var isProminent = false
    let action: () -> Void

    private var isChosen: Bool { chosen == id }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : symbol)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isChosen)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(kind.textColor))
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.horizontal, 8)
            .background(isProminent ? kind.color : kind.softColor, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(kind.textColor, lineWidth: isChosen ? 2.5 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(kind.color, in: .capsule)
                        .padding(8)
                }
            }
            .scaleEffect(isChosen ? 1.04 : 1)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(badge.map { "\(title), suggested \($0.lowercased()) side" } ?? title)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

private struct RunningTimer: View {
    let start: Date
    let label: String
    let kind: EntryKind

    var body: some View {
        VStack(spacing: 4) {
            Text(start, style: .timer)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(kind.textColor)
                .contentTransition(.numericText())
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Big, easy-to-hit amount control for bottles.
private struct AmountPicker: View {
    @Binding var amount: Double
    let unit: VolumeUnitPreference
    var buttonTitle = "Log Bottle"
    let onLog: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                stepButton(symbol: "minus", delta: -unit.step)
                Text(unit.format(milliliters: unit.toMilliliters(amount)))
                    .font(.title.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: amount))
                    .frame(minWidth: 110)
                stepButton(symbol: "plus", delta: unit.step)
            }
            .frame(maxWidth: .infinity)

            Button(action: onLog) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(EntryKind.feed.color)
            .controlSize(.large)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(symbol: String, delta: Double) -> some View {
        Button {
            withAnimation(.snappy) {
                amount = min(max(amount + delta, 0), unit.maximum)
            }
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 48, height: 48)
                .background(EntryKind.feed.softColor, in: .circle)
                .foregroundStyle(EntryKind.feed.textColor)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(delta > 0 ? "More" : "Less")
        .sensoryFeedback(.selection, trigger: amount)
    }
}

/// Small selectable capsules for where the baby is sleeping.
private struct LocationChips: View {
    let options: [SleepLocation]
    @Binding var selection: SleepLocation?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.4)) { selection = option }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(.title3)
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(EntryKind.sleep.textColor))
                    .background(isSelected ? EntryKind.sleep.color : EntryKind.sleep.softColor,
                                in: .rect(cornerRadius: 18, style: .continuous))
                        .scaleEffect(isSelected ? 1.03 : 1)
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview("Feed") {
    QuickLogSheet(kind: .feed, baby: PreviewStore.firstBaby(in: PreviewStore.empty), onLogged: { _ in }, onMoreDetails: {})
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}

#Preview("Sleep") {
    QuickLogSheet(kind: .sleep, baby: PreviewStore.firstBaby(in: PreviewStore.empty), onLogged: { _ in }, onMoreDetails: {})
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}

#Preview("Sleep · Custom Time") {
    QuickLogSheet(kind: .sleep, baby: PreviewStore.firstBaby(in: PreviewStore.empty), startsWithCustomTime: true,
                  onLogged: { _ in }, onMoreDetails: {})
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}
