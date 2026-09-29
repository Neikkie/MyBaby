import AppIntents
import CloudKit
import CoreData
import SwiftUI
import UserNotifications

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let persistence = PersistenceController.shared

    init() {
        LegacyImport.runIfNeeded(PersistenceController.shared)
        ScreenshotData.seedIfRequested(PersistenceController.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(\.managedObjectContext, persistence.viewContext)
        .onChange(of: scenePhase) { _, phase in
            // Core Data doesn't autosave; make sure nothing is left unsaved when leaving.
            if phase != .active { persistence.save() }
            // Refresh baby names Siri listens for ("Mia woke up").
            if phase == .active { BabyShortcuts.updateAppShortcutParameters() }
        }
    }
}

/// Lets feed reminders appear while the app is open, and routes accepted iCloud shares.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Receives the invitation when a partner taps a shared baby log link.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        PersistenceController.shared.acceptShare(cloudKitShareMetadata)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // An invitation that launched the app.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            PersistenceController.shared.acceptShare(metadata)
        }
    }
}
