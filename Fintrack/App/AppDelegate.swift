import UIKit
import Firebase
import FirebaseAuth
import CoreData
import BackgroundTasks
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import Network

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    var window: UIWindow?
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Set messaging delegate early
        Messaging.messaging().delegate = self
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Setup network monitoring
        setupNetworkMonitoring()
        
        // Disable iPad slide over and split view features
        if UIDevice.current.userInterfaceIdiom == .pad {
            application.delegate?.window??.overrideUserInterfaceStyle = .light
        }
        
        return true
    }

    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            self?.isNetworkAvailable = isAvailable
            
            DispatchQueue.main.async {
                if isAvailable {
                    // Reconnect to Firebase services
                    self?.reconnectFirebaseServices()
                }
            }
        }
        
        networkMonitor?.start(queue: queue)
    }
    
    private func reconnectFirebaseServices() {
        // Reconnect Firestore
        let db = Firestore.firestore()
        db.enableNetwork { error in
            if let error = error {
                print("❌ Error reconnecting to Firestore: \(error)")
            }
        }
        
        // Refresh FCM token
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ Error refreshing FCM token: \(error)")
            } else if let token = token {
                UserDefaults.standard.set(token, forKey: "fcmToken")
                AuthViewModel.shared.updateUserActiveStatus()
            }
        }
    }

    // Force orientation based on device type
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    // MARK: - Remote Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("📱 APNS token set successfully")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        AuthViewModel.shared.updateUserActiveStatus()
        completionHandler(.newData)
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting scene: UIScene, willMigrateFrom fromScene: UIScene?, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: scene.session.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions are being discarded while the application is being created, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation creates and returns a container, having loaded the store for the application to it. This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
         */
        let container = NSPersistentContainer(name: "Fintrack")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving support

    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase registration token: \(String(describing: fcmToken))")
        
        if let token = fcmToken {
            UserDefaults.standard.set(token, forKey: "fcmToken")
            AuthViewModel.shared.updateUserActiveStatus()
        }
    }

    // MARK: - UNUserNotificationCenter Delegate Methods
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // Handle news notification
        if let type = userInfo["type"] as? String,
           type == "news" {
            Task {
                await NewsViewModel.shared.initialFetchAndSetup()
            }
        }
        
        // Show banner and play sound
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle news notification
        if let type = userInfo["type"] as? String,
           type == "news" {
            Task {
                await NewsViewModel.shared.initialFetchAndSetup()
            }
        }
        
        completionHandler()
    }

} 