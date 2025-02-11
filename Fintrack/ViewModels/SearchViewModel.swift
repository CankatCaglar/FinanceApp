import Foundation
import Combine
import FintrackModels
import UIKit

@MainActor
class SearchViewModel: ObservableObject {
    static let shared = SearchViewModel()
    @Published var searchResults: [Asset] = []
    @Published var popularAssets: [Asset] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedAssetType: AssetType = .crypto {
        didSet {
            if oldValue != selectedAssetType {
                searchResults = []
                error = nil
                loadPopularAssets()
            }
        }
    }
    
    private var searchCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var cachedCryptos: [Asset] = []
    private var lastAPICallTime: Date?
    private let apiCallCooldown: TimeInterval = 2.0 // Minimum time between API calls
    
    // API URLs and Keys
    private let finnhubBaseURL = APIConstants.finnhubBaseURL
    private let cmcBaseURL = APIConstants.coinMarketCapBaseURL
    private let finnhubAPIKey = APIConstants.finnhubAPIKey
    private let cmcAPIKey = APIConstants.coinMarketCapAPIKey
    
    init() {
        loadPopularAssets()
        // Load more cryptos in background
        Task {
            await loadExtendedCryptoList()
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ""
        formatter.usesGroupingSeparator = false
        
        // For very small numbers (less than 0.01), show more decimal places
        if price < 0.01 {
            formatter.minimumFractionDigits = 8
            formatter.maximumFractionDigits = 8
        } else if price < 1.0 {
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        
        if let formattedPrice = formatter.string(from: NSNumber(value: price)) {
            return formattedPrice
        }
        return "0.00"
    }
    
    private func formatMarketCap(_ marketCap: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        if marketCap >= billion {
            return String(format: "%.2fB", marketCap / billion)
        } else if marketCap >= million {
            return String(format: "%.2fM", marketCap / million)
        } else if marketCap >= thousand {
            return String(format: "%.2fK", marketCap / thousand)
        } else {
            return String(format: "%.2f", marketCap)
        }
    }
    
    private func loadExtendedCryptoList() async {
        do {
            let urlString = "\(APIConstants.coinMarketCapBaseURL)/cryptocurrency/listings/latest?limit=200&convert=USD"
            guard let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: encodedUrlString) else { return }
            
            var request = URLRequest(url: url)
            request.setValue(APIConstants.coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(CMCListingsResponse.self, from: data)
            
            var assets: [Asset] = []
            
            for crypto in result.data {
                guard let usdData = crypto.quote["USD"] else { continue }
                
                let asset = Asset(
                    type: .crypto,
                    symbol: crypto.symbol,
                    name: crypto.name,
                    currentPrice: usdData.price,
                    formattedPrice: formatPrice(usdData.price),
                    priceChangePercentage24H: usdData.percent_change_24h,
                    high24H: usdData.price * (1 + abs(usdData.percent_change_24h/100)),
                    low24H: usdData.price * (1 - abs(usdData.percent_change_24h/100)),
                    marketCap: usdData.market_cap,
                    volume24H: usdData.volume_24h,
                    circulatingSupply: crypto.circulating_supply,
                    totalSupply: crypto.total_supply,
                    maxSupply: crypto.max_supply,
                    athPrice: 0,
                    athDate: Date(),
                    atlPrice: 0,
                    atlDate: Date(),
                    lastUpdated: Date(),
                    marketCapRank: crypto.cmc_rank,
                    description: nil,
                    homepageURL: nil,
                    githubURL: nil,
                    redditURL: nil,
                    twitterUsername: nil,
                    priceHistory: nil
                )
                
                assets.append(asset)
            }
            
            await MainActor.run {
                self.cachedCryptos = assets
            }
            
        } catch {
            print("Error loading extended crypto list: \(error)")
        }
    }
    
    public func loadPopularAssets() {
        Task {
            await loadPopularAssetsAsync()
        }
    }
    
    private func loadPopularAssetsAsync() async {
        isLoading = true
        error = nil
        
        do {
            switch selectedAssetType {
            case .crypto:
                try await loadPopularCryptos()
            case .stock:
                try await loadPopularStocks()
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        error = nil
        
        // Cancel any existing search task
        searchCancellable?.cancel()
        
        // Debounce search requests
        searchCancellable = Just(query)
            .delay(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                
                Task {
                    await self.performSearch(query: query)
                }
            }
    }
    
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                self.searchResults = []
                self.isLoading = false
            }
            return
        }
        
        do {
            switch selectedAssetType {
            case .crypto:
                // First, search in cached results
                let lowercasedQuery = query.lowercased()
                var matchingAssets = cachedCryptos.filter { asset in
                    asset.symbol.lowercased().contains(lowercasedQuery) ||
                    asset.name.lowercased().contains(lowercasedQuery)
                }
                
                // Sort results by relevance and market cap
                matchingAssets.sort { (a, b) -> Bool in
                    // Exact symbol matches get highest priority
                    if a.symbol.lowercased() == lowercasedQuery {
                        return true
                    }
                    if b.symbol.lowercased() == lowercasedQuery {
                        return false
                    }
                    
                    // Then check for symbol starts with
                    let aStartsWithSymbol = a.symbol.lowercased().starts(with: lowercasedQuery)
                    let bStartsWithSymbol = b.symbol.lowercased().starts(with: lowercasedQuery)
                    if aStartsWithSymbol != bStartsWithSymbol {
                        return aStartsWithSymbol
                    }
                    
                    // Then check for name starts with
                    let aStartsWithName = a.name.lowercased().starts(with: lowercasedQuery)
                    let bStartsWithName = b.name.lowercased().starts(with: lowercasedQuery)
                    if aStartsWithName != bStartsWithName {
                        return aStartsWithName
                    }
                    
                    // Finally, sort by market cap
                    return a.marketCap > b.marketCap
                }
                
                // Update UI with cached results first
                self.searchResults = Array(matchingAssets.prefix(20))
                
                // Only call API if necessary and enough time has passed
                if (matchingAssets.count < 5 || shouldCallAPI()) && query.count >= 2 {
                    do {
                        try await searchCrypto(query: query)
                    } catch {
                        // If API call fails, still show cached results
                        print("API search failed: \(error)")
                    }
                }
                
            case .stock:
                guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                    throw URLError(.badURL)
                }
                let url = "\(finnhubBaseURL)/search?q=\(encodedQuery)"
                try await searchStocks(url: url)
            }
        } catch {
            self.error = "Search failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func shouldCallAPI() -> Bool {
        guard let lastCall = lastAPICallTime else {
            lastAPICallTime = Date()
            return true
        }
        
        let timeSinceLastCall = Date().timeIntervalSince(lastCall)
        if timeSinceLastCall >= apiCallCooldown {
            lastAPICallTime = Date()
            return true
        }
        
        return false
    }
    
    private func searchCrypto(query: String) async throws {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(APIConstants.coinMarketCapBaseURL)/cryptocurrency/map?symbol=\(encodedQuery)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(APIConstants.coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(CoinMarketCapMapResponse.self, from: data)
        
        // Filter and sort results
        let matchingCryptos = result.data
            .filter { crypto in
                crypto.symbol.lowercased().contains(query.lowercased()) ||
                crypto.name.lowercased().contains(query.lowercased())
            }
            .sorted { (a, b) -> Bool in
                return a.symbol.lowercased() == query.lowercased() ||
                a.symbol.lowercased().starts(with: query.lowercased()) &&
                !b.symbol.lowercased().starts(with: query.lowercased())
            }
            .prefix(20)
        
        if matchingCryptos.isEmpty {
            return
        }
        
        let symbols = matchingCryptos.map { $0.symbol }.joined(separator: ",")
        guard let detailsUrl = URL(string: "\(APIConstants.coinMarketCapBaseURL)/cryptocurrency/quotes/latest?symbol=\(symbols)&convert=USD") else {
            throw URLError(.badURL)
        }
        
        var detailsRequest = URLRequest(url: detailsUrl)
        detailsRequest.setValue(APIConstants.coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        detailsRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        detailsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        detailsRequest.timeoutInterval = 30
        detailsRequest.cachePolicy = .reloadIgnoringLocalCacheData
        
        let (detailsData, detailsResponse) = try await URLSession.shared.data(for: detailsRequest)
        
        guard let detailsHttpResponse = detailsResponse as? HTTPURLResponse,
              detailsHttpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let detailsResult = try decoder.decode(CoinMarketCapQuotesResponse.self, from: detailsData)
        
        var newAssets: [Asset] = []
        
        for crypto in matchingCryptos {
            if let cryptoData = detailsResult.data[crypto.symbol],
               let usdData = cryptoData.quote["USD"] {
                
                let asset = Asset(
                    type: .crypto,
                    symbol: cryptoData.symbol,
                    name: cryptoData.name,
                    currentPrice: usdData.price,
                    formattedPrice: formatPrice(usdData.price),
                    priceChangePercentage24H: usdData.percent_change_24h,
                    high24H: usdData.price * (1 + abs(usdData.percent_change_24h/100)),
                    low24H: usdData.price * (1 - abs(usdData.percent_change_24h/100)),
                    marketCap: usdData.market_cap,
                    volume24H: usdData.volume_24h,
                    circulatingSupply: cryptoData.circulating_supply ?? 0,
                    totalSupply: cryptoData.total_supply,
                    maxSupply: cryptoData.max_supply,
                    athPrice: 0,
                    athDate: Date(),
                    atlPrice: 0,
                    atlDate: Date(),
                    lastUpdated: Date(),
                    marketCapRank: cryptoData.cmc_rank ?? 0,
                    description: nil,
                    homepageURL: nil,
                    githubURL: nil,
                    redditURL: nil,
                    twitterUsername: nil,
                    priceHistory: nil
                )
                
                newAssets.append(asset)
            }
        }
        
        await MainActor.run {
            // Update cache with new assets
            for asset in newAssets {
                if !self.cachedCryptos.contains(where: { $0.symbol == asset.symbol }) {
                    self.cachedCryptos.append(asset)
                }
            }
            
            // Merge with existing results, keeping the order
            var finalResults = self.searchResults
            for asset in newAssets {
                if !finalResults.contains(where: { $0.symbol == asset.symbol }) {
                    finalResults.append(asset)
                }
            }
            
            self.searchResults = Array(finalResults.prefix(20))
        }
    }
    
    private func searchStocks(url: String) async throws {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(finnhubAPIKey, forHTTPHeaderField: "X-Finnhub-Token")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200:
            break // Success
        case 401:
            throw NSError(domain: "SearchError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid Finnhub API key"])
        case 429:
            throw NSError(domain: "SearchError", code: 429, userInfo: [NSLocalizedDescriptionKey: "Finnhub rate limit exceeded"])
        default:
            throw NSError(domain: "SearchError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Finnhub server error: \(httpResponse.statusCode)"])
        }
        
        let searchResponse = try JSONDecoder().decode(FinnhubSearchResponse.self, from: data)
        
        // Filter only US stocks and common stocks
        let stockResults = searchResponse.result.filter { result in
            // Only include US stocks and exclude common crypto symbols
            let commonCryptoTickers = ["BTC", "ETH", "USDT", "BNB", "XRP", "ADA", "DOGE", "SOL"]
            return result.type == "Common Stock" && 
                   !result.symbol.contains(".") &&
                   !result.symbol.contains(":") &&
                   result.symbol.count <= 5 &&
                   !commonCryptoTickers.contains(result.symbol.uppercased())
        }
        
        var assets: [Asset] = []
        
        // Process each stock result
        for result in stockResults.prefix(5) {
            do {
                let stock = try await fetchStockDetails(symbol: result.symbol)
                if stock.currentPrice > 0 && stock.marketCap > 0 {
                    assets.append(stock)
                }
            } catch {
                print("Error fetching stock details for \(result.symbol): \(error)")
                continue
            }
        }
        
        // Sort by market cap and update UI
        await MainActor.run {
            self.searchResults = assets.sorted { $0.marketCap > $1.marketCap }
        }
    }
    
    private func fetchStockDetails(symbol: String) async throws -> Asset {
        print("Fetching details for stock: \(symbol)")
        
        let quoteURL = "\(finnhubBaseURL)/quote?symbol=\(symbol)"
        let profileURL = "\(finnhubBaseURL)/stock/profile2?symbol=\(symbol)"
        
        print("Quote URL: \(quoteURL)")
        print("Profile URL: \(profileURL)")
        
        // Add retry logic
        let maxRetries = 3
        var lastError: Error? = nil
        
        for attempt in 1...maxRetries {
            do {
                async let quoteRequest = makeRequest(url: quoteURL)
                async let profileRequest = makeRequest(url: profileURL)
                
                let (quoteData, profileData) = try await (quoteRequest, profileRequest)
                
                guard let quote = try? JSONDecoder().decode(StockQuote.self, from: quoteData),
                      let profile = try? JSONDecoder().decode(StockProfile.self, from: profileData) else {
                    throw URLError(.cannotParseResponse)
                }
                
                let currentPrice = quote.currentPrice > 0 ? quote.currentPrice : 0
                let marketCap = currentPrice * Double(profile.shareOutstanding)
                
                guard currentPrice > 0, marketCap > 0 else {
                    print("Invalid price or market cap for \(symbol)")
                    throw URLError(.cannotParseResponse)
                }
                
                print("✅ Successfully fetched details for \(symbol)")
                
                return Asset(
                    type: .stock,
                    symbol: symbol.uppercased(),
                    name: profile.name,
                    currentPrice: currentPrice,
                    formattedPrice: formatPrice(currentPrice),
                    priceChangePercentage24H: quote.percentChange,
                    high24H: quote.highPrice,
                    low24H: quote.lowPrice,
                    marketCap: marketCap,
                    volume24H: 0,
                    circulatingSupply: Double(profile.shareOutstanding),
                    totalSupply: nil,
                    maxSupply: nil,
                    athPrice: 0,
                    athDate: Date(),
                    atlPrice: 0,
                    atlDate: Date(),
                    lastUpdated: Date(),
                    marketCapRank: 0,
                    description: profile.description,
                    homepageURL: profile.weburl,
                    githubURL: nil,
                    redditURL: nil,
                    twitterUsername: nil,
                    priceHistory: nil
                )
            } catch {
                lastError = error
                print("❌ Attempt \(attempt) failed for \(symbol): \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    print("Retrying in \(attempt) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
                    continue
                }
            }
        }
        
        throw lastError ?? URLError(.unknown)
    }
    
    private func makeRequest(url: String) async throws -> Data {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(finnhubAPIKey, forHTTPHeaderField: "X-Finnhub-Token")
        request.timeoutInterval = 30
        
        // Add retry logic
        let maxRetries = 3
        var lastError: Error? = nil
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                switch httpResponse.statusCode {
                case 200:
                    return data
                case 429:
                    print("⚠️ Rate limit exceeded, waiting before retry...")
                    try await Task.sleep(nanoseconds: UInt64(attempt * 2_000_000_000))
                    continue
                case 401:
                    throw NSError(domain: "SearchError", code: 401, 
                                userInfo: [NSLocalizedDescriptionKey: "Invalid API key"])
                default:
                    throw NSError(domain: "SearchError", code: httpResponse.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode)"])
                }
            } catch {
                lastError = error
                print("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    print("Retrying in \(attempt) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
                    continue
                }
            }
        }
        
        throw lastError ?? URLError(.unknown)
    }
    
    private func loadPopularCryptos() async throws {
        let urlString = "\(APIConstants.coinMarketCapBaseURL)/cryptocurrency/listings/latest?limit=10&convert=USD"
        guard let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedUrlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(APIConstants.coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(CMCListingsResponse.self, from: data)
        
        var assets: [Asset] = []
        
        for crypto in result.data {
            guard let usdData = crypto.quote["USD"] else { continue }
            
            let price = usdData.price
            let percentChange = usdData.percent_change_24h
            let marketCap = usdData.market_cap
            let volume = usdData.volume_24h
            
            let asset = Asset(
                type: .crypto,
                symbol: crypto.symbol,
                name: crypto.name,
                currentPrice: price,
                formattedPrice: formatPrice(price),
                priceChangePercentage24H: percentChange,
                high24H: price * (1 + abs(percentChange/100)),
                low24H: price * (1 - abs(percentChange/100)),
                marketCap: marketCap,
                volume24H: volume,
                circulatingSupply: crypto.circulating_supply,
                totalSupply: crypto.total_supply,
                maxSupply: crypto.max_supply,
                athPrice: 0,
                athDate: Date(),
                atlPrice: 0,
                atlDate: Date(),
                lastUpdated: Date(),
                marketCapRank: crypto.cmc_rank,
                description: nil,
                homepageURL: nil,
                githubURL: nil,
                redditURL: nil,
                twitterUsername: nil,
                priceHistory: nil
            )
            
            assets.append(asset)
        }
        
        await MainActor.run {
            self.popularAssets = assets.filter { $0.currentPrice > 0 && $0.marketCap > 0 }
        }
    }
    
    private func loadPopularStocks() async throws {
        let symbols = ["AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "JPM", "V", "WMT"]
        var stocks: [Asset] = []
        
        for symbol in symbols {
            do {
                let stock = try await fetchStockDetails(symbol: symbol)
                if stock.currentPrice > 0 && stock.marketCap > 0 {
                    stocks.append(stock)
                }
            } catch {
                print("Error fetching popular stock \(symbol): \(error)")
                continue
            }
        }
        
        // Sort by market cap
        popularAssets = stocks.sorted { $0.marketCap > $1.marketCap }
    }
    
    func clearResults() {
        searchResults = []
    }
} 
