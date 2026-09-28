import SwiftUI

extension BabyGender {
    var theme: AppTheme {
        switch self {
        case .girl: .girl
        case .boy: .boy
        case .both: .both
        }
    }
}

/// Colors inspired by the app icon: pastel clouds with a purple-to-pink wordmark.
///
/// Every text color here has at least 4.5:1 contrast on its background in both appearances
/// (the gradient title is large bold text, which needs 3:1).
struct AppTheme {
    /// Buttons, links, toggles and the selected tab.
    let accent: Color
    /// Gradient used for the fun navigation titles.
    let titleColors: [Color]
    /// Soft background gradient behind lists, top to bottom.
    let backgroundColors: [Color]
    /// Tint for the decorative clouds at the top of each screen.
    let cloudColor: Color

    static let girl = AppTheme(
        accent: Color(light: 0xC2185B, dark: 0xFF80B5),
        titleColors: [Color(light: 0x7B3FC4, dark: 0xC3A3FF), Color(light: 0xD81B60, dark: 0xFF80B5)],
        backgroundColors: [Color(light: 0xFDEBF3, dark: 0x2A1622), Color(light: 0xF4EEFF, dark: 0x1A1426)],
        cloudColor: Color(light: 0xFFFFFF, dark: 0x3A2440)
    )

    static let boy = AppTheme(
        accent: Color(light: 0x1565C0, dark: 0x82B4FF),
        titleColors: [Color(light: 0x1565C0, dark: 0x82B4FF), Color(light: 0x6A4FD8, dark: 0xB9A6FF)],
        backgroundColors: [Color(light: 0xE8F1FF, dark: 0x121C2E), Color(light: 0xEEF0FF, dark: 0x16142A)],
        cloudColor: Color(light: 0xFFFFFF, dark: 0x22304A)
    )

    static let both = AppTheme(
        accent: Color(light: 0x7B3FC4, dark: 0xC3A3FF),
        titleColors: [Color(light: 0x7B3FC4, dark: 0xC3A3FF), Color(light: 0xD81B60, dark: 0xFF80B5)],
        backgroundColors: [Color(light: 0xF4EEFF, dark: 0x1E1630), Color(light: 0xEAF7F1, dark: 0x141A24)],
        cloudColor: Color(light: 0xFFFFFF, dark: 0x2E2544)
    )

    var titleGradient: LinearGradient {
        LinearGradient(colors: titleColors, startPoint: .leading, endPoint: .trailing)
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundColors, startPoint: .top, endPoint: .bottom)
    }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .both
}

// MARK: - Background

/// Pastel gradient with soft clouds drifting along the top, like the app icon.
struct ThemedBackground: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack(alignment: .top) {
            theme.backgroundGradient
            CloudBank(color: theme.cloudColor)
                .frame(height: 220)
                .offset(y: -40)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A row of overlapping, blurred circles that reads as fluffy clouds.
private struct CloudBank: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                ForEach(Array(Self.puffs.enumerated()), id: \.offset) { _, puff in
                    Circle()
                        .fill(color)
                        .frame(width: width * puff.size, height: width * puff.size)
                        .position(x: width * puff.x, y: proxy.size.height * puff.y)
                }
            }
            .blur(radius: 18)
            .opacity(0.8)
        }
    }

    /// Relative positions and sizes of each puff.
    private static let puffs: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.05, 0.55, 0.45), (0.30, 0.45, 0.38), (0.55, 0.60, 0.42),
        (0.80, 0.45, 0.40), (1.02, 0.60, 0.44),
    ]
}

extension View {
    /// Replaces the plain list background with the themed pastel background.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { ThemedBackground() }
    }
}

// MARK: - Fun titles

/// Chunky rounded gradient title with a little heart, echoing the "myBaby" wordmark.
struct FunTitle: View {
    let title: String
    /// When true, draws the "myBaby" wordmark itself: purple "my", pink "Baby".
    var isWordmark = false
    var alignment: Alignment = .leading
    var font: Font = .largeTitle.weight(.black)
    var heartFont: Font = .body

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if isWordmark {
                Text("my")
                    .foregroundStyle(theme.titleColors[0])
                Text("Baby")
                    .foregroundStyle(theme.titleColors[theme.titleColors.count - 1])
            } else {
                Text(title)
                    .foregroundStyle(theme.titleGradient)
            }
            Image(systemName: "heart.fill")
                .font(heartFont)
                .foregroundStyle(theme.titleColors[theme.titleColors.count - 1])
                .rotationEffect(.degrees(-12))
                .offset(y: -16)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .font(font)
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isWordmark ? "My Baby" : title)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Sets the navigation title and draws it in the playful themed style when shown large.
    func funNavigationTitle(_ title: String, isWordmark: Bool = false) -> some View {
        navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    FunTitle(title: title, isWordmark: isWordmark)
                }
            }
    }
}
