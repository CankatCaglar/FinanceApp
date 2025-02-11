import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import FirebaseMessaging

@MainActor
public class NewsViewModel: ObservableObject {
    public static let shared = NewsViewModel()
    
    @Published private(set) var newsItems: [NewsCategory: [NewsItem]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var selectedCategory: NewsCategory = .all {
        didSet {
            news = newsItems[selectedCategory] ?? []
        }
    }
    @Published var news: [NewsItem] = []
    
    private var processedArticleIds: Set<Int> = []
    private var lastFetchTimestamp: Timestamp?
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var refreshTask: Task<Void, Never>?
    
    private init() {
        // Initialize empty arrays for each category
        NewsCategory.allCases.forEach { category in
            newsItems[category] = []
        }
        
        // Initial fetch and setup
        Task {
            await initialFetchAndSetup()
        }
        
        // Add notification center observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Register for remote notifications
        registerForRemoteNotifications()
    }
    
    deinit {
        listener?.remove()
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        
        Task { @MainActor in
            self.newsItems.removeAll()
            self.news.removeAll()
            self.error = nil
        }
    }
    
    @objc private func handleDidBecomeActive() {
        Task {
            // Remove old listener
            listener?.remove()
            
            // Instead of clearing processedArticleIds, we'll keep track of existing IDs
            let existingIds = Set(newsItems.values.flatMap { $0 }.map { $0.id })
            processedArticleIds = existingIds
            
            // Refresh news and setup new listener
            await initialFetchAndSetup()
        }
    }
    
    @objc private func handleDidEnterBackground() {
        // Remove listener when app goes to background
        listener?.remove()
        listener = nil
    }
    
    public func initialFetchAndSetup() async {
        do {
            // Clear news items before fetching
            await MainActor.run {
                self.newsItems = [:]
                NewsCategory.allCases.forEach { category in
                    self.newsItems[category] = []
                }
            }
            
            try await fetchInitialNews()
            setupNewsListener()
        } catch {
            print("❌ Error in initial fetch and setup: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    public func fetchInitialNews() async throws {
        isLoading = true
        error = nil
        
        do {
            let newsRef = db.collection("news")
            
            let query = newsRef
                .order(by: "publishedAt", descending: true)
                .limit(to: 100)
            
            let snapshot = try await query.getDocuments()
            
            var fetchedNews: [NewsItem] = []
            for document in snapshot.documents {
                if let newsItem = parseNewsDocument(document) {
                    fetchedNews.append(newsItem)
                }
            }
            
            // Update the UI
            await MainActor.run {
                // Update category-based collections
                var updatedNews = [NewsCategory: [NewsItem]]()
                var processedIds = Set<Int>()
                
                // First, sort all news by date
                let sortedNews = fetchedNews.sorted { $0.publishedAt > $1.publishedAt }
                
                // Process each article
                for article in sortedNews {
                    if !processedIds.contains(article.id) {
                        processedIds.insert(article.id)
                        // Add to its specific category (stocks or crypto)
                        updatedNews[article.category, default: []].append(article)
                    }
                }
                
                // Create "All" category by combining unique articles
                var allArticles: [NewsItem] = []
                for (_, articles) in updatedNews {
                    allArticles.append(contentsOf: articles)
                }
                
                // Sort all articles by date
                updatedNews[.all] = allArticles.sorted { $0.publishedAt > $1.publishedAt }
                
                self.newsItems = updatedNews
                self.news = updatedNews[self.selectedCategory] ?? []
                self.lastFetchTimestamp = Timestamp(date: Date())
                self.error = nil
                self.isLoading = false
            }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            throw error
        }
    }
    
    private func setupNewsListener() {
        listener?.remove()
        
        print("🔄 Setting up news listener...")
        
        // Son 24 saatlik haberleri dinle
        let oneDayAgo = Timestamp(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        
        listener = db.collection("news")
            .whereField("publishedAt", isGreaterThan: oneDayAgo)
            .order(by: "publishedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to news updates:", error)
                    self.error = error.localizedDescription
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                print("📱 Received \(documents.count) news items")
                
                Task {
                    await self.processNewsDocuments(documents)
                }
            }
        
        print("📡 News listener setup completed")
    }
    
    private func processNewsDocuments(_ documents: [QueryDocumentSnapshot]) async {
        var newArticles: [NewsItem] = []
        
        for document in documents {
            if let newsItem = parseNewsDocument(document) {
                // Skip if we've already processed this article
                guard !processedArticleIds.contains(newsItem.id) else {
                    print("⏩ Skipping duplicate article: \(newsItem.id)")
                    continue
                }
                
                processedArticleIds.insert(newsItem.id)
                newArticles.append(newsItem)
                print("📰 Processing new article: \(newsItem.id) - \(newsItem.headline)")
            }
        }
        
        guard !newArticles.isEmpty else { return }
        
        // Sort new articles by date
        let sortedArticles = newArticles.sorted { $0.publishedAt > $1.publishedAt }
        
        // Update categories
        var updatedNews = newsItems
        
        // First, update specific categories (stocks or crypto)
        for article in sortedArticles {
            updatedNews[article.category, default: []].insert(article, at: 0)
        }
        
        // Then, create "All" category by combining all articles
        var allArticles = updatedNews.values.flatMap { $0 }
        
        // Sort all articles by date and ensure uniqueness
        let uniqueAllArticles = Array(Set(allArticles)).sorted { $0.publishedAt > $1.publishedAt }
        updatedNews[.all] = uniqueAllArticles
        
        // Sort and limit each category
        for (category, articles) in updatedNews {
            updatedNews[category] = Array(Set(articles))
                .sorted { $0.publishedAt > $1.publishedAt }
                .prefix(100)
                .map { $0 }
        }
        
        // Update UI
        await MainActor.run {
            self.newsItems = updatedNews
            self.news = updatedNews[self.selectedCategory] ?? []
            self.error = nil
        }
        
        print("📊 Updated news counts:")
        for (category, articles) in updatedNews {
            print("  \(category): \(articles.count) unique items")
        }
    }
    
    private func parseNewsDocument(_ document: QueryDocumentSnapshot) -> NewsItem? {
        let data = document.data()
        
        // Extract id - try multiple approaches
        let id: Int
        if let idInt = data["id"] as? Int {
            id = idInt
        } else if let idString = data["id"] as? String,
                  let parsedId = Int(idString) {
            id = parsedId
        } else if let docId = Int(document.documentID.replacingOccurrences(of: " ", with: "_")) {
            id = docId
        } else {
            print("❌ Could not parse id for document \(document.documentID)")
            return nil
        }
        
        // Extract required string fields with fallbacks
        guard let headline = (data["headline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !headline.isEmpty else {
            print("❌ Missing or empty headline for news item \(id)")
            return nil
        }
        
        let summary = (data["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? headline
        let url = (data["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = (data["source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
        
        // Handle timestamp with fallback
        let publishedAt: Date
        if let timestamp = data["publishedAt"] as? Timestamp {
            publishedAt = timestamp.dateValue()
        } else {
            print("⚠️ Warning: Missing timestamp for news item \(id), skipping")
            return nil
        }
        
        // Handle category
        let categoryStr = (data["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "stocks"
        let category = NewsCategory(firestoreString: categoryStr) ?? .stocks
        
        // Create NewsItem
        return NewsItem(
            id: id,
            headline: headline,
            summary: summary,
            url: url,
            source: source,
            imageUrl: data["imageUrl"] as? String ?? "",
            publishedAt: publishedAt,
            category: category
        )
    }
    
    func changeCategory(_ category: NewsCategory) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        news = newsItems[category] ?? []
    }
    
    // Yeni refresh metodu
    public func refreshNews() async {
        do {
            try await fetchInitialNews()
            setupNewsListener()
        } catch {
            print("❌ Error refreshing news:", error)
        }
    }
    
    private func registerForRemoteNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Enable notifications in Firestore for this user
                if let userId = Auth.auth().currentUser?.uid {
                    Task {
                        do {
                            try await self.db.collection("users").document(userId).setData([
                                "notificationsEnabled": true
                            ], merge: true)
                            print("✅ Notifications enabled for user")
                        } catch {
                            print("❌ Error enabling notifications:", error)
                        }
                    }
                }
            }
        }
    }
    
    // Handle remote notification received while app is in background
    public func handleRemoteNews(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String,
              type == "news" else { return }
        
        Task {
            await initialFetchAndSetup()
        }
    }
    
    // Reset badge count when app becomes active
    public func resetBadgeCount() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        // Reset badge count in Firestore
        if let userId = Auth.auth().currentUser?.uid {
            Task {
                do {
                    try await self.db.collection("users").document(userId).setData([
                        "badgeCount": 0
                    ], merge: true)
                    print("✅ Badge count reset")
                } catch {
                    print("❌ Error resetting badge count:", error)
                }
            }
        }
    }
}

extension NewsItem: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: NewsItem, rhs: NewsItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - NewsItem Firestore Extension
extension NewsItem {
    init(from document: QueryDocumentSnapshot) throws {
        let data = document.data()
        
        guard let id = data["id"] as? Int,
              let headline = data["headline"] as? String,
              let summary = data["summary"] as? String,
              let url = data["url"] as? String,
              let source = data["source"] as? String,
              let publishedAt = (data["publishedAt"] as? Timestamp)?.dateValue(),
              let categoryStr = data["category"] as? String,
              let categoriesStrings = data["categories"] as? [String] else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid news data"])
        }
        
        guard let category = NewsCategory(firestoreString: categoryStr) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid category: \(categoryStr)"])
        }
        
        self.id = id
        self.headline = headline
        self.summary = summary
        self.url = url
        self.source = source
        self.imageUrl = data["imageUrl"] as? String
        self.publishedAt = publishedAt
        self.category = category
        self.categories = categoriesStrings.compactMap { NewsCategory(firestoreString: $0) }
    }
}


