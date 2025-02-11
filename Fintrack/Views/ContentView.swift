import SwiftUI
import FintrackModels
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showLoginView = false
    @State private var selectedTab: Tab = .news
    @State private var showAssetDetail: Bool = false
    @State private var selectedAssetSymbol: String?
    @State private var isLoading = true
    
    init() {
        setupNotificationHandlers()
        // Force full screen style for iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            UIWindow.appearance().windowScene?.sizeRestrictions?.minimumSize = CGSize(width: 768, height: 1024)
            UIWindow.appearance().windowScene?.sizeRestrictions?.maximumSize = CGSize(width: 768, height: 1024)
        }
    }
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView()
                    .onAppear {
                        // Simulate a short loading time
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation {
                                isLoading = false
                            }
                        }
                    }
            } else if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
    
    private func setupNotificationHandlers() {
        // Handle asset detail navigation
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenAssetDetail"),
            object: nil,
            queue: .main
        ) { notification in
            if let symbol = notification.userInfo?["symbol"] as? String {
                selectedAssetSymbol = symbol
                showAssetDetail = true
            }
        }
        
        // Handle news tab navigation
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenNewsTab"),
            object: nil,
            queue: .main
        ) { _ in
            selectedTab = .news
        }
    }
}

// Custom modifier for iPad
struct iPadModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.defaultMinListRowHeight, 50)
    }
}

// View extension to conditionally apply modifiers
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

enum Tab {
    case portfolio
    case search
    case news
    case profile
} 
