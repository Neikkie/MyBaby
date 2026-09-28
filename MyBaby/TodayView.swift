import SwiftUI
import CoreData

// MARK: - Today

/// The home screen. Starts with just three friendly tiles; more appears only once there's
/// something to show, so a new parent isn't overwhelmed.
struct TodayView: View {
    @ObservedObject var baby: Baby
    @Environment(TabRouter.self) private var router
    @FetchRequest private var fetchedEntries: FetchedResults<BabyEntry>

    init(baby: Baby) {
        self.baby = baby
        _fetchedEntries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby))
    }

    private var entries: [BabyEntry] { Array(fetchedEntries) }
    private var age: BabyAge? { BabyAge(birthdayInterval: baby.birthdayInterval) }

    @State private var loggingKind: EntryKind?
    @State private var formKind: EntryKind?
    @State private var confirmation: LogConfirmation?
    /// Bumped per kind after logging, to bounce that tile's symbol.
    @State private var bounce: [EntryKind: Int] = [:]

    private static let trackedKinds: [EntryKind] = [.feed, .sleep, .diaper]

    private var trackedEntries: [BabyEntry] {
        entries.filter { Self.trackedKinds.contains($0.kind) }
    }

    private var hasEntries: Bool { !trackedEntries.isEmpty }

    private var todaysEntries: [BabyEntry] {
        trackedEntries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TodayHeader(baby: baby, age: age)

                    TileRow(entries: entries, age: age, bounce: bounce, isExpanded: !hasEntries) { kind in
                        loggingKind = kind
                    }

                    // Once something is logged: one gentle suggestion and a slim milestone row. That's it.
                    if hasEntries {
                        WhatsNextCard(
                            baby: baby,
                            entries: entries,
                            todaysEntries: todaysEntries,
                            onTap: { kind in loggingKind = kind },
                            onOpenHistory: { router.open(.history) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                        if let age {
                            DevelopmentRow(age: age)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
                .animation(.spring(duration: 0.5, bounce: 0.25), value: hasEntries)
            }
            .background { ThemedBackground() }
            // Today draws its own, larger header; the title still names the screen for VoiceOver and Back buttons.
            .navigationTitle(baby.displayName)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if let confirmation {
                    LoggedToast(confirmation: confirmation) {
                        confirmation.undo()
                        withAnimation(.spring) { self.confirmation = nil }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(confirmation.id)
                }
            }
            .task(id: confirmation?.id) {
                // The confirmation fades away on its own after a few seconds.
                guard confirmation != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.spring) { confirmation = nil }
            }
            .sheet(item: $loggingKind) { kind in
                QuickLogSheet(
                    kind: kind,
                    baby: baby,
                    onLogged: { result in
                        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                            confirmation = result
                        }
                        bounce[kind, default: 0] += 1
                    },
                    onMoreDetails: {
                        loggingKind = nil
                        // Let the quick sheet finish closing before opening the full form.
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            formKind = kind
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $formKind) { kind in
                EntryFormView(kind: kind, baby: baby)
            }
        }
    }
}

// MARK: - Header

/// Big, friendly greeting: the baby's name (or the wordmark), today's date and their age.
/// Tapping the name switches between babies or adds another.
private struct TodayHeader: View {
    @ObservedObject var baby: Baby
    let age: BabyAge?

    @Environment(\.appTheme) private var theme
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @AppStorage(SelectedBaby.storageKey, store: SelectedBaby.defaults) private var selectedBabyID = ""
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 46
    @State private var isAddingBaby = false

    private var name: String { (baby.name ?? "").trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(babies) { other in
                    Button {
                        withAnimation(.spring) { selectedBabyID = other.babyID?.uuidString ?? "" }
                    } label: {
                        if other == baby {
                            Label(other.displayName, systemImage: "checkmark")
                        } else {
                            Text(other.displayName)
                        }
                    }
                }
                Divider()
                Button("Add Baby", systemImage: "plus") { isAddingBaby = true }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    FunTitle(
                        title: name.isEmpty ? "My Baby" : name,
                        isWordmark: name.isEmpty,
                        font: .system(size: nameSize, weight: .black, design: .rounded),
                        heartFont: .title2
                    )
                    .fixedSize()
                    if babies.count > 1 {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(babies.count > 1 ? "Switch babies or add another" : "Add another baby")
            .padding(.top, 12)

            HStack(spacing: 10) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let age {
                    // A little picture for their stage: baby, toddler or child.
                    Text("\(age.stagePicture(for: baby.gender)) \(age.weeksDescription)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.accent.opacity(0.14), in: .capsule)
                        .accessibilityLabel("\(age.stageName), \(age.weeksDescription)")
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isAddingBaby) {
            AddBabySheet()
        }
    }
}

// MARK: - Tiles

/// The three pastel tiles, styled after the app icon. With nothing logged they fill the
/// screen as big, friendly invitations; after the first log they spring into a compact row.
private struct TileRow: View {
    let entries: [BabyEntry]
    let age: BabyAge?
    let bounce: [EntryKind: Int]
    let isExpanded: Bool
    let onTap: (EntryKind) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var namespace

    private static let kinds: [EntryKind] = [.feed, .sleep, .diaper]

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 14) {
                    ForEach(Self.kinds) { kind in
                        tile(kind, age: age, style: .large)
                    }
                }
                // Fill the visible screen below the title, leaving room for the tab bar.
                .containerRelativeFrame(.vertical) { height, _ in max(height - 150, 420) }
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 12))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ForEach(Self.kinds) { kind in
                        tile(kind, age: age, style: .compact)
                    }
                }
            }
        }
    }

    private func tile(_ kind: EntryKind, age: BabyAge?, style: ActivityTile.Style) -> some View {
        ActivityTile(
            kind: kind,
            stage: TileStage.forKind(kind, age: age),
            entries: entries,
            bounceTrigger: bounce[kind, default: 0],
            style: style,
            action: { onTap(kind) }
        )
        .matchedGeometryEffect(id: kind, in: namespace)
    }
}

private struct ActivityTile: View {
    enum Style { case large, compact }

    let kind: EntryKind
    let stage: TileStage
    let entries: [BabyEntry]
    let bounceTrigger: Int
    let style: Style
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapCount = 0

    private var latest: BabyEntry? { entries.first { $0.kind == kind } }
    private var running: BabyEntry? { entries.first { $0.kind == kind && $0.isInProgress } }
    private var isLarge: Bool { style == .large }

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Group {
                if isLarge {
                    largeContent
                } else if dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 16) { artwork; labels }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) { artwork; labels }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, isLarge ? 20 : 18)
            .padding(.horizontal, isLarge ? 24 : 10)
            .frame(maxHeight: isLarge ? .infinity : nil)
            .background(kind.softColor, in: .rect(cornerRadius: isLarge ? 36 : 28, style: .continuous))
            .overlay {
                // A soft breathing ring while a timer is running.
                if running != nil {
                    RoundedRectangle(cornerRadius: isLarge ? 36 : 28, style: .continuous)
                        .strokeBorder(kind.textColor.opacity(0.6), lineWidth: 2)
                        .phaseAnimator([false, true]) { ring, glowing in
                            ring.opacity(reduceMotion ? 1 : (glowing ? 1 : 0.35))
                        } animation: { _ in .easeInOut(duration: 1.2) }
                }
            }
            .shadow(color: kind.textColor.opacity(0.18), radius: 12, y: 6)
        }
        .buttonStyle(SquishButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .accessibilityLabel(stage.label)
        .accessibilityValue(accessibilityStatus)
        .accessibilityHint("Opens quick options to log a \(stage.label.lowercased())")
    }

    /// Big invitation used before anything is logged: artwork on the left, words on the right.
    private var largeContent: some View {
        HStack(spacing: 20) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.label)
                    .font(.title.bold())
                    .fontDesign(.rounded)
                Text(stage.caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kind.textColor)
                Text("Tap to log")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.title)
                .foregroundStyle(kind.textColor)
                .symbolEffect(.breathe, isActive: !reduceMotion)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artwork: some View {
        let hops = !reduceMotion
        return TileArtwork(art: stage.symbol, kind: kind, size: isLarge ? 72 : 38)
            // A happy hop when something is logged or the tile is tapped.
            .keyframeAnimator(initialValue: 1.0, trigger: bounceTrigger + tapCount) { view, scale in
                view.scaleEffect(hops ? scale : 1)
            } keyframes: { _ in
                SpringKeyframe(1.18, duration: 0.18)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            }
    }

    private var labels: some View {
        VStack(spacing: 2) {
            Text(stage.label)
                .font(.headline)
                .fontDesign(.rounded)
            status
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let running {
            if kind == .feed, let side = running.feedType?.sideTitle {
                Text("\(side) · \(running.timestamp, style: .timer)").monospacedDigit()
            } else {
                Text("Asleep · \(running.timestamp, style: .timer)").monospacedDigit()
            }
        } else if let latest {
            TimelineView(.everyMinute) { context in
                Text(Self.ago(latest.endTime ?? latest.timestamp, now: context.date))
            }
        } else {
            Text("Tap to log")
        }
    }

    private var accessibilityStatus: String {
        if running != nil { return kind == .sleep ? "Asleep now" : "Feeding now" }
        if let latest { return "Last logged \(Self.ago(latest.endTime ?? latest.timestamp, now: .now))" }
        return "\(stage.caption). Nothing logged yet"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        return interval < 60 ? "Just now" : "\(BabyEntry.format(interval)) ago"
    }
}

/// Gently shrinks on press and springs back, so taps feel alive.
struct SquishButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: configuration.isPressed)
    }
}

// MARK: - Cards

/// A rounded card on the themed background.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

private struct CardHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontDesign(.rounded)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// A slim row: age in weeks and a link to the milestones coming up.
private struct DevelopmentRow: View {
    let age: BabyAge

    @Environment(\.appTheme) private var theme

    var body: some View {
        let stage = MilestoneStage.upcoming(for: age)
        NavigationLink {
            MilestonesView(age: age)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.gradient, in: .rect(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Week \(age.weeks) milestones")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("See what's coming up \(stage.title.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background.opacity(0.7), in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Confirmation

/// What was just logged, with a way to take it back.
struct LogConfirmation: Identifiable, Equatable {
    let id = UUID()
    let kind: EntryKind
    let message: String
    let undo: () -> Void

    static func == (lhs: LogConfirmation, rhs: LogConfirmation) -> Bool { lhs.id == rhs.id }
}

private struct LoggedToast: View {
    let confirmation: LogConfirmation
    let onUndo: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(confirmation.kind.textColor)
                .symbolEffect(.bounce, value: appeared)
            Text(confirmation.message)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", onUndo)
        .onAppear {
            AccessibilityNotification.Announcement(confirmation.message).post()
        }
    }
}

// MARK: - Tabs

enum AppTab: Hashable {
    case today, health, history, settings
}

/// Shared tab selection, so screens can jump to another tab (e.g. "See All" on Today).
@Observable
final class TabRouter {
    var selected: AppTab = .today

    func open(_ tab: AppTab) {
        withAnimation { selected = tab }
    }
}
