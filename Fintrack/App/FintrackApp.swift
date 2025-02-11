import SwiftUI
import FirebaseCore
import BackgroundTasks
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

@main
struct FintrackApp: App {
    @StateObject private var newsViewModel = NewsViewModel.shared
    @StateObject private var authViewModel = AuthViewModel.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(newsViewModel)
                .task {
                    if newsViewModel.news.isEmpty {
                        await newsViewModel.initialFetchAndSetup()
                    }
                }
        }
    }
} 
