import UIKit
import SwiftUI
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    // Add custom view controller for orientation control
    class PortraitHostingController<Content: View>: UIHostingController<Content> {
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            // Allow all orientations for iPad, portrait only for iPhone
            if UIDevice.current.userInterfaceIdiom == .pad {
                return .all
            }
            return .portrait
        }
        
        override var prefersHomeIndicatorAutoHidden: Bool {
            return false
        }
        
        override func viewDidLoad() {
            super.viewDidLoad()
            
            // Force full screen style for iPad
            if UIDevice.current.userInterfaceIdiom == .pad {
                // Remove split view behavior
                if let splitVC = splitViewController {
                    splitVC.preferredDisplayMode = .secondaryOnly
                    splitVC.presentsWithGesture = false
                }
                
                // Force navigation style
                if let navController = navigationController {
                    navController.navigationBar.prefersLargeTitles = true
                    navController.setNavigationBarHidden(false, animated: false)
                }
                
                // Disable slide over and split view
                if #available(iOS 13.0, *) {
                    self.modalPresentationStyle = .fullScreen
                    self.navigationController?.modalPresentationStyle = .fullScreen
                }
            }
        }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Configure Firebase if not already configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        // Set messaging delegate
        Messaging.messaging().delegate = NotificationManager.shared
        
        // Lock orientation based on device type
        if UIDevice.current.userInterfaceIdiom == .phone {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        
        // Create window with full screen style
        let window = UIWindow(windowScene: windowScene)
        let contentView = ContentView()
        let rootViewController = PortraitHostingController(rootView: contentView)
        
        // Force full screen on iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            rootViewController.modalPresentationStyle = .fullScreen
            
            // Additional iPad settings
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
            window.windowScene?.sizeRestrictions?.minimumSize = CGSize(width: 768, height: 1024)
            window.windowScene?.sizeRestrictions?.maximumSize = CGSize(width: 768, height: 1024)
        }
        
        window.rootViewController = rootViewController
        self.window = window
        window.makeKeyAndVisible()
        
        // Handle notification if app was launched from notification
        if let notification = connectionOptions.notificationResponse {
            handleNotification(response: notification)
        }
    }
    
    private func handleNotification(response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        if let type = userInfo["type"] as? String {
            switch type {
            case "STOCK_NEWS":
                if let articleId = userInfo["article_id"] as? String {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenNewsDetail"),
                        object: nil,
                        userInfo: ["article_id": articleId]
                    )
                }
            case "PRICE_CHANGE":
                if let symbol = userInfo["symbol"] as? String {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenAssetDetail"),
                        object: nil,
                        userInfo: ["symbol": symbol]
                    )
                }
            default:
                break
            }
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when the scene is being released by the system
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        AuthViewModel.shared.updateUserActiveStatus()
        
        // Sync badge count when app becomes active
        if Auth.auth().currentUser != nil {
            Task {
                await NotificationManager.shared.syncBadgeCount()
            }
        }
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        // Clear badge count when app becomes inactive
        if Auth.auth().currentUser != nil {
            Task { @MainActor in
                UIApplication.shared.applicationIconBadgeNumber = 0
                await NotificationManager.shared.syncBadgeCount()
            }
        }
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background
        guard Auth.auth().currentUser != nil else { return }
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground
    }
    
    // Add orientation lock support
    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace, interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation, traitCollection previousTraitCollection: UITraitCollection) {
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
} 
