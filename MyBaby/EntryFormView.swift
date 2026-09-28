import SwiftUI
import CoreData

/// Sheet for adding a new entry or editing an existing one.
struct EntryFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The entry being edited, or nil when creating a new one.
    let entry: BabyEntry?
    /// Who the entry is for.
    let baby: Baby?

    @State private var kind: EntryKind
    @State private var timestamp: Date
    @State private var hasEndTime: Bool
    @State private var endTime: Date
    @State private var feedType: FeedType
    /// Bottle amount in the unit chosen in Settings (ml or oz).
    @State private var amount: Double
    @State private var diaperType: DiaperType
    @State private var sleepLocation: SleepLocation?
    @State private var symptom: Symptom
    @State private var severity: Severity
    @State private var hasTemperature: Bool
    /// Temperature in the unit currently selected by `useFahrenheit`.
    @State private var temperature: Double
    @State private var useFahrenheit: Bool
    @State private var notes: String

    /// Log something new for a baby.
    init(kind: EntryKind, baby: Baby) {
        self.init(kind: kind, entry: nil, baby: baby)
    }

    /// Edit an existing entry.
    init(entry: BabyEntry) {
        self.init(kind: entry.kind, entry: entry, baby: entry.baby)
    }

    private init(kind: EntryKind, entry: BabyEntry?, baby: Baby?) {
        self.entry = entry
        self.baby = baby
        let months = BabyAge(birthdayInterval: baby?.birthdayInterval ?? 0)?.months
        let isNewSleep = entry == nil && kind == .sleep
        // New sleeps default to "went to sleep an hour ago, woke up now" so both times are easy to adjust.
        let start = entry?.timestamp ?? (isNewSleep ? Date.now.addingTimeInterval(-3600) : .now)
        _kind = State(initialValue: entry?.kind ?? kind)
        _timestamp = State(initialValue: start)
        _hasEndTime = State(initialValue: entry?.endTime != nil || isNewSleep)
        _endTime = State(initialValue: entry?.endTime ?? max(start, .now))
        _feedType = State(initialValue: entry?.feedType
            ?? FeedType.available(forMonths: months).first
            ?? .solids)
        let volumeUnit = VolumeUnitPreference.current
        _amount = State(initialValue: volumeUnit.toDisplay(milliliters: entry?.amountML ?? 90))
        _diaperType = State(initialValue: entry?.diaperType ?? .wet)
        _sleepLocation = State(initialValue: entry?.sleepLocation)
        _symptom = State(initialValue: entry?.symptom ?? .fever)
        _severity = State(initialValue: entry?.severity ?? .mild)

        let fahrenheit = TemperatureUnitPreference.current.usesFahrenheit
        let celsius = entry?.temperatureC ?? 37.0
        _useFahrenheit = State(initialValue: fahrenheit)
        _temperature = State(initialValue: fahrenheit ? Self.toFahrenheit(celsius) : celsius)
        _hasTemperature = State(initialValue: entry?.temperatureC != nil || (entry == nil && kind == .health))
        _notes = State(initialValue: entry?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(EntryKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch kind {
                case .feed:
                    feedSection
                case .sleep:
                    sleepSection
                case .diaper:
                    diaperSection
                case .health:
                    healthSection
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(entry == nil ? "New \(kind.title)" : "Edit \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: kind) { _, newKind in
                // When switching a new entry to Sleep, ask for a wake-up time by default.
                if entry == nil && newKind == .sleep {
                    hasEndTime = true
                }
            }
            .toolbar {
                // Standard roles render as the system Liquid Glass cancel (✕) and confirm (✓) buttons.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(hasInvalidEndTime)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var feedSection: some View {
        Section("Feed") {
            Picker("Method", selection: $feedType) {
                ForEach(feedTypeOptions) { Text($0.title).tag($0) }
            }
            DatePicker("Started", selection: $timestamp)
            if feedType.hasAmount {
                let unit = VolumeUnitPreference.current
                Stepper(value: $amount, in: 0...unit.maximum, step: unit.step) {
                    LabeledContent("Amount", value: unit.format(milliliters: unit.toMilliliters(amount)))
                }
            }
            if feedType.isBreast {
                Toggle(entry?.isOngoingFeed == true ? "Stop timer" : "Record end time", isOn: $hasEndTime)
                if hasEndTime {
                    DatePicker("Ended", selection: $endTime, in: timestamp...)
                }
            }
        }
    }

    private var age: BabyAge? {
        BabyAge(birthdayInterval: baby?.birthdayInterval ?? 0)
    }

    /// Feed types for the baby's age, keeping the entry's own type when editing an older one.
    private var feedTypeOptions: [FeedType] {
        var options = FeedType.available(forMonths: age?.months)
        if !options.contains(feedType) { options.insert(feedType, at: 0) }
        return options
    }

    private var sleepLocationOptions: [SleepLocation] {
        var options = SleepLocation.available(forMonths: age?.months)
        if let sleepLocation, !options.contains(sleepLocation) { options.insert(sleepLocation, at: 0) }
        return options
    }

    /// True when an end time is required but set before the start time.
    private var hasInvalidEndTime: Bool {
        let usesEndTime = kind == .sleep || (kind == .feed && feedType.isBreast)
        return usesEndTime && hasEndTime && endTime < timestamp
    }

    private var sleepSection: some View {
        Section {
            DatePicker("Went to sleep", selection: $timestamp)
            Picker("Where", selection: $sleepLocation) {
                Text("Not set").tag(SleepLocation?.none)
                ForEach(sleepLocationOptions) { Text($0.title).tag(SleepLocation?.some($0)) }
            }
            Toggle("Still sleeping", isOn: Binding(
                get: { !hasEndTime },
                set: { hasEndTime = !$0 }
            ))
            if hasEndTime {
                DatePicker("Woke up", selection: $endTime)
            }

            // Live duration so parents can see the total as they adjust the times.
            if hasEndTime {
                LabeledContent("Sleep duration") {
                    Text(endTime >= timestamp ? BabyEntry.format(endTime.timeIntervalSince(timestamp)) : "—")
                        .font(.headline)
                        .foregroundStyle(EntryKind.sleep.textColor)
                }
            } else {
                LabeledContent("Sleeping for") {
                    Text(timestamp, style: .timer)
                        .monospacedDigit()
                        .font(.headline)
                        .foregroundStyle(EntryKind.sleep.textColor)
                }
            }
        } header: {
            Text("Sleep")
        } footer: {
            if hasInvalidEndTime {
                Text("Wake-up time must be after the time the baby went to sleep.")
                    .foregroundStyle(EntryKind.health.textColor)
            } else if !hasEndTime {
                Text("Turn off \"Still sleeping\" to enter the wake-up time, or tap Wake Up on the Today screen later.")
            }
        }
    }

    private var diaperSection: some View {
        Section("Diaper") {
            Picker("Contents", selection: $diaperType) {
                ForEach(DiaperType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker("Time", selection: $timestamp)
        }
    }

    private var healthSection: some View {
        Section {
            Picker("Symptom", selection: $symptom) {
                ForEach(Symptom.allCases) { symptom in
                    Label(symptom.title, systemImage: symptom.symbol).tag(symptom)
                }
            }
            Picker("Severity", selection: $severity) {
                ForEach(Severity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker("Time", selection: $timestamp)

            Toggle("Record temperature", isOn: $hasTemperature)
            if hasTemperature {
                HStack {
                    TextField("Temperature", value: $temperature, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $useFahrenheit) {
                        Text("°C").tag(false)
                        Text("°F").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                // Convert the entered value when switching units so it stays the same temperature.
                .onChange(of: useFahrenheit) { _, isFahrenheit in
                    temperature = isFahrenheit ? Self.toFahrenheit(temperature) : Self.toCelsius(temperature)
                }
            }
        } header: {
            Text("Health")
        } footer: {
            if hasTemperature && temperatureInCelsius >= 38.0 {
                Label("That's a fever. For babies under 3 months, contact your doctor right away.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(EntryKind.health.textColor)
            }
        }
    }

    private var temperatureInCelsius: Double {
        useFahrenheit ? Self.toCelsius(temperature) : temperature
    }

    private static func toFahrenheit(_ celsius: Double) -> Double {
        (celsius * 9 / 5 + 32).rounded(toPlaces: 1)
    }

    private static func toCelsius(_ fahrenheit: Double) -> Double {
        ((fahrenheit - 32) * 5 / 9).rounded(toPlaces: 1)
    }

    private func save() {
        let target = entry ?? BabyEntry(context: context, baby: baby, kind: kind)
        target.kind = kind
        target.timestamp = timestamp
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clear fields that don't apply to the chosen kind.
        target.feedType = nil
        target.amountML = nil
        target.diaperType = nil
        target.sleepLocation = nil
        target.symptom = nil
        target.severity = nil
        target.temperatureC = nil
        target.endTime = nil

        // A running breastfeeding timer keeps running unless it's given an end time.
        let keepsTimerRunning = kind == .feed && feedType.isBreast && !hasEndTime && target.isTimerRunning
        target.isTimerRunning = keepsTimerRunning

        switch kind {
        case .feed:
            target.feedType = feedType
            if feedType.hasAmount { target.amountML = VolumeUnitPreference.current.toMilliliters(amount) }
            if feedType.isBreast && hasEndTime {
                target.endTime = endTime
            }
        case .sleep:
            target.endTime = hasEndTime ? endTime : nil
            target.sleepLocation = sleepLocation
        case .diaper:
            target.diaperType = diaperType
        case .health:
            target.symptom = symptom
            target.severity = severity
            if hasTemperature { target.temperatureC = temperatureInCelsius }
        }

        try? context.save()

        dismiss()
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

#Preview {
    EntryFormView(kind: .feed, baby: PreviewStore.firstBaby(in: PreviewStore.empty))
        .environment(\.managedObjectContext, PreviewStore.empty.viewContext)
}
