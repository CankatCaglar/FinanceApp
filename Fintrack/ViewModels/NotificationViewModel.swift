import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
class NotificationViewModel: ObservableObject {
    static let shared = NotificationViewModel()
    
    @Published var badgeCount: Int = 0
    private var lastSeenArticleIds: Set<Int> = []
    
    private init() {
        // Load last seen article IDs from UserDefaults
        if let savedIds = UserDefaults.standard.array(forKey: "lastSeenArticleIds") as? [Int] {
            lastSeenArticleIds = Set(savedIds)
        }
        
        // Load current badge count
        badgeCount = UIApplication.shared.applicationIconBadgeNumber
        
        // Add observers for app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppBecameActive() {
        Task { @MainActor in
            // Reset badge count when app becomes active
            updateBadgeCount(0)
        }
    }
    
    @objc private func handleAppEnteredBackground() {
        Task { @MainActor in
            // Save current badge count when app enters background
            UserDefaults.standard.set(badgeCount, forKey: "lastBadgeCount")
        }
    }
    
    func updateBadgeCount(_ count: Int) {
        badgeCount = count
        UIApplication.shared.applicationIconBadgeNumber = count
    }
    
    func incrementBadgeCount() {
        // Only increment badge if app is in background
        guard UIApplication.shared.applicationState != .active else {
            return
        }
        
        badgeCount += 1
        UIApplication.shared.applicationIconBadgeNumber = badgeCount
    }
    
    func markArticleAsSeen(_ articleId: Int) {
        lastSeenArticleIds.insert(articleId)
        UserDefaults.standard.set(Array(lastSeenArticleIds), forKey: "lastSeenArticleIds")
    }
    
    func isArticleSeen(_ articleId: Int) -> Bool {
        return lastSeenArticleIds.contains(articleId)
    }
} 