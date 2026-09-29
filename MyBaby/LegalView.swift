import SwiftUI
import WebKit

/// Contact details and website pages shown from Settings.
enum AppInfo {
    static let supportEmail = "support.chaniiapps@gmail.com"
    static let developerName = "Chanii Apps"

    static let homeURL = URL(string: "https://neikkie.github.io/MyBaby/index.html")
    static let howItWorksURL = URL(string: "https://neikkie.github.io/MyBaby/usage.html")
    static let privacyURL = URL(string: "https://neikkie.github.io/MyBaby/privacy.html")
    static let termsURL = URL(string: "https://neikkie.github.io/MyBaby/terms.html")

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// A mailto link with a helpful subject and the details support usually needs.
    static var supportMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "My Baby Support"),
            URLQueryItem(name: "body", value: "\n\n—\nApp version: \(version)\niOS: \(UIDevice.current.systemVersion)"),
        ]
        return components.url
    }
}

/// Settings section with privacy, terms and support.
struct SupportAndLegalSection: View {
    @Environment(\.openURL) private var openURL
    @State private var didCopyEmail = false

    var body: some View {
        Section {
            NavigationLink {
                WebPageView(title: "Home", url: AppInfo.homeURL)
            } label: {
                Label("Home", systemImage: "house.fill")
            }

            NavigationLink {
                WebPageView(title: "How It Works", url: AppInfo.howItWorksURL)
            } label: {
                Label("How It Works", systemImage: "questionmark.circle.fill")
            }

            NavigationLink {
                WebPageView(title: "Privacy Policy", url: AppInfo.privacyURL)
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }

            NavigationLink {
                WebPageView(title: "Terms of Use", url: AppInfo.termsURL)
            } label: {
                Label("Terms of Use", systemImage: "doc.text.fill")
            }

            Button {
                if let url = AppInfo.supportMailURL { openURL(url) }
            } label: {
                LabeledContent {
                    Text(AppInfo.supportEmail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Contact Support", systemImage: "envelope.fill")
                }
            }
            .contextMenu {
                Button("Copy Email Address", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = AppInfo.supportEmail
                    didCopyEmail = true
                }
            }

            LabeledContent("Version", value: AppInfo.version)
        } header: {
            Text("Privacy & Support")
        } footer: {
            Text(didCopyEmail ? "Email address copied." : "My Baby doesn't collect your data. Everything stays on your devices and in your private iCloud.")
        }
    }
}

/// Shows a page from the My Baby website inside the app.
struct WebPageView: View {
    let title: String
    let url: URL?

    var body: some View {
        WebView(url: url)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        Form { SupportAndLegalSection() }
    }
}
