import CloudKit
import CoreData
import SwiftUI
import UIKit

/// Settings section for sharing a baby's log with a partner or caregiver through iCloud.
struct SharingSection: View {
    @ObservedObject var baby: Baby

    @State private var sharingItem: SharingItem?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    /// Bumped after the sharing screen closes so the status refreshes.
    @State private var refresh = 0

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
            if isFromSomeoneElse {
                LabeledContent("Shared by", value: share.map { Self.name(of: $0.owner) } ?? "Someone else")
                Button("Manage or Leave", systemImage: "person.2.badge.gearshape") {
                    Task { await openSharing() }
                }
            } else {
                Button {
                    Task { await openSharing() }
                } label: {
                    HStack {
                        Label(share == nil ? "Share \(baby.displayName)'s Log" : "Manage Sharing", systemImage: "person.2.fill")
                        Spacer()
                        if isPreparing { ProgressView() }
                    }
                }
                .disabled(isPreparing)

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
        .sheet(item: $sharingItem, onDismiss: { refresh += 1 }) { item in
            CloudSharingView(share: item.share, container: item.container, baby: baby)
                .ignoresSafeArea()
        }
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
            sharingItem = SharingItem(share: share, container: persistence.cloudKitContainer)
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let (share, container) = try await persistence.makeShare(for: baby)
            sharingItem = SharingItem(share: share, container: container)
        } catch {
            errorMessage = "Couldn't start sharing. Check your connection and try again."
        }
    }

    static func name(of participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? "Invited person"
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

struct SharingItem: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Apple's standard sharing screen for inviting people and managing access.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let baby: Baby

    func makeCoordinator() -> Coordinator {
        Coordinator(title: "\(baby.displayName)'s Baby Log")
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        share[CKShare.SystemFieldKey.title] = context.coordinator.title as CKRecordValue
        let controller = UICloudSharingController(share: share, container: container)
        controller.modalPresentationStyle = .formSheet
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String

        init(title: String) {
            self.title = title
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            title
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            UIImage(named: "WelcomeArt")?.jpegData(compressionQuality: 0.6)
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share {
                PersistenceController.shared.persistUpdatedShare(share)
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // A participant who leaves removes the shared baby from their device.
            guard let share = csc.share else { return }
            if share.currentUserParticipant != share.owner {
                PersistenceController.shared.removeSharedData(for: share)
            }
        }
    }
}
