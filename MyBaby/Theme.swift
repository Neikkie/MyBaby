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

/// Colors taken from the app artwork: a lavender sky fading into pink-lilac clouds,
/// with the purple-to-pink "myBaby" wordmark. The app is always shown in Light Mode.
///
/// Accent colors have at least 4.5:1 contrast on every part of the background (and with white
/// text on top); the gradient titles are large bold text, which needs 3:1.
struct AppTheme {
    /// Buttons, links, toggles and the selected tab.
    let accent: Color
    /// Gradient used for the fun navigation titles.
    let titleColors: [Color]
    /// Sky gradient behind every screen, top to bottom.
    let backgroundColors: [Color]
    /// Fluffy clouds along the top of each screen.
    let cloudColor: Color
    /// Tinted clouds along the bottom, like the clouds under the bear in the artwork.
    let lowCloudColor: Color

    /// Pink sky with lilac clouds.
    static let girl = AppTheme(
        accent: Color(hex: 0xAD1457),
        titleColors: [Color(hex: 0x7B3FC4), Color(hex: 0xD81B60)],
        backgroundColors: [Color(hex: 0xF9D4EC), Color(hex: 0xFDEBF5), Color(hex: 0xF1DAFB)],
        cloudColor: Color(hex: 0xFFF6FB),
        lowCloudColor: Color(hex: 0xF8D3EE)
    )

    /// Soft blue sky fading into lavender clouds.
    static let boy = AppTheme(
        accent: Color(hex: 0x0D58AD),
        titleColors: [Color(hex: 0x1565C0), Color(hex: 0x6A4FD8)],
        backgroundColors: [Color(hex: 0xD3E3FD), Color(hex: 0xEAF1FF), Color(hex: 0xE4DAFB)],
        cloudColor: Color(hex: 0xF7FAFF),
        lowCloudColor: Color(hex: 0xDCD6FB)
    )

    /// The artwork itself: lavender sky and pink-lilac clouds.
    static let both = AppTheme(
        accent: Color(hex: 0x6A32B5),
        titleColors: [Color(hex: 0x7B3FC4), Color(hex: 0xD81B60)],
        backgroundColors: [Color(hex: 0xE6D2FD), Color(hex: 0xF5E9FE), Color(hex: 0xF8DDF7)],
        cloudColor: Color(hex: 0xFEF4FD),
        lowCloudColor: Color(hex: 0xF3CBFB)
    )

    var titleGradient: LinearGradient {
        LinearGradient(colors: titleColors, startPoint: .leading, endPoint: .trailing)
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundColors, startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    /// A fixed sRGB color from a hex value like 0x7B3FC4.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .both
}

// MARK: - Background

/// The artwork's sky: a pastel gradient with fluffy clouds along the top and bottom.
struct ThemedBackground: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            theme.backgroundGradient
            CloudBank(color: theme.cloudColor, puffs: CloudBank.topPuffs)
                .frame(height: 220)
                .offset(y: -40)
                .frame(maxHeight: .infinity, alignment: .top)
            CloudBank(color: theme.lowCloudColor, puffs: CloudBank.bottomPuffs)
                .frame(height: 200)
                .offset(y: 70)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A row of overlapping, blurred circles that reads as fluffy clouds.
private struct CloudBank: View {
    let color: Color
    let puffs: [(x: CGFloat, y: CGFloat, size: CGFloat)]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                ForEach(Array(puffs.enumerated()), id: \.offset) { _, puff in
                    Circle()
                        .fill(color)
                        .frame(width: width * puff.size, height: width * puff.size)
                        .position(x: width * puff.x, y: proxy.size.height * puff.y)
                }
            }
            .blur(radius: 18)
            .opacity(0.85)
        }
    }

    /// Relative positions and sizes of each puff.
    static let topPuffs: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.05, 0.55, 0.45), (0.30, 0.45, 0.38), (0.55, 0.60, 0.42),
        (0.80, 0.45, 0.40), (1.02, 0.60, 0.44),
    ]

    static let bottomPuffs: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.0, 0.40, 0.50), (0.28, 0.55, 0.44), (0.52, 0.38, 0.48),
        (0.78, 0.55, 0.42), (1.0, 0.40, 0.50),
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

