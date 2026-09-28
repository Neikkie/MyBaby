import SwiftUI

// MARK: - Age

/// The baby's age, derived from the birthday saved in Settings.
struct BabyAge {
    let birthday: Date
    var now: Date = .now

    init?(birthdayInterval: Double, now: Date = .now) {
        guard birthdayInterval != 0 else { return nil }
        self.birthday = Date(timeIntervalSince1970: birthdayInterval)
        self.now = now
    }

    var days: Int {
        max(Calendar.current.dateComponents([.day], from: birthday, to: now).day ?? 0, 0)
    }

    var weeks: Int { days / 7 }

    /// Whole calendar months, used to match milestone checkpoints.
    var months: Int {
        max(Calendar.current.dateComponents([.month], from: birthday, to: now).month ?? 0, 0)
    }

    /// "5 days old" for the first week, then "10 weeks old".
    var weeksDescription: String {
        if weeks == 0 {
            return days == 1 ? "1 day old" : "\(days) days old"
        }
        return weeks == 1 ? "1 week old" : "\(weeks) weeks old"
    }

    /// Baby for the first year, toddler until 3, then child.
    var stageName: String {
        switch months {
        case ..<12: "Baby"
        case ..<36: "Toddler"
        default: "Child"
        }
    }

    /// A friendly picture for the stage, matching the theme picked for them.
    func stagePicture(for gender: BabyGender) -> String {
        switch months {
        case ..<12: return "👶"
        case ..<36: return "🧒"
        default:
            switch gender {
            case .girl: return "👧"
            case .boy: return "👦"
            case .both: return "🧒"
            }
        }
    }

    /// "2 months, 1 week" style description.
    var monthsDescription: String {
        let components = Calendar.current.dateComponents([.year, .month, .weekOfMonth, .day], from: birthday, to: now)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: components) ?? ""
    }
}

// MARK: - Milestones

/// A group of milestones most children reach by a given age.
struct MilestoneStage: Identifiable {
    enum Area: String, CaseIterable {
        case social = "Social & Emotional"
        case language = "Language & Communication"
        case cognitive = "Learning & Thinking"
        case movement = "Movement & Physical"

        var symbol: String {
            switch self {
            case .social: "heart.fill"
            case .language: "bubble.left.and.bubble.right.fill"
            case .cognitive: "lightbulb.fill"
            case .movement: "figure.child"
            }
        }
    }

    let months: Int
    let items: [(area: Area, text: String)]

    var id: Int { months }

    var title: String {
        months % 12 == 0 && months >= 24 ? "By \(months / 12) years" : "By \(months) months"
    }

    func items(in area: Area) -> [String] {
        items.filter { $0.area == area }.map(\.text)
    }

    /// Adapted from the CDC's "Learn the Signs. Act Early." milestone checklists (2022),
    /// which list what most children (75% or more) can do by each age.
    static let all: [MilestoneStage] = [
        MilestoneStage(months: 2, items: [
            (.social, "Calms down when spoken to or picked up"),
            (.social, "Looks at your face"),
            (.social, "Seems happy to see you when you walk up"),
            (.social, "Smiles when you talk to or smile at them"),
            (.language, "Makes sounds other than crying"),
            (.language, "Reacts to loud sounds"),
            (.cognitive, "Watches you as you move"),
            (.cognitive, "Looks at a toy for several seconds"),
            (.movement, "Holds head up when on tummy"),
            (.movement, "Moves both arms and both legs"),
            (.movement, "Opens hands briefly"),
        ]),
        MilestoneStage(months: 4, items: [
            (.social, "Smiles on their own to get your attention"),
            (.social, "Chuckles when you try to make them laugh"),
            (.social, "Looks at you, moves or makes sounds to get or keep your attention"),
            (.language, "Makes cooing sounds like \"oooo\" and \"aahh\""),
            (.language, "Makes sounds back when you talk"),
            (.language, "Turns head toward the sound of your voice"),
            (.cognitive, "Opens mouth when they see breast or bottle, if hungry"),
            (.cognitive, "Looks at their hands with interest"),
            (.movement, "Holds head steady without support when held"),
            (.movement, "Holds a toy when you put it in their hand"),
            (.movement, "Uses an arm to swing at toys"),
            (.movement, "Brings hands to mouth"),
            (.movement, "Pushes up onto elbows or forearms when on tummy"),
        ]),
        MilestoneStage(months: 6, items: [
            (.social, "Knows familiar people"),
            (.social, "Likes to look at themselves in a mirror"),
            (.social, "Laughs"),
            (.language, "Takes turns making sounds with you"),
            (.language, "Blows \"raspberries\""),
            (.language, "Makes squealing noises"),
            (.cognitive, "Puts things in their mouth to explore them"),
            (.cognitive, "Reaches to grab a toy they want"),
            (.cognitive, "Closes lips to show they don't want more food"),
            (.movement, "Rolls from tummy to back"),
            (.movement, "Pushes up with straight arms when on tummy"),
            (.movement, "Leans on hands to support themselves when sitting"),
        ]),
        MilestoneStage(months: 9, items: [
            (.social, "Is shy, clingy or fearful around strangers"),
            (.social, "Shows several facial expressions, like happy, sad, angry and surprised"),
            (.social, "Looks when you call their name"),
            (.social, "Reacts when you leave (looks, reaches for you or cries)"),
            (.social, "Smiles or laughs when you play peek-a-boo"),
            (.language, "Makes different sounds like \"mamamama\" and \"babababa\""),
            (.language, "Lifts arms up to be picked up"),
            (.cognitive, "Looks for objects when dropped out of sight"),
            (.cognitive, "Bangs two things together"),
            (.movement, "Gets to a sitting position by themselves"),
            (.movement, "Moves things from one hand to the other"),
            (.movement, "Uses fingers to \"rake\" food toward themselves"),
            (.movement, "Sits without support"),
        ]),
        MilestoneStage(months: 12, items: [
            (.social, "Plays games with you, like pat-a-cake"),
            (.language, "Waves \"bye-bye\""),
            (.language, "Calls a parent \"mama\", \"dada\" or another special name"),
            (.language, "Understands \"no\" (pauses or stops when you say it)"),
            (.cognitive, "Puts something in a container, like a block in a cup"),
            (.cognitive, "Looks for things they see you hide"),
            (.movement, "Pulls up to stand"),
            (.movement, "Walks while holding on to furniture"),
            (.movement, "Drinks from a cup without a lid while you hold it"),
            (.movement, "Picks things up between thumb and pointer finger"),
        ]),
        MilestoneStage(months: 15, items: [
            (.social, "Copies other children while playing"),
            (.social, "Shows you an object they like"),
            (.social, "Claps when excited"),
            (.social, "Hugs a stuffed toy or doll"),
            (.social, "Shows you affection with hugs, cuddles or kisses"),
            (.language, "Tries to say one or two words besides \"mama\" or \"dada\""),
            (.language, "Looks at a familiar object when you name it"),
            (.language, "Follows directions given with a gesture and words"),
            (.language, "Points to ask for something or to get help"),
            (.cognitive, "Tries to use things the right way, like a phone, cup or book"),
            (.cognitive, "Stacks at least two small objects, like blocks"),
            (.movement, "Takes a few steps on their own"),
            (.movement, "Uses fingers to feed themselves some food"),
        ]),
        MilestoneStage(months: 18, items: [
            (.social, "Moves away from you but looks to make sure you're close by"),
            (.social, "Points to show you something interesting"),
            (.social, "Puts hands out for you to wash them"),
            (.social, "Looks at a few pages in a book with you"),
            (.social, "Helps you dress them by pushing an arm through a sleeve"),
            (.language, "Tries to say three or more words besides \"mama\" or \"dada\""),
            (.language, "Follows one-step directions without gestures"),
            (.cognitive, "Copies you doing chores, like sweeping"),
            (.cognitive, "Plays with toys in a simple way, like pushing a toy car"),
            (.movement, "Walks without holding on"),
            (.movement, "Scribbles"),
            (.movement, "Drinks from a cup without a lid (may spill)"),
            (.movement, "Feeds themselves with fingers"),
            (.movement, "Tries to use a spoon"),
            (.movement, "Climbs on and off a couch or chair without help"),
        ]),
        MilestoneStage(months: 24, items: [
            (.social, "Notices when others are hurt or upset"),
            (.social, "Looks at your face to see how to react in a new situation"),
            (.language, "Points to things in a book when you ask"),
            (.language, "Says at least two words together, like \"more milk\""),
            (.language, "Points to at least two body parts when you ask"),
            (.language, "Uses more gestures than waving and pointing, like blowing a kiss"),
            (.cognitive, "Holds something in one hand while using the other"),
            (.cognitive, "Tries to use switches, knobs or buttons on a toy"),
            (.cognitive, "Plays with more than one toy at the same time"),
            (.movement, "Kicks a ball"),
            (.movement, "Runs"),
            (.movement, "Walks up a few stairs with or without help"),
            (.movement, "Eats with a spoon"),
        ]),
    ]

    /// The next checkpoint the baby hasn't reached yet (or the last one for older toddlers).
    static func upcoming(for age: BabyAge) -> MilestoneStage {
        all.first { age.months < $0.months } ?? all[all.count - 1]
    }

    /// The date the baby reaches this checkpoint's age.
    func date(for age: BabyAge) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: age.birthday) ?? age.birthday
    }
}

// MARK: - Views

/// All milestone checkpoints in order, opening scrolled to the one coming up next.
struct MilestonesView: View {
    let age: BabyAge

    var body: some View {
        let upcoming = MilestoneStage.upcoming(for: age)

        ScrollViewReader { proxy in
            List {
                Section {
                    Text("Every baby develops at their own pace. These are things most children can do by each age. If you have concerns, talk to your pediatrician — you don't need to wait for a checkup.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(MilestoneStage.all) { stage in
                    Section {
                        ForEach(MilestoneStage.Area.allCases, id: \.self) { area in
                            let items = stage.items(in: area)
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(area.rawValue, systemImage: area.symbol)
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(items, id: \.self) { item in
                                        Text("• \(item)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    } header: {
                        HStack {
                            Text(stage.title)
                            if stage.id == upcoming.id {
                                Text("Up Next")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(EntryKind.sleep.color, in: .capsule)
                            } else if stage.months <= age.months {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Age reached")
                            }
                        }
                    }
                    .id(stage.id)
                }

                Section {
                    Text("Adapted from the CDC's \"Learn the Signs. Act Early.\" milestone checklists.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { proxy.scrollTo(upcoming.id, anchor: .top) }
        }
        .themedBackground()
        .funNavigationTitle("Milestones")
        .navigationSubtitle(age.weeksDescription)
    }
}

#Preview("Milestones") {
    NavigationStack {
        MilestonesView(age: BabyAge(birthdayInterval: Date.now.addingTimeInterval(-10 * 7 * 86_400).timeIntervalSince1970)!)
    }
}
