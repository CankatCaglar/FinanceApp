import Foundation
import Network

class NewsService {
    static let shared = NewsService()
    // Finnhub API key
    private let apiKey = "cudqf91r01qiosq0svdgcudqf91r01qiosq0sve0"
    private let baseURL = "https://finnhub.io/api/v1"
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = path.status == .satisfied
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    func fetchNews(category: NewsCategory = .all) async throws -> [NewsItem] {
        guard isNetworkAvailable else {
            throw URLError(.notConnectedToInternet)
        }
        
        switch category {
        case .all:
            var allNews: [NewsItem] = []
            
            // Fetch crypto news
            do {
                let cryptoNews = try await fetchNewsFromEndpoint("/news?category=crypto&limit=20")
                allNews.append(contentsOf: cryptoNews.map { news in
                    var modifiedNews = news
                    modifiedNews.category = .crypto
                    return modifiedNews
                })
            } catch {
                print("Failed to fetch crypto news: \(error.localizedDescription)")
            }
            
            // Fetch stock news
            do {
                let stockNews = try await fetchNewsFromEndpoint("/news?category=forex&limit=20")
                allNews.append(contentsOf: stockNews.map { news in
                    var modifiedNews = news
                    modifiedNews.category = .stocks
                    return modifiedNews
                })
            } catch {
                print("Failed to fetch stock news: \(error.localizedDescription)")
            }
            
            // If no news was fetched at all, throw an error
            guard !allNews.isEmpty else {
                throw NSError(domain: "NewsService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to fetch any news"
                ])
            }
            
            // Sort by date and return all news
            return allNews.sorted { $0.publishedAt > $1.publishedAt }
            
        case .crypto:
            let news = try await fetchNewsFromEndpoint("/news?category=crypto&limit=20")
            return news.map { item in
                var modifiedNews = item
                modifiedNews.category = .crypto
                return modifiedNews
            }
            
        case .stocks:
            let news = try await fetchNewsFromEndpoint("/news?category=forex&limit=20")
            return news.map { item in
                var modifiedNews = item
                modifiedNews.category = .stocks
                return modifiedNews
            }
        }
    }
    
    private func fetchNewsFromEndpoint(_ endpoint: String) async throws -> [NewsItem] {
        let urlString = "\(baseURL)\(endpoint)" + (endpoint.contains("?") ? "&" : "?") + "token=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        print("📡 Fetching news from: \(urlString)")
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 429 {
                throw NSError(domain: "NewsService", code: 429, userInfo: [
                    NSLocalizedDescriptionKey: "API rate limit exceeded. Please try again later."
                ])
            }
            
            guard httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            struct FinnhubNewsItem: Codable {
                let category: String
                let datetime: TimeInterval
                let headline: String
                let id: Int
                let image: String?
                let related: String
                let source: String
                let summary: String
                let url: String
            }
            
            let decoder = JSONDecoder()
            let finnhubNews = try decoder.decode([FinnhubNewsItem].self, from: data)
            
            guard !finnhubNews.isEmpty else {
                throw NSError(domain: "NewsService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No news available for this category"
                ])
            }
            
            // Determine the category based on the endpoint
            let category: NewsCategory
            if endpoint.contains("category=crypto") {
                category = .crypto
            } else if endpoint.contains("category=forex") {
                category = .stocks
            } else {
                category = .all
            }
            
            return finnhubNews.map { item in
                NewsItem(
                    id: item.id,
                    headline: item.headline,
                    summary: item.summary,
                    url: item.url,
                    source: item.source,
                    imageUrl: item.image,
                    publishedAt: Date(timeIntervalSince1970: item.datetime),
                    category: category // Use the determined category
                )
            }
        } catch {
            print("❌ Error fetching news from \(endpoint): \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                print("🔍 Decoding error details: \(decodingError)")
            }
            throw error
        }
    }
} 