import Foundation
import UserNotifications
import UIKit
import FirebaseAuth
import FirebaseMessaging
import FirebaseFirestore

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationManager()
    let notificationCenter = UNUserNotificationCenter.current()
    private let db = Firestore.firestore()
    
    @Published var isNotificationsEnabled: Bool = false
    
    private override init() {
        super.init()
        notificationCenter.delegate = self
        Messaging.messaging().delegate = self
        
        Task {
            await checkNotificationStatus()
        }
    }
    
    // MARK: - Firebase Messaging Delegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM token received: \(fcmToken ?? "nil")")
        
        guard let token = fcmToken else {
            print("❌ No FCM token available")
            return
        }
        
        // Save token to UserDefaults
        UserDefaults.standard.set(token, forKey: "fcmToken")
        
        // Update Firestore if user is authenticated
        if let userId = Auth.auth().currentUser?.uid {
            Task {
                do {
                    try await db.collection("users").document(userId).setData([
                        "fcmToken": token,
                        "lastTokenUpdate": FieldValue.serverTimestamp(),
                        "notificationsEnabled": true,
                        "platform": "iOS",
                        "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    ], merge: true)
                    
                    print("✅ FCM token updated successfully for user: \(userId)")
                } catch {
                    print("❌ Error updating FCM token: \(error)")
                }
            }
        }
    }
    
    // MARK: - Notification Handling
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if Auth.auth().currentUser != nil {
            // Get badge count from notification
            if let badgeCount = notification.request.content.badge?.intValue {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
                
                // Update Firestore
                if let userId = Auth.auth().currentUser?.uid {
                    Task {
                        try? await db.collection("users").document(userId).updateData([
                            "badgeCount": badgeCount
                        ])
                    }
                }
            }
            
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([])
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle notification based on type
        if let type = userInfo["type"] as? String {
            handleNotification(type: type, userInfo: userInfo)
        }
        
        // Reset badge count when notification is opened
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Also update Firestore
        if let userId = Auth.auth().currentUser?.uid {
            Task {
                try? await db.collection("users").document(userId).updateData([
                    "badgeCount": 0,
                    "lastNotificationRead": FieldValue.serverTimestamp()
                ])
            }
        }
        
        completionHandler()
    }
    
    // MARK: - Public Methods
    
    func setupNotificationsAfterAuth() async {
        print("📱 Setting up notifications")
        
        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus == .authorized {
            await MainActor.run {
                isNotificationsEnabled = true
                // Don't call registerForRemoteNotifications here, it's handled in AppDelegate
            }
            
            // Reset badge count on setup
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
            
            // Update FCM token in Firestore if available
            if let token = try? await Messaging.messaging().token() {
                if let userId = Auth.auth().currentUser?.uid {
                    try? await db.collection("users").document(userId).setData([
                        "fcmToken": token,
                        "notificationsEnabled": true,
                        "lastTokenUpdate": FieldValue.serverTimestamp()
                    ], merge: true)
                }
            }
        } else {
            print("📱 Requesting notification authorization")
            let granted = try? await requestAuthorization()
            if granted == true {
                await MainActor.run {
                    isNotificationsEnabled = true
                    // Don't call registerForRemoteNotifications here
                }
            }
        }
    }
    
    private func checkNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        await MainActor.run {
            isNotificationsEnabled = settings.authorizationStatus == .authorized
        }
    }
    
    public func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await notificationCenter.requestAuthorization(options: options)
            await MainActor.run {
                self.isNotificationsEnabled = granted
            }
            
            if granted {
                await MainActor.run {
                    // Don't call registerForRemoteNotifications here
                }
            }
            
            return granted
        } catch {
            print("❌ Error requesting notification authorization: \(error)")
            return false
        }
    }
    
    func clearNotificationSetup() async {
        print("📱 Clearing notification setup")
        
        await MainActor.run {
            isNotificationsEnabled = false
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        
        // Remove FCM token from Firestore
        if let userId = Auth.auth().currentUser?.uid {
            do {
                try await db.collection("users").document(userId).updateData([
                    "fcmToken": FieldValue.delete(),
                    "notificationsEnabled": false
                ])
                print("✅ Cleared notification data in Firestore")
            } catch {
                print("❌ Error clearing FCM token: \(error)")
            }
        }
        
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
    
    // MARK: - Private Methods
    
    private func handleNotification(type: String, userInfo: [AnyHashable: Any]) {
        print("📱 Handling notification of type: \(type)")
        
        switch type {
        case "WELCOME":
            if let action = userInfo["action"] as? String, action == "OPEN_ONBOARDING" {
                NotificationCenter.default.post(name: NSNotification.Name("OpenOnboarding"), object: nil)
            }
            
        case "WELCOME_BACK":
            if let action = userInfo["action"] as? String, action == "OPEN_PORTFOLIO" {
                NotificationCenter.default.post(name: NSNotification.Name("OpenPortfolio"), object: nil)
            }
            
        case "NEWS":
            if let articleId = userInfo["articleId"] as? String {
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenNewsDetail"),
                    object: nil,
                    userInfo: ["articleId": articleId]
                )
            }
            
        default:
            print("⚠️ Unknown notification type: \(type)")
        }
    }
    
    // Add new method to sync badge count
    func syncBadgeCount() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            let badgeCount = userDoc.data()?["badgeCount"] as? Int ?? 0
            
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }
            
            print("📱 Badge count synced: \(badgeCount)")
        } catch {
            print("❌ Error syncing badge count:", error)
        }
    }
} 

