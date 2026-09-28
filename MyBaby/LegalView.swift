import SwiftUI

/// Contact details and legal text shown from Settings.
enum AppInfo {
    static let supportEmail = "support.chaniiapps@gmail.com"
    static let developerName = "Chanii Apps"
    static let effectiveDate = "September 27, 2026"

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
                LegalDocumentView(title: "Privacy Policy", sections: LegalText.privacy)
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }

            NavigationLink {
                LegalDocumentView(title: "Terms of Use", sections: LegalText.terms)
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

/// A simple, readable legal document.
struct LegalDocumentView: View {
    let title: String
    let sections: [(heading: String, body: String)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Effective \(AppInfo.effectiveDate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(sections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sections[index].heading)
                            .font(.headline)
                            .fontDesign(.rounded)
                        Text(sections[index].body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding()
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { ThemedBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum LegalText {
    static let privacy: [(heading: String, body: String)] = [
        ("Overview",
         "My Baby is made by \(AppInfo.developerName). We built it so your family's information stays yours. We don't collect, sell or share your personal data, and the app has no accounts, ads, analytics or tracking."),
        ("What you enter",
         "The app stores what you choose to log — such as your baby's name, birthday, feeds, sleep, diapers, symptoms, temperatures and notes — so it can show your history, summaries and suggestions."),
        ("Where it's stored",
         "Your entries are stored on your device. If iCloud is turned on, they also sync through your own private iCloud account using Apple's CloudKit, so they appear on your other devices. We can't see or access this data. You can turn off iCloud syncing for My Baby in the Settings app."),
        ("Notifications, widgets and Live Activities",
         "Feed reminders are scheduled on your device. Widgets and Live Activities read your entries on your device to show recent activity. None of this is sent to us."),
        ("Health information",
         "Symptoms and temperatures you log are used only to display them back to you. They aren't shared with anyone, and they aren't used for advertising."),
        ("Children's privacy",
         "My Baby is intended for parents and caregivers, not for children to use. Information about a child is entered by their parent or caregiver and stays in that person's control."),
        ("Deleting your data",
         "You can delete individual entries at any time, or delete everything from Settings > Delete All Entries. Deleting the app removes data from the device; data in iCloud can be removed from the Settings app under iCloud > Manage Storage."),
        ("Changes",
         "If this policy changes, we'll update it in the app and change the effective date above."),
        ("Contact",
         "Questions about privacy? Email us at \(AppInfo.supportEmail)."),
    ]

    static let terms: [(heading: String, body: String)] = [
        ("Agreement",
         "By using My Baby, you agree to these terms. If you don't agree, please don't use the app."),
        ("Not medical advice",
         "My Baby is a record-keeping tool. Suggestions such as feeding times, sleep windows, diaper goals and developmental milestones are general estimates, not medical advice, diagnosis or treatment. Always follow your pediatrician's guidance, and call your doctor or emergency services if you're worried about your baby's health."),
        ("Your content",
         "You own everything you enter. You're responsible for its accuracy and for keeping your device and iCloud account secure."),
        ("Acceptable use",
         "Use the app only for lawful, personal purposes. Don't attempt to reverse engineer, disrupt or misuse the app."),
        ("Availability",
         "We work to keep My Baby reliable, but it's provided \"as is\" and we can't guarantee it will always be available, error-free or that data will never be lost. We recommend keeping iCloud turned on as a backup."),
        ("Limitation of liability",
         "To the extent allowed by law, \(AppInfo.developerName) isn't liable for any indirect or consequential damages arising from your use of the app."),
        ("Apple's terms",
         "These terms are between you and \(AppInfo.developerName), not Apple. Your use of the app is also subject to the Apple Media Services Terms and Conditions."),
        ("Changes",
         "We may update these terms from time to time. Continuing to use the app after an update means you accept the new terms."),
        ("Contact",
         "Questions? Email \(AppInfo.supportEmail)."),
    ]
}

#Preview {
    NavigationStack {
        Form { SupportAndLegalSection() }
    }
}
