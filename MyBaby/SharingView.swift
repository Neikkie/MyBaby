import CloudKit
import CoreData
import SwiftUI
import UIKit

/// Settings section for sharing a baby's log with a partner or caregiver through iCloud.
struct SharingSection: View {
    @ObservedObject var baby: Baby

    @State private var isPreparing = false
    @State private var errorMessage: String?
    /// Bumped after the sharing screen closes so the status refreshes.
    @State private var refresh = 0
    @Environment(\.scenePhase) private var scenePhase

    private let persistence = PersistenceController.shared

    private var share: CKShare? {
        _ = refresh
        return persistence.existingShare(for: baby)
    }

    private var isFromSomeoneElse: Bool { persistence.isFromSomeoneElse(baby) }

    /// Everyone on the share except you.
    private var otherPeople: [CKShare.Participant] {
        (share?.participants ?? []).filter { $0 != share?.currentUserParticipant }
    }

    var body: some View {
        Section {
            ICloudStatusRow()
            if isFromSomeoneElse {
                LabeledContent("Shared by", value: share.map { Self.name(of: $0.owner) } ?? "Someone else")
                Button("Manage or Leave", systemImage: "person.2.badge.gearshape") {
                    Task { await openSharing() }
                }
            } else {
                if persistence.isCloudKitEnabled {
                    // The system share sheet creates the invitation link when Messages, Mail etc. is picked.
                    ShareLink(item: shareItem, preview: SharePreview(shareItem.title, image: Image("WelcomeArt"))) {
                        Label(share == nil ? "Share \(baby.displayName)'s Log" : "Invite Someone Else", systemImage: "person.2.fill")
                    }
                } else {
                    Button("Share \(baby.displayName)'s Log", systemImage: "person.2.fill") {
                        errorMessage = "Sign in to iCloud in the Settings app to share \(baby.displayName)'s log."
                    }
                }

                if share != nil {
                    Button {
                        Task { await openSharing() }
                    } label: {
                        HStack {
                            Label("Manage Sharing", systemImage: "person.2.badge.gearshape")
                            Spacer()
                            if isPreparing { ProgressView() }
                        }
                    }
                    .disabled(isPreparing)
                }

                ForEach(otherPeople, id: \.self) { person in
                    LabeledContent(Self.name(of: person), value: Self.status(of: person))
                }
            }
        } header: {
            Text("Share With Family")
        } footer: {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(EntryKind.health.textColor)
            } else if isFromSomeoneElse {
                Text("You can log for \(baby.displayName), and everyone on the share sees it right away.")
            } else {
                Text("Invite a partner, grandparent or nanny. They'll see and log for \(baby.displayName) on their own iPhone. Sharing uses iCloud, so everyone needs an Apple Account.")
            }
        }
        // Coming back from Messages or Mail: show the new share and who's invited.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh += 1 }
        }
    }

    private var shareItem: BabyShareItem {
        BabyShareItem(objectID: baby.objectID, title: "\(baby.displayName)'s Baby Log")
    }

    private func openSharing() async {
        errorMessage = nil
        guard persistence.isCloudKitEnabled,
              (try? await persistence.cloudKitContainer.accountStatus()) == .available
        else {
            errorMessage = "Sign in to iCloud in the Settings app to share \(baby.displayName)'s log."
            return
        }
        if let share {
            presentSharing(share, container: persistence.cloudKitContainer)
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let (share, container) = try await persistence.makeShare(for: baby)
            presentSharing(share, container: container)
        } catch {
            errorMessage = "Couldn't start sharing. Check your connection and try again. (\(error.localizedDescription))"
        }
    }

    private func presentSharing(_ share: CKShare, container: CKContainer) {
        CloudSharingPresenter.present(share: share, container: container, title: "\(baby.displayName)'s Baby Log") { result in
            refresh += 1
            if case .failure(let error) = result {
                errorMessage = "Couldn't send the invitation. (\(error.localizedDescription))"
            }
        }
    }

    /// The person's name only. Phone numbers and email addresses are never shown, for privacy.
    static func name(of participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return String(localized: "Invited Person")
    }

    static func status(of participant: CKShare.Participant) -> String {
        switch participant.acceptanceStatus {
        case .accepted: participant.permission == .readOnly ? "Can view" : "Can log"
        case .pending: "Invited"
        case .removed: "Removed"
        default: "Unknown"
        }
    }
}

/// Shows whether iCloud sync is on. Apps can't sign in to iCloud themselves, so when
/// there's no account this points people to the Settings app.
struct ICloudStatusRow: View {
    @Environment(\.openURL) private var openURL
    @State private var status: CKAccountStatus?

    private let persistence = PersistenceController.shared

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isOn ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                    .foregroundStyle(isOn ? EntryKind.diaper.textColor : EntryKind.health.textColor)
            }
            Spacer()
            if status == nil {
                ProgressView()
            } else if !isOn {
                Button("Sign In") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .task {
            await refresh()
            // Signing in or out while the app is open.
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await refresh()
            }
        }
    }

    private var isOn: Bool { persistence.isCloudKitEnabled && status == .available }

    private var detail: String {
        switch status {
        case nil: String(localized: "Checking…")
        case .available?: persistence.isCloudKitEnabled
            ? String(localized: "On. Your log is backed up and syncs to your devices.")
            : String(localized: "Unavailable right now. Your log is saved on this iPhone.")
        case .restricted?: String(localized: "iCloud is restricted on this iPhone (for example by Screen Time).")
        case .temporarilyUnavailable?: String(localized: "iCloud is temporarily unavailable. Check Settings.")
        default: String(localized: "Sign in to iCloud in Settings to back up and share your log.")
        }
    }

    private func refresh() async {
        status = (try? await persistence.cloudKitContainer.accountStatus()) ?? .couldNotDetermine
    }
}

/// Shows Apple's sharing screen (invite by Messages, Mail, link, etc.).
///
/// `UICloudSharingController` must be presented modally by UIKit. Wrapped in a SwiftUI sheet it
/// can't present Messages or Mail properly and the invitation spins forever.
@MainActor
enum CloudSharingPresenter {
    /// The controller only holds its delegate weakly, so keep it alive while it's on screen.
    private static var activeDelegate: Delegate?

    static func present(share: CKShare, container: CKContainer, title: String,
                        onChange: @escaping (Result<Void, Error>) -> Void) {
        guard let presenter = topViewController() else { return }
        let delegate = Delegate(title: title, onChange: onChange)
        activeDelegate = delegate

        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.delegate = delegate
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true)
    }

    /// The front-most view controller in the active window.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onChange: (Result<Void, Error>) -> Void

        init(title: String, onChange: @escaping (Result<Void, Error>) -> Void) {
            self.title = title
            self.onChange = onChange
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            title
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            UIImage(named: "WelcomeArt")?.jpegData(compressionQuality: 0.6)
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onChange(.failure(error))
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share {
                PersistenceController.shared.persistUpdatedShare(share)
            }
            onChange(.success(()))
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // A participant who leaves removes the shared baby from their device.
            if let share = csc.share, share.currentUserParticipant != share.owner {
                PersistenceController.shared.removeSharedData(for: share)
            }
            onChange(.success(()))
        }
    }
}

/// What the share sheet sends: an iCloud invitation to one baby's log.
nonisolated struct BabyShareItem: Transferable {
    let objectID: NSManagedObjectID
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let persistence = PersistenceController.shared
            let container = persistence.cloudKitContainer
            // Already shared: let the owner invite more people to the same share.
            if let share = persistence.existingShare(forObjectWith: item.objectID) {
                return .existing(share, container: container)
            }
            // Not shared yet: the system calls this once a way to send it is picked.
            return .prepareShare(container: container) {
                try await persistence.makeShare(forObjectWith: item.objectID, title: item.title)
            }
        }
    }
}
