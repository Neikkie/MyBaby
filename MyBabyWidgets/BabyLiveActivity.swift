import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// Lock Screen and Dynamic Island presentation for a running sleep or feed timer.
struct BabyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BabyActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(Self.title(for: context), systemImage: kind.symbol)
                        .font(.headline)
                        .foregroundStyle(kind.textColor)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(start: context.state.startDate)
                        .font(.title2.bold())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FinishButton(context: context)
                }
            } compactLeading: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.textColor)
            } compactTrailing: {
                TimerText(start: context.state.startDate)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.textColor)
            }
        }
    }

    /// "Asleep" / "Feeding · Left", with the baby's name when known.
    static func title(for context: ActivityViewContext<BabyActivityAttributes>) -> String {
        let name = context.attributes.babyName
        switch context.attributes.kind {
        case .sleep:
            return name.isEmpty ? "Asleep" : "\(name) is asleep"
        default:
            let side = context.state.side.map { " · \($0)" } ?? ""
            return "Feeding\(side)"
        }
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<BabyActivityAttributes>

    var body: some View {
        let kind = context.attributes.kind
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(kind.color, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(BabyLiveActivity.title(for: context))
                    .font(.headline)
                TimerText(start: context.state.startDate)
                    .font(.title.bold())
            }

            Spacer()

            FinishButton(context: context)
                .fixedSize()
        }
        .padding()
    }
}

/// Counts up from the start time.
private struct TimerText: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// Ends the timer without opening the app.
private struct FinishButton: View {
    let context: ActivityViewContext<BabyActivityAttributes>

    var body: some View {
        let kind = context.attributes.kind
        Button(intent: FinishTimerIntent(entryID: context.attributes.entryID)) {
            Label(kind == .sleep ? "Wake Up" : "Stop", systemImage: kind == .sleep ? "sun.horizon.fill" : "stop.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(kind.color)
    }
}

#Preview("Lock Screen", as: .content, using: BabyActivityAttributes(entryID: UUID(), kindRaw: "sleep", babyName: "Ava")) {
    BabyLiveActivity()
} contentStates: {
    BabyActivityAttributes.ContentState(startDate: .now.addingTimeInterval(-1250), side: nil)
}
