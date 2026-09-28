import SwiftUI

/// What each home-screen tile shows at the baby's current age.
/// Feeding moves from bottle to food, and diapers become potty time.
struct TileStage {
    let symbol: TileArtwork.Art
    let label: String
    /// Short, friendly description of this stage, e.g. "First foods".
    let caption: String

    static func forKind(_ kind: EntryKind, age: BabyAge?) -> TileStage {
        let months = age?.months ?? 0
        switch kind {
        case .feed:
            switch months {
            case ..<6: return TileStage(symbol: .bottle, label: "Feed", caption: "Milk time")
            case ..<9: return TileStage(symbol: .sfSymbol("carrot.fill"), label: "Feed", caption: "First foods")
            case ..<12: return TileStage(symbol: .sfSymbol("fork.knife"), label: "Feed", caption: "Finger foods")
            default: return TileStage(symbol: .sfSymbol("fork.knife.circle.fill"), label: "Feed", caption: "Meals & snacks")
            }
        case .sleep:
            switch months {
            case ..<3: return TileStage(symbol: .teddy, label: "Sleep", caption: "Newborn naps")
            case ..<12: return TileStage(symbol: .teddy, label: "Sleep", caption: "Naps & nights")
            case ..<24: return TileStage(symbol: .teddy, label: "Sleep", caption: "Toddler sleep")
            default: return TileStage(symbol: .teddy, label: "Sleep", caption: "Big kid bedtime")
            }
        default:
            // Most children start potty training between 2 and 3 years.
            switch months {
            case ..<24: return TileStage(symbol: .diaper, label: "Diaper", caption: "Changes")
            case ..<36: return TileStage(symbol: .potty, label: "Potty", caption: "Potty training")
            default: return TileStage(symbol: .potty, label: "Potty", caption: "Potty time")
            }
        }
    }

    var isPottyStage: Bool {
        if case .potty = symbol { return true }
        return false
    }
}

/// Animated tile illustration: a tilting bottle, a snoozing teddy, a bobbing diaper, and so on.
struct TileArtwork: View {
    enum Art: Equatable {
        case bottle
        case teddy
        case diaper
        case potty
        case sfSymbol(String)
    }

    let art: Art
    let kind: EntryKind
    var size: CGFloat = 44
    /// Idle motion; also turned off automatically with Reduce Motion.
    var isAnimated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { isAnimated && !reduceMotion }

    var body: some View {
        Group {
            switch art {
            case .bottle:
                BabyBottle(color: kind.textColor)
                    .frame(width: size * 0.62, height: size)
                    .wobble(degrees: 7, isActive: animates)
            case .teddy:
                SleepingTeddy(size: size, zColor: kind.textColor, isAnimated: animates)
            case .diaper:
                Diaper(color: kind.textColor)
                    .frame(width: size, height: size * 0.82)
                    .bob(isActive: animates)
            case .potty:
                Image(systemName: "toilet.fill")
                    .font(.system(size: size * 0.85, weight: .semibold))
                    .foregroundStyle(kind.textColor)
                    .bob(isActive: animates)
            case .sfSymbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.85, weight: .semibold))
                    .foregroundStyle(name == "carrot.fill" ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(kind.textColor))
                    .wobble(degrees: 6, isActive: animates)
            }
        }
        .frame(width: size * 1.3, height: size * 1.15)
        .accessibilityHidden(true)
    }
}

// MARK: - Illustrations

/// A baby bottle like the one on the app icon: amber nipple, colored collar, milk inside.
private struct BabyBottle: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            VStack(spacing: 0) {
                // Nipple
                Capsule()
                    .fill(Color(red: 0.96, green: 0.70, blue: 0.25).gradient)
                    .frame(width: w * 0.34, height: h * 0.2)
                    .offset(y: h * 0.04)
                // Collar
                RoundedRectangle(cornerRadius: w * 0.08, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: w * 0.86, height: h * 0.14)
                // Body with milk and measuring lines
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                        .fill(.white)
                    RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.97, blue: 0.9))
                        .frame(height: h * 0.4)
                    VStack(spacing: h * 0.08) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(color.opacity(0.7))
                                .frame(width: w * (index == 1 ? 0.22 : 0.32), height: max(h * 0.025, 1.5))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, w * 0.14)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: w * 0.26, style: .continuous)
                        .strokeBorder(color.opacity(0.35), lineWidth: max(w * 0.04, 1))
                }
                .frame(width: w * 0.78)
            }
            .frame(width: w, height: h)
        }
    }
}

/// A teddy bear dozing, with little "z"s drifting up.
private struct SleepingTeddy: View {
    let size: CGFloat
    let zColor: Color
    let isAnimated: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "teddybear.fill")
                .font(.system(size: size * 0.85))
                .foregroundStyle(Color(red: 0.72, green: 0.47, blue: 0.25).gradient)
                .breathe(isActive: isAnimated)

            FloatingZs(color: zColor, size: size, isAnimated: isAnimated)
                .offset(x: size * 0.22, y: -size * 0.02)
        }
    }
}

private struct FloatingZs: View {
    let color: Color
    let size: CGFloat
    let isAnimated: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let z = Text("z")
                    .font(.system(size: size * (0.18 + CGFloat(index) * 0.06), weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .offset(x: CGFloat(index) * size * 0.1, y: -CGFloat(index) * size * 0.14)
                if isAnimated {
                    // Each "z" drifts up and fades, a little after the one before it.
                    z.phaseAnimator([0.0, 1.0]) { view, phase in
                        view
                            .offset(x: phase * size * 0.08, y: -phase * size * 0.12)
                            .opacity(1 - phase * 0.7)
                    } animation: { _ in
                        .easeInOut(duration: 1.6).delay(Double(index) * 0.35)
                    }
                } else {
                    z
                }
            }
        }
    }
}

/// A diaper with a little heart, like the one on the app icon.
private struct Diaper: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .top) {
                DiaperShape()
                    .fill(.white)
                DiaperShape()
                    .stroke(color.opacity(0.35), lineWidth: max(w * 0.04, 1))
                // Waistband
                RoundedRectangle(cornerRadius: h * 0.08, style: .continuous)
                    .fill(color.opacity(0.25))
                    .frame(width: w * 0.9, height: h * 0.18)
                // Side tabs
                HStack {
                    tab(w: w, h: h)
                    Spacer()
                    tab(w: w, h: h)
                }
                .frame(width: w)
                .offset(y: h * 0.12)
                Image(systemName: "heart.fill")
                    .font(.system(size: h * 0.28))
                    .foregroundStyle(color)
                    .offset(y: h * 0.36)
            }
            .frame(width: w, height: h)
        }
    }

    private func tab(w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
            .fill(Color(red: 0.55, green: 0.75, blue: 0.98))
            .frame(width: w * 0.14, height: h * 0.2)
    }
}

private struct DiaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.05, y: h * 0.06))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.06))
        // Right side curves in toward the leg opening.
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.94),
                      control1: CGPoint(x: w * 0.98, y: h * 0.55),
                      control2: CGPoint(x: w * 0.78, y: h * 0.62))
        path.addQuadCurve(to: CGPoint(x: w * 0.32, y: h * 0.94), control: CGPoint(x: w * 0.5, y: h * 1.02))
        path.addCurve(to: CGPoint(x: w * 0.05, y: h * 0.06),
                      control1: CGPoint(x: w * 0.22, y: h * 0.62),
                      control2: CGPoint(x: w * 0.02, y: h * 0.55))
        path.closeSubpath()
        return path
    }
}

// MARK: - Idle motions

/// Loops a gentle two-phase motion, or leaves the view still when inactive (e.g. Reduce Motion).
private struct IdleMotion: ViewModifier {
    enum Kind { case wobble(Double), bob, breathe }

    let kind: Kind
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([0.0, 1.0]) { view, phase in
                switch kind {
                case .wobble(let degrees):
                    view.rotationEffect(.degrees((phase * 2 - 1) * degrees), anchor: .bottom)
                case .bob:
                    view.offset(y: -4 * phase)
                case .breathe:
                    view.scaleEffect(1 + 0.05 * phase, anchor: .bottom)
                }
            } animation: { _ in
                switch kind {
                case .wobble: .easeInOut(duration: 1.4)
                case .bob: .easeInOut(duration: 1.2)
                case .breathe: .easeInOut(duration: 1.8)
                }
            }
        } else {
            content
        }
    }
}

private extension View {
    /// Gentle side-to-side tilt.
    func wobble(degrees: Double, isActive: Bool) -> some View {
        modifier(IdleMotion(kind: .wobble(degrees), isActive: isActive))
    }

    /// Soft floating up and down.
    func bob(isActive: Bool) -> some View {
        modifier(IdleMotion(kind: .bob, isActive: isActive))
    }

    /// Slow breathing, like a sleeping baby.
    func breathe(isActive: Bool) -> some View {
        modifier(IdleMotion(kind: .breathe, isActive: isActive))
    }
}

#Preview {
    let samples: [(TileArtwork.Art, EntryKind)] = [
        (.bottle, .feed), (.teddy, .sleep), (.diaper, .diaper), (.potty, .diaper), (.sfSymbol("carrot.fill"), .feed),
    ]
    HStack(spacing: 20) {
        ForEach(samples.indices, id: \.self) { index in
            TileArtwork(art: samples[index].0, kind: samples[index].1, size: 56)
                .padding(8)
                .background(samples[index].1.softColor, in: .rect(cornerRadius: 20))
        }
    }
    .padding()
}
