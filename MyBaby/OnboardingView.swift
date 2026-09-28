import CoreData
import SwiftUI

/// First-launch welcome: introduce the app, ask how many babies, then collect each one's details.
struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(SelectedBaby.storageKey, store: SelectedBaby.defaults) private var selectedBabyID = ""

    /// One baby being set up.
    private struct BabyDraft {
        var name = ""
        var hasBirthday = true
        var birthday = Date.now
        var gender: BabyGender = .both
    }

    enum Step: Hashable {
        case welcome
        case count
        case baby(Int)
    }

    @State private var step: Step
    @State private var babyCount = 1
    @State private var drafts: [BabyDraft] = [BabyDraft()]

    init(startingAt step: Step = .welcome) {
        _step = State(initialValue: step)
    }

    /// The welcome flow recolors live to the theme picked for the baby being set up.
    private var theme: AppTheme {
        if case .baby(let index) = step, drafts.indices.contains(index) {
            return drafts[index].gender.theme
        }
        return drafts.first?.gender.theme ?? .both
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: welcome
                        case .count: countPicker
                        case .baby(let index): details(for: index)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 520)
                    // Short steps sit in the middle of the screen; long ones still scroll.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }

            footer
        }
        .background { ThemedBackground() }
        .environment(\.appTheme, theme)
        .tint(theme.accent)
        .animation(.smooth, value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 28) {
            Image("WelcomeArt")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(.rect(cornerRadius: 56, style: .continuous))
                .shadow(color: theme.titleColors[0].opacity(0.25), radius: 24, y: 12)
                .accessibilityHidden(true)

            Text("Track feeds, sleep, diapers and health — all in one cozy place, shared with the people who help care for your baby.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
    }

    private var countPicker: some View {
        VStack(spacing: 28) {
            StepHeader(title: "How Many Babies?", subtitle: "Each baby gets their own log. You can add a sibling later, too.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(1...4, id: \.self) { count in
                    CountCard(count: count, title: Self.countTitle(count), isSelected: babyCount == count, accent: theme.accent) {
                        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { babyCount = count }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: babyCount)
        }
    }

    private func details(for index: Int) -> some View {
        VStack(spacing: 24) {
            StepHeader(
                title: babyCount == 1 ? "About Your Baby" : "Baby \(index + 1) of \(babyCount)",
                subtitle: "You can change these any time in Settings."
            )
            BabyDetailsFields(
                name: $drafts[index].name,
                hasBirthday: $drafts[index].hasBirthday,
                birthday: $drafts[index].birthday,
                gender: $drafts[index].gender
            )
        }
    }

    static func countTitle(_ count: Int) -> String {
        switch count {
        case 1: "One Baby"
        case 2: "Twins"
        case 3: "Triplets"
        default: "Quadruplets"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back", systemImage: "chevron.left", action: goBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }

            Button(action: advance) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 520)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .count: return "Next"
        case .baby(let index): return index + 1 < babyCount ? "Next Baby" : "Let's Go!"
        }
    }

    private func goBack() {
        switch step {
        case .welcome: break
        case .count: step = .welcome
        case .baby(0): step = .count
        case .baby(let index): step = .baby(index - 1)
        }
    }

    private func advance() {
        switch step {
        case .welcome:
            step = .count
        case .count:
            // Keep anything already typed; add or trim drafts to match the count.
            if drafts.count < babyCount {
                drafts += Array(repeating: BabyDraft(gender: drafts.first?.gender ?? .both), count: babyCount - drafts.count)
            } else {
                drafts = Array(drafts.prefix(babyCount))
            }
            step = .baby(0)
        case .baby(let index):
            if index + 1 < babyCount {
                step = .baby(index + 1)
            } else {
                finish()
            }
        }
    }

    private func finish() {
        var first: Baby?
        for draft in drafts {
            let baby = Baby(
                context: context,
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                birthday: draft.hasBirthday ? draft.birthday : nil,
                gender: draft.gender
            )
            if first == nil { first = baby }
        }
        try? context.save()
        selectedBabyID = first?.babyID?.uuidString ?? ""
        hasCompletedOnboarding = true
    }
}

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            FunTitle(title: title, alignment: .center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One square choice in the "How many babies?" grid.
private struct CountCard: View {
    let count: Int
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Babies in rows of two so every card has the same shape.
                VStack(spacing: 2) {
                    ForEach(0..<((count + 1) / 2), id: \.self) { row in
                        Text(String(repeating: "👶", count: min(2, count - row * 2)))
                    }
                }
                .font(.system(size: 30))
                .frame(height: 70)

                Text(title)
                    .font(.headline)
                    .fontDesign(.rounded)
                Text(count == 1 ? "1 baby" : "\(count) babies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.background, in: .rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isSelected ? accent : .clear, lineWidth: 2.5)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                    .symbolEffect(.bounce, value: isSelected)
                    .padding(12)
            }
            .shadow(color: isSelected ? accent.opacity(0.2) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("\(title), \(count == 1 ? "1 baby" : "\(count) babies")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A selectable theme card showing that theme's colors.
struct ThemeOptionCard: View {
    let option: BabyGender
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let theme = option.theme
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Swatch previewing the theme's background and title colors.
                ZStack {
                    Circle().fill(theme.backgroundGradient)
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(theme.titleGradient)
                }
                .frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.tertiary))
            }
            .padding()
            .background(.background, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview("Welcome") {
    OnboardingView()
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}

#Preview("How Many") {
    OnboardingView(startingAt: .count)
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}

#Preview("About Your Baby") {
    OnboardingView(startingAt: .baby(0))
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}
