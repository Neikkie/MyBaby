import Foundation

/// Keys for values stored in UserDefaults via @AppStorage.
nonisolated enum SettingsKey {
    static let babyName = "babyName"
    /// Birthday as seconds since 1970; 0 means not set.
    static let babyBirthday = "babyBirthday"
    static let temperatureUnit = "temperatureUnit"
    static let volumeUnit = "volumeUnit"
    static let feedRemindersEnabled = "feedRemindersEnabled"
    /// Minutes after the last feed to send a reminder.
    static let feedReminderMinutes = "feedReminderMinutes"
    /// "girl", "boy" or "both"; picks the app's color theme.
    static let babyGender = "babyGender"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
}

nonisolated enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
    case system
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automatic"
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }

    /// Whether temperatures should be entered and shown in °F.
    var usesFahrenheit: Bool {
        switch self {
        case .system: Locale.current.measurementSystem == .us
        case .celsius: false
        case .fahrenheit: true
        }
    }

    /// The preference currently saved in settings.
    static var current: TemperatureUnitPreference {
        UserDefaults.standard.string(forKey: SettingsKey.temperatureUnit)
            .flatMap(TemperatureUnitPreference.init(rawValue:)) ?? .system
    }
}

/// Unit for bottle amounts. Amounts are always stored in millilitres.
nonisolated enum VolumeUnitPreference: String, CaseIterable, Identifiable {
    case system
    case milliliters
    case ounces

    var id: String { rawValue }

    static let millilitersPerOunce = 29.5735

    var title: String {
        switch self {
        case .system: "Automatic"
        case .milliliters: "Millilitres (ml)"
        case .ounces: "Ounces (oz)"
        }
    }

    /// Whether amounts should be entered and shown in fluid ounces.
    var usesOunces: Bool {
        switch self {
        case .system: Locale.current.measurementSystem == .us
        case .milliliters: false
        case .ounces: true
        }
    }

    var symbol: String { usesOunces ? "oz" : "ml" }

    /// Stepper increment in the display unit.
    var step: Double { usesOunces ? 0.5 : 10 }

    /// Largest amount offered in the form, in the display unit.
    var maximum: Double { usesOunces ? 14 : 400 }

    func toDisplay(milliliters: Double) -> Double {
        usesOunces ? (milliliters / Self.millilitersPerOunce * 2).rounded() / 2 : milliliters.rounded()
    }

    func toMilliliters(_ displayValue: Double) -> Double {
        usesOunces ? displayValue * Self.millilitersPerOunce : displayValue
    }

    /// "120 ml" or "4 oz" / "4.5 oz".
    func format(milliliters: Double) -> String {
        let value = toDisplay(milliliters: milliliters)
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(symbol)"
    }

    static var current: VolumeUnitPreference {
        UserDefaults.standard.string(forKey: SettingsKey.volumeUnit)
            .flatMap(VolumeUnitPreference.init(rawValue:)) ?? .system
    }
}
