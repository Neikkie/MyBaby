import Charts
import CoreData
import SwiftUI

/// Weight, length and head size over time.
///
/// This charts the baby's own measurements. It deliberately doesn't draw percentile curves:
/// those need the official WHO growth standard tables, and your pediatrician's chart is the
/// right place to compare against them.
struct GrowthView: View {
    @ObservedObject var baby: Baby
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme
    @FetchRequest private var measurements: FetchedResults<GrowthMeasurement>

    @State private var metric: GrowthMetric = .weight
    @State private var isAdding = false
    @State private var editing: GrowthMeasurement?

    init(baby: Baby) {
        self.baby = baby
        _measurements = FetchRequest(fetchRequest: GrowthMeasurement.fetch(for: baby))
    }

    private var points: [(date: Date, value: Double)] {
        measurements.compactMap { m in
            guard let date = m.date, let value = metric.value(of: m) else { return nil }
            return (date, metric.display(value))
        }
    }

    var body: some View {
        List {
            if measurements.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Measurements Yet", systemImage: "ruler.fill")
                    } description: {
                        Text("Add \(baby.displayName)'s weight, length and head size after each checkup to see how they're growing.")
                    } actions: {
                        Button("Add Measurement") { isAdding = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            } else {
                Section {
                    LatestRow(measurements: Array(measurements))
                }

                Section {
                    Picker("Measure", selection: $metric) {
                        ForEach(GrowthMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if points.count >= 1 {
                        Chart {
                            ForEach(points, id: \.date) { point in
                                LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                                    .interpolationMethod(.monotone)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                                    .symbolSize(70)
                                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue(metric.format(metric.stored(point.value)))
                            }
                        }
                        .foregroundStyle(theme.accent)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxisLabel(metric.unitLabel)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                    } else {
                        Text("No \(metric.title.lowercased()) logged yet.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Compare with the growth chart at your pediatrician's office. Percentile curves aren't shown here.")
                }

                Section("All Measurements") {
                    ForEach(measurements.reversed()) { measurement in
                        Button { editing = measurement } label: {
                            MeasurementRow(measurement: measurement, birthday: baby.birthday)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation {
                                    context.delete(measurement)
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Growth")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Measurement", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            MeasurementSheet(baby: baby, measurement: nil)
        }
        .sheet(item: $editing) { measurement in
            MeasurementSheet(baby: baby, measurement: measurement)
        }
    }
}

// MARK: - Units

/// Whether to show pounds and inches (US) or kilograms and centimetres.
private var usesImperial: Bool { Locale.current.measurementSystem == .us }

enum GrowthMetric: String, CaseIterable, Identifiable {
    case weight
    case length
    case head

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: String(localized: "Weight")
        case .length: String(localized: "Length")
        case .head: String(localized: "Head")
        }
    }

    var unitLabel: String {
        switch self {
        case .weight: usesImperial ? "lb" : "kg"
        case .length, .head: usesImperial ? "in" : "cm"
        }
    }

    func value(of measurement: GrowthMeasurement) -> Double? {
        switch self {
        case .weight: measurement.weightKg
        case .length: measurement.lengthCm
        case .head: measurement.headCm
        }
    }

    /// Stored metric value to the displayed unit.
    func display(_ stored: Double) -> Double {
        guard usesImperial else { return stored }
        return self == .weight ? stored * 2.20462 : stored / 2.54
    }

    /// Displayed unit back to the stored metric value.
    func stored(_ display: Double) -> Double {
        guard usesImperial else { return display }
        return self == .weight ? display / 2.20462 : display * 2.54
    }

    /// "12 lb 4 oz", "5.6 kg", "23.5 in", "59.7 cm".
    func format(_ stored: Double) -> String {
        switch self {
        case .weight:
            if usesImperial {
                let ounces = stored * 35.27396
                let pounds = Int(ounces / 16)
                let remainder = Int((ounces - Double(pounds) * 16).rounded())
                return remainder == 16 ? "\(pounds + 1) lb" : "\(pounds) lb \(remainder) oz"
            }
            return "\(stored.formatted(.number.precision(.fractionLength(0...2)))) kg"
        case .length, .head:
            let value = display(stored)
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unitLabel)"
        }
    }

    /// "+8 oz", "−0.2 kg", "+1.2 in".
    func formatChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : "−"
        let magnitude = abs(change)
        if self == .weight, usesImperial {
            let ounces = magnitude * 35.27396
            return ounces >= 16
                ? "\(sign)\((ounces / 16).formatted(.number.precision(.fractionLength(0...1)))) lb"
                : "\(sign)\(Int(ounces.rounded())) oz"
        }
        let value = display(magnitude)
        let digits = self == .weight ? 0...2 : 0...1
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(digits)))) \(unitLabel)"
    }
}

// MARK: - Rows

/// The most recent value of each measure, with the change since the one before.
private struct LatestRow: View {
    let measurements: [GrowthMeasurement]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(GrowthMetric.allCases) { metric in
                let values = measurements.compactMap { metric.value(of: $0) }
                VStack(spacing: 4) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(values.last.map(metric.format) ?? "—")
                        .font(.headline)
                        .fontDesign(.rounded)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if values.count >= 2, let last = values.last {
                        Text(metric.formatChange(last - values[values.count - 2]))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(EntryKind.diaper.textColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MeasurementRow: View {
    @ObservedObject var measurement: GrowthMeasurement
    let birthday: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(measurement.date ?? .now, format: .dateTime.month(.abbreviated).day().year())
                    .font(.headline)
                Spacer()
                if let birthday, let date = measurement.date,
                   let age = BabyAge(birthdayInterval: birthday.timeIntervalSince1970, now: date) {
                    Text(age.weeksDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            let values = GrowthMetric.allCases.compactMap { metric in
                metric.value(of: measurement).map { "\(metric.title) \(metric.format($0))" }
            }
            Text(values.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !measurement.notes.isEmpty {
                Text(measurement.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

// MARK: - Add / edit

private struct MeasurementSheet: View {
    @ObservedObject var baby: Baby
    let measurement: GrowthMeasurement?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    // Imperial weight is entered as pounds + ounces; everything else as one number.
    @State private var pounds: Double?
    @State private var ounces: Double?
    @State private var kilograms: Double?
    @State private var length: Double?
    @State private var head: Double?
    @State private var notes: String

    init(baby: Baby, measurement: GrowthMeasurement?) {
        self.baby = baby
        self.measurement = measurement
        _date = State(initialValue: measurement?.date ?? .now)
        _notes = State(initialValue: measurement?.notes ?? "")
        if let kg = measurement?.weightKg {
            let totalOunces = kg * 35.27396
            _pounds = State(initialValue: Double(Int(totalOunces / 16)))
            _ounces = State(initialValue: (totalOunces - Double(Int(totalOunces / 16)) * 16).rounded())
            _kilograms = State(initialValue: kg)
        }
        _length = State(initialValue: measurement?.lengthCm.map(GrowthMetric.length.display))
        _head = State(initialValue: measurement?.headCm.map(GrowthMetric.head.display))
    }

    private var weightKg: Double? {
        if usesImperial {
            guard pounds != nil || ounces != nil else { return nil }
            return ((pounds ?? 0) * 16 + (ounces ?? 0)) / 35.27396
        }
        return kilograms
    }

    private var canSave: Bool { weightKg != nil || length != nil || head != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("Weight") {
                    if usesImperial {
                        HStack {
                            TextField("lb", value: $pounds, format: .number)
                                .keyboardType(.numberPad)
                            Text("lb").foregroundStyle(.secondary)
                            TextField("oz", value: $ounces, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                            Text("oz").foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            TextField("Weight", value: $kilograms, format: .number.precision(.fractionLength(0...3)))
                                .keyboardType(.decimalPad)
                            Text("kg").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Length") {
                    HStack {
                        TextField("Length", value: $length, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Text(GrowthMetric.length.unitLabel).foregroundStyle(.secondary)
                    }
                }
                Section("Head Size") {
                    HStack {
                        TextField("Head circumference", value: $head, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Text(GrowthMetric.head.unitLabel).foregroundStyle(.secondary)
                    }
                }
                Section("Notes") {
                    TextField("Optional notes, like \"2-month checkup\"", text: $notes, axis: .vertical)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(measurement == nil ? "Add Measurement" : "Edit Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let target = measurement ?? GrowthMeasurement(context: context, baby: baby, date: date)
        target.date = date
        target.weightKg = weightKg
        target.lengthCm = length.map(GrowthMetric.length.stored)
        target.headCm = head.map(GrowthMetric.head.stored)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        dismiss()
    }
}

// MARK: - Today row

/// Slim link from Today to growth tracking.
struct GrowthRow: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var measurements: FetchedResults<GrowthMeasurement>
    @Environment(\.appTheme) private var theme

    init(baby: Baby) {
        self.baby = baby
        _measurements = FetchRequest(fetchRequest: GrowthMeasurement.fetch(for: baby))
    }

    var body: some View {
        NavigationLink {
            GrowthView(baby: baby)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(EntryKind.diaper.color.gradient, in: .rect(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Growth")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    private var summary: String {
        guard let latest = measurements.last else { return String(localized: "Track weight, length and head size") }
        let parts = GrowthMetric.allCases.compactMap { metric in metric.value(of: latest).map(metric.format) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        GrowthView(baby: PreviewStore.firstBaby(in: PreviewStore.sampleDay))
    }
    .environment(\.managedObjectContext, PreviewStore.sampleDay.viewContext)
}
