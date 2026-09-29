import CloudKit
@preconcurrency import CoreData
import Foundation

/// The Core Data stack shared by the app, its widgets and its App Intents.
///
/// Two stores live in the App Group container so the widget extension can read them:
/// - **Private**: your babies and entries, mirrored to your private iCloud database.
/// - **Shared**: babies other people have shared with you, mirrored to the shared database.
///
/// Only the app itself talks to CloudKit. The widget opens the same files without CloudKit,
/// and the app picks up anything the widget writes through persistent history.
nonisolated final class PersistenceController: @unchecked Sendable {
    // IMPORTANT: When you set your real bundle identifier, update these two values and the
    // matching entries in both targets' entitlements (Signing & Capabilities).
    static let appGroupID = "group.com.chaniiappsllc.MyBaby"
    static let cloudKitContainerID = "iCloud.com.chaniiappsllc.MyBaby"

    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    /// False when iCloud isn't available (e.g. no account); everything still works locally.
    private(set) var isCloudKitEnabled = false

    private var historyToken: NSPersistentHistoryToken?
    private var remoteChangeObserver: NSObjectProtocol?
    private let historyQueue = DispatchQueue(label: "MyBaby.history")

    var viewContext: NSManagedObjectContext { container.viewContext }

    var cloudKitContainer: CKContainer { CKContainer(identifier: Self.cloudKitContainerID) }

    private static var isExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    private var author: String { Self.isExtension ? "widget" : "app" }

    init(inMemory: Bool = false) {
        let wantsCloudKit = !inMemory && !Self.isExtension
        var loaded = Self.makeContainer(inMemory: inMemory, cloudKit: wantsCloudKit)
        if loaded.failed, wantsCloudKit {
            // iCloud or the entitlements aren't available; keep working with local stores.
            loaded = Self.makeContainer(inMemory: inMemory, cloudKit: false)
        }
        container = loaded.container
        isCloudKitEnabled = wantsCloudKit && !loaded.failed
        privateStore = loaded.privateStore
        sharedStore = loaded.sharedStore

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = author

        if !inMemory {
            startObservingOtherProcesses()
        }

        #if DEBUG
        if isCloudKitEnabled {
            initializeCloudKitSchemaIfNeeded()
        }
        #endif
    }

    #if DEBUG
    /// Development builds only: uploads every record type and field to CloudKit's Development
    /// environment, once per model change. After it runs, open the CloudKit Console and choose
    /// "Deploy Schema Changes…" so TestFlight and App Store builds (Production) can sync and share.
    private func initializeCloudKitSchemaIfNeeded() {
        let version = BabyDataModel.model.entityVersionHashesByName
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.base64EncodedString())" }
            .joined(separator: "|")
        let key = "cloudKitSchemaVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        let container = container
        DispatchQueue.global(qos: .utility).async {
            do {
                try container.initializeCloudKitSchema(options: [])
                UserDefaults.standard.set(version, forKey: key)
                print("✅ CloudKit schema uploaded to Development. Now deploy it to Production in the CloudKit Console.")
            } catch {
                print("⚠️ CloudKit schema upload failed: \(error)")
            }
        }
    }
    #endif

    // MARK: Setup

    private static func makeContainer(inMemory: Bool, cloudKit: Bool)
        -> (container: NSPersistentCloudKitContainer, privateStore: NSPersistentStore?, sharedStore: NSPersistentStore?, failed: Bool)
    {
        let container = NSPersistentCloudKitContainer(name: "MyBaby", managedObjectModel: BabyDataModel.model)
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? NSPersistentContainer.defaultDirectoryURL()

        func description(file: String, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
            let description = NSPersistentStoreDescription(url: inMemory
                ? URL(filePath: "/dev/null").appending(path: file)
                : directory.appending(path: file))
            if inMemory { description.type = NSInMemoryStoreType }
            description.shouldAddStoreAsynchronously = false
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if cloudKit {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
                options.databaseScope = scope
                description.cloudKitContainerOptions = options
            } else {
                description.cloudKitContainerOptions = nil
            }
            return description
        }

        let privateDescription = description(file: "MyBaby-private.sqlite", scope: .private)
        let sharedDescription = description(file: "MyBaby-shared.sqlite", scope: .shared)
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var failed = false
        container.loadPersistentStores { _, error in
            if error != nil { failed = true }
        }

        let coordinator = container.persistentStoreCoordinator
        let privateStore = privateDescription.url.flatMap { coordinator.persistentStore(for: $0) }
        let sharedStore = sharedDescription.url.flatMap { coordinator.persistentStore(for: $0) }
        return (container, privateStore, sharedStore, failed || privateStore == nil)
    }

    // MARK: Saving

    /// Saves pending changes on the main context, if there are any.
    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }

    // MARK: Changes from other processes

    /// Merges changes the widget (or an intent) saved while this process was running.
    private func startObservingOtherProcesses() {
        historyToken = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            self?.historyQueue.async { self?.mergeNewHistory() }
        }
    }

    private func mergeNewHistory() {
        let context = container.newBackgroundContext()
        let token = historyToken
        let author = author
        // Read the new history and collect the IDs of objects other processes changed.
        let (latestToken, changes): (NSPersistentHistoryToken?, [AnyHashable: Any]) = context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  let last = transactions.last
            else { return (nil, [:]) }

            var inserted: [NSManagedObjectID] = []
            var updated: [NSManagedObjectID] = []
            var deleted: [NSManagedObjectID] = []
            // Our own saves are already in the main context.
            for transaction in transactions where transaction.author != author {
                for change in transaction.changes ?? [] {
                    switch change.changeType {
                    case .insert: inserted.append(change.changedObjectID)
                    case .update: updated.append(change.changedObjectID)
                    case .delete: deleted.append(change.changedObjectID)
                    @unknown default: break
                    }
                }
            }
            return (last.token, [NSInsertedObjectsKey: inserted, NSUpdatedObjectsKey: updated, NSDeletedObjectsKey: deleted])
        }
        guard let latestToken else { return }
        historyToken = latestToken
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
    }

    // MARK: Sharing

    /// The CloudKit share a baby belongs to, if any.
    func existingShare(for object: NSManagedObject) -> CKShare? {
        existingShare(forObjectWith: object.objectID)
    }

    func existingShare(forObjectWith id: NSManagedObjectID) -> CKShare? {
        (try? container.fetchShares(matching: [id]))?[id]
    }

    /// True when someone else shared this baby with you.
    func isFromSomeoneElse(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }

    func isShared(_ object: NSManagedObject) -> Bool {
        isFromSomeoneElse(object) || existingShare(for: object) != nil
    }

    /// Whether the current person can change this object (read-only participants can't).
    func canEdit(_ object: NSManagedObject) -> Bool {
        container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    /// Creates a share for a baby and everything logged for them.
    /// Creates the share for the system share sheet (Messages, Mail, AirDrop, Copy Link…).
    @MainActor
    func makeShare(forObjectWith id: NSManagedObjectID, title: String) async throws -> CKShare {
        let object = try viewContext.existingObject(with: id)
        let (_, share, _) = try await container.share([object], to: nil)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        // Finish saving the title before Messages sends the link, so the invite is complete.
        if let privateStore {
            _ = try? await container.persistUpdatedShare(share, in: privateStore)
        }
        return share
    }

    func makeShare(for baby: Baby) async throws -> (CKShare, CKContainer) {
        let (_, share, ckContainer) = try await container.share([baby], to: nil)
        share[CKShare.SystemFieldKey.title] = "\(baby.displayName)'s Baby Log" as CKRecordValue
        return (share, ckContainer)
    }

    /// Saves changes the system sharing UI made to a share.
    func persistUpdatedShare(_ share: CKShare) {
        let isOwner = share.currentUserParticipant == share.owner
        guard let store = isOwner ? privateStore : sharedStore else { return }
        container.persistUpdatedShare(share, in: store, completion: nil)
    }

    /// Deletes a baby and everything logged for them.
    ///
    /// - Your own baby: deleted here, on your other devices and, if shared, for everyone on the share.
    /// - A baby someone shared with you: only removed from your devices. Their log stays intact.
    @MainActor
    func delete(_ baby: Baby) async {
        let share = existingShare(for: baby)
        if isFromSomeoneElse(baby) {
            if let share { removeSharedData(for: share) }
            return
        }
        viewContext.delete(baby)   // Entries, measurements and schedule go with it (cascade).
        save()
        // Also remove the share and its iCloud zone so invited people lose access.
        if let share, let privateStore {
            container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: privateStore, completion: nil)
        }
    }

    /// Accepts an invitation someone sent, adding their baby to the shared store.
    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore, completion: nil)
    }

    /// After you leave someone else's share, remove their baby from this device.
    func removeSharedData(for share: CKShare) {
        guard let sharedStore else { return }
        container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore, completion: nil)
    }
}

/// Which baby is currently shown. Stored in the App Group so widgets follow the same baby.
nonisolated enum SelectedBaby {
    static let storageKey = "selectedBabyID"
    private static var key: String { storageKey }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: PersistenceController.appGroupID) ?? .standard
    }

    static var id: UUID? {
        get { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: key) }
    }

    /// The selected baby, falling back to the first one.
    static func resolve(in context: NSManagedObjectContext) -> Baby? {
        let babies = (try? context.fetch(Baby.fetchAll())) ?? []
        if let id, let match = babies.first(where: { $0.babyID == id }) { return match }
        return babies.first
    }
}
