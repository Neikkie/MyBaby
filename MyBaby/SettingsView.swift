import SwiftUI
import CoreData
import UserNotifications
import WidgetKit

struct SettingsView: View {
    @ObservedObject var baby: Baby

    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL
    @FetchRequest private var entries: FetchedResults<BabyEntry>
    @FetchRequest private var feeds: FetchedResults<BabyEntry>
    @FetchRequest private var measurements: FetchedResults<GrowthMeasurement>
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @AppStorage(SelectedBaby.storageKey, store: SelectedBaby.defaults) private var selectedBabyID = ""

    init(baby: Baby) {
        self.baby = baby
        _entries = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby))
        _feeds = FetchRequest(fetchRequest: BabyEntry.fetch(for: baby, kinds: [.feed], limit: 1))
        _measurements = FetchRequest(fetchRequest: GrowthMeasurement.fetch(for: baby))
    }

    private var birthdayInterval: Double { baby.birthdayInterval }
    @AppStorage(SettingsKey.temperatureUnit) private var temperatureUnit: TemperatureUnitPreference = .system
    @AppStorage(SettingsKey.volumeUnit) private var volumeUnit: VolumeUnitPreference = .system
    @AppStorage(SettingsKey.feedRemindersEnabled) private var remindersEnabled = false
    @AppStorage(SettingsKey.feedReminderMinutes) private var reminderMinutes = FeedReminderScheduler.defaultMinutes
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true

    @State private var isConfirmingDelete = false
    @State private var isConfirmingDeleteBaby = false
    @State private var notificationsDenied = false

    private var name: Binding<String> {
        Binding(get: { baby.name ?? "" }, set: { baby.name = $0; save() })
    }

    private var birthday: Binding<Date> {
        Binding(get: { baby.birthday ?? .now }, set: { baby.birthday = $0; save() })
    }

    private func save() {
        try? context.save()
    }

    private var ageDescription: String? {
        Self.ageDescription(birthdayInterval: birthdayInterval)
    }

    /// Baby's age such as "3 months, 5 days", or nil if no birthday is set.
    static func ageDescription(birthdayInterval: Double) -> String? {
        guard birthdayInterval != 0 else { return nil }
        let components = Calendar.current.dateComponents(
            [.year, .month, .weekOfMonth, .day],
            from: Date(timeIntervalSince1970: birthdayInterval),
            to: .now
        )
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: components)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("\(baby.displayName)'s Profile") {
                    TextField("Name", text: name)
                        .textContentType(.name)
                    DatePicker("Birthday", selection: birthday, in: ...Date.now, displayedComponents: .date)
                    if let ageDescription, let age = BabyAge(birthdayInterval: birthdayInterval) {
                        LabeledContent("Age", value: ageDescription)
                        LabeledContent("Age in Weeks", value: age.weeksDescription)
                    }
                }

                SharingSection(baby: baby)

                Section {
                    ForEach(BabyGender.allCases) { option in
                        ThemeOptionCard(option: option, isSelected: baby.gender == option) {
                            withAnimation {
                                baby.gender = option
                                save()
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("\(baby.displayName)'s Theme")
                }

                Section {
                    Toggle("Feed Reminders", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Remind After", selection: $reminderMinutes) {
                            ForEach(FeedReminderScheduler.intervalOptions, id: \.self) { minutes in
                                Text(FeedReminderScheduler.formatted(minutes: minutes)).tag(minutes)
                            }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if notificationsDenied {
                        Button("Notifications are turned off for My Baby. Open Settings to allow them.") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(.footnote)
                    } else {
                        Text("Get a notification when it's been a while since the last feed.")
                    }
                }

                Section("Units") {
                    Picker("Temperature", selection: $temperatureUnit) {
                        ForEach(TemperatureUnitPreference.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Bottle Amounts", selection: $volumeUnit) {
                        ForEach(VolumeUnitPreference.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    LabeledContent("Logged Entries", value: "\(entries.count)")
                    LabeledContent("Growth Measurements", value: "\(measurements.count)")
                    Button("Delete Logged Data", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .disabled(entries.isEmpty && measurements.isEmpty)
                    Button(isShared ? "Remove \(baby.displayName)" : "Delete \(baby.displayName)",
                           systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                        isConfirmingDeleteBaby = true
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text(dataFooter)
                }

                Section {
                    Label {
                        Text("My Baby helps you keep a record. It doesn't provide medical advice, diagnosis or treatment. Always contact your pediatrician or emergency services if you're worried about your baby's health.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "stethoscope")
                            .foregroundStyle(EntryKind.health.textColor)
                    }
                } header: {
                    Text("Medical Disclaimer")
                }

                SupportAndLegalSection()

                Section {
                    Button("Show Welcome Screen Again") {
                        hasCompletedOnboarding = false
                    }
                }
            }
            .themedBackground()
            .funNavigationTitle("Settings")
            .confirmationDialog(
                deleteDataMessage,
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Logged Data", role: .destructive) {
                    // Stop any running timers first so their Live Activities don't linger.
                    for entry in entries where entry.isInProgress {
                        BabyActivityController.end(entryID: entry.entryID)
                    }
                    entries.forEach(context.delete)
                    measurements.forEach(context.delete)
                    save()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            .confirmationDialog(
                deleteBabyMessage,
                isPresented: $isConfirmingDeleteBaby,
                titleVisibility: .visible
            ) {
                Button(isShared ? "Remove \(baby.displayName)" : "Delete \(baby.displayName)", role: .destructive) {
                    Task { await deleteBaby() }
                }
            }
            .onChange(of: remindersEnabled) { _, enabled in
                Task {
                    if enabled {
                        let granted = await FeedReminderScheduler.requestAuthorization()
                        notificationsDenied = !granted
                        if !granted { remindersEnabled = false }
                    }
                    await FeedReminderScheduler.reschedule(lastFeed: feeds.first?.timestamp, babyName: baby.name ?? "")
                }
            }
            .onChange(of: reminderMinutes) {
                Task { await FeedReminderScheduler.reschedule(lastFeed: feeds.first?.timestamp, babyName: baby.name ?? "") }
            }
        }
    }
}

extension SettingsView {
    /// True when someone else shared this baby with you.
    private var isShared: Bool { PersistenceController.shared.isFromSomeoneElse(baby) }

    private var dataFooter: String {
        if isShared {
            return String(localized: "Removing \(baby.displayName) takes them off your devices only. The person who shared \(baby.displayName) keeps the log.")
        }
        return String(localized: "Your data syncs privately through your iCloud account. Deleting \(baby.displayName) removes their profile and everything logged, on all your devices and for anyone you share with.")
    }

    private var deleteDataMessage: String {
        let isOnShare = isShared || PersistenceController.shared.existingShare(for: baby) != nil
        return isOnShare
            ? String(localized: "Delete all of \(baby.displayName)'s feeds, sleep, diapers, health notes and growth measurements for everyone on the share? \(baby.displayName)'s profile stays. This can't be undone.")
            : String(localized: "Delete all of \(baby.displayName)'s feeds, sleep, diapers, health notes and growth measurements? \(baby.displayName)'s profile stays. This can't be undone.")
    }

    private var deleteBabyMessage: String {
        if isShared {
            return String(localized: "Remove \(baby.displayName) from your devices? You'll need a new invitation to see their log again.")
        }
        let isSharedWithOthers = PersistenceController.shared.existingShare(for: baby) != nil
        return isSharedWithOthers
            ? String(localized: "Delete \(baby.displayName) and everything logged for them? Everyone you share with will lose access too. This can't be undone.")
            : String(localized: "Delete \(baby.displayName) and everything logged for them? This can't be undone.")
    }

    private func deleteBaby() async {
        // Switch to another baby first so no screen is left showing a deleted one.
        let next = babies.first { $0.objectID != baby.objectID }
        for entry in entries where entry.isInProgress {
            BabyActivityController.end(entryID: entry.entryID)
        }
        ScheduleReminders.removeAll(for: baby)
        let deleted = baby
        withAnimation { selectedBabyID = next?.babyID?.uuidString ?? "" }
        await PersistenceController.shared.delete(deleted)
        WidgetCenter.shared.reloadAllTimelines()
        // With no babies left, the welcome screen appears to add one.
    }
}

#Preview {
    SettingsView(baby: PreviewStore.firstBaby(in: PreviewStore.empty))
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}
