import Foundation
import Combine
import FintrackModels
import FirebaseFirestore
import FirebaseAuth

class PortfolioViewModel: ObservableObject {
    public static let shared = PortfolioViewModel()
    
    @Published var portfolioAssets: [PortfolioAsset] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private var userId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private init() {
        print("📱 Initializing PortfolioViewModel")
        
        // First check for existing user and load portfolio
        if let currentUserId = Auth.auth().currentUser?.uid {
            print("👤 Found existing user session: \(currentUserId)")
            Task { @MainActor in
                await loadPortfolio(for: currentUserId)
            }
        } else {
            print("👤 No existing user session found")
        }
        
        // Then setup auth listener for future changes
        setupAuthListener()
    }
    
    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            if let userId = user?.uid {
                print("👤 Auth state changed - User signed in: \(userId)")
                Task { @MainActor in
                    await self.loadPortfolio(for: userId)
                }
            } else {
                print("👤 Auth state changed - User signed out")
                // Don't clear portfolio when user signs out
                Task { @MainActor in
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadPortfolio(for userId: String) async {
        print("📝 Starting to load portfolio for user: \(userId)")
        
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("portfolio")
                .getDocuments()
            
            print("📝 Found \(snapshot.documents.count) portfolio items")
            
            var loadedAssets: [PortfolioAsset] = []
            for document in snapshot.documents {
                if let asset = PortfolioAsset.fromFirestore(document.data()) {
                    loadedAssets.append(asset)
                    print("✅ Loaded asset: \(asset.symbol) with quantity: \(asset.quantity)")
                } else {
                    print("⚠️ Failed to parse portfolio asset from document: \(document.documentID)")
                }
            }
            
            // Always update the portfolio with loaded assets, even if empty
            await MainActor.run {
                print("📝 Updating portfolio with \(loadedAssets.count) assets")
                self.portfolioAssets = loadedAssets
                self.isLoading = false
            }
            
            // Refresh prices after loading portfolio
            if !loadedAssets.isEmpty {
                await self.refreshPortfolio()
            }
        } catch {
            print("❌ Error loading portfolio: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func savePortfolio() async {
        guard let userId = userId else {
            print("❌ Cannot save portfolio: No user ID available")
            return
        }
        
        do {
            print("📝 Starting to save portfolio for user: \(userId)")
            
            // Reference to the portfolio collection
            let portfolioRef = db.collection("users").document(userId).collection("portfolio")
            
            // Create a batch to perform all operations atomically
            let batch = db.batch()
            
            // First, delete all existing documents
            let existingDocs = try await portfolioRef.getDocuments()
            for doc in existingDocs.documents {
                batch.deleteDocument(doc.reference)
            }
            
            // Then, add all current assets
            for asset in portfolioAssets {
                let docRef = portfolioRef.document(asset.symbol)
                let data: [String: Any] = [
                    "type": asset.type.rawValue,
                    "symbol": asset.symbol,
                    "name": asset.name,
                    "quantity": asset.quantity,
                    "currentPrice": asset.currentPrice,
                    "priceChangePercentage24H": asset.priceChangePercentage24H,
                    "purchaseDate": Timestamp(date: asset.purchaseDate)
                ]
                batch.setData(data, forDocument: docRef)
                print("📝 Saving asset: \(asset.symbol) with quantity: \(asset.quantity)")
            }
            
            // Commit all changes
            try await batch.commit()
            print("✅ Successfully saved portfolio with \(portfolioAssets.count) assets")
            
        } catch {
            print("❌ Error saving portfolio: \(error.localizedDescription)")
            await MainActor.run {
                self.error = "Failed to save portfolio: \(error.localizedDescription)"
            }
        }
    }
    
    func addAsset(type: AssetType, symbol: String, quantity: Double) {
        print("📝 Adding asset: \(symbol) with quantity: \(quantity)")
        
        Task { @MainActor in
            self.isLoading = true
            self.error = nil
            
            do {
                let asset: Asset
                switch type {
                case .crypto:
                    asset = try await fetchCryptoDetails(symbol: symbol)
                case .stock:
                    asset = try await fetchStockDetails(symbol: symbol)
                }
                
                if let existingIndex = portfolioAssets.firstIndex(where: { $0.symbol.uppercased() == symbol.uppercased() }) {
                    // Update existing asset
                    print("📝 Updating existing asset: \(symbol)")
                    portfolioAssets[existingIndex].quantity += quantity
                    portfolioAssets[existingIndex].currentPrice = asset.currentPrice
                    portfolioAssets[existingIndex].priceChangePercentage24H = asset.priceChangePercentage24H
                } else {
                    // Add new asset
                    print("📝 Creating new asset: \(symbol)")
                    let portfolioAsset = PortfolioAsset(
                        type: asset.type,
                        symbol: asset.symbol,
                        name: asset.name,
                        quantity: quantity,
                        currentPrice: asset.currentPrice,
                        priceChangePercentage24H: asset.priceChangePercentage24H,
                        purchaseDate: Date()
                    )
                    portfolioAssets.append(portfolioAsset)
                }
                
                // Save portfolio immediately after adding asset
                print("📝 Saving portfolio after adding asset")
                await savePortfolio()
                
                self.isLoading = false
            } catch {
                print("❌ Error adding asset: \(error.localizedDescription)")
                self.error = "Failed to add asset: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func removeAssets(at indexSet: IndexSet) {
        print("🗑️ Removing assets at indices: \(indexSet)")
        
        // Get symbols before removing for logging
        let symbolsToRemove = indexSet.map { portfolioAssets[$0].symbol }
        
        portfolioAssets.remove(atOffsets: indexSet)
        
        Task { @MainActor in
            print("🗑️ Removed assets: \(symbolsToRemove.joined(separator: ", "))")
            await savePortfolio()
        }
    }
    
    @MainActor
    func refreshPortfolio() async {
        guard !portfolioAssets.isEmpty else { return }
        guard let userId = userId else { return }
        
        isLoading = true
        error = nil
        
        do {
            print("🔄 Starting portfolio refresh")
            var updatedAssets = portfolioAssets
            
            // Update prices one by one to prevent timeout
            for (index, asset) in updatedAssets.enumerated() {
                do {
                    let updatedAsset = try await fetchAssetDetails(symbol: asset.symbol, type: asset.type)
                    updatedAssets[index].currentPrice = updatedAsset.currentPrice
                    updatedAssets[index].priceChangePercentage24H = updatedAsset.priceChangePercentage24H
                    print("✅ Updated price for \(asset.symbol)")
                } catch {
                    print("⚠️ Error updating \(asset.symbol): \(error.localizedDescription)")
                }
            }
            
            self.portfolioAssets = updatedAssets
            try? await savePortfolio()
        } catch {
            self.error = error.localizedDescription
            print("❌ Error refreshing portfolio: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.2fK", value / 1_000)
        } else {
            return String(format: "$%.2f", value)
        }
    }
    
    public func fetchAssetDetails(symbol: String, type: AssetType) async throws -> Asset {
        switch type {
        case .crypto:
            return try await fetchCryptoDetails(symbol: symbol)
        case .stock:
            return try await fetchStockDetails(symbol: symbol)
        }
    }
    
    private func fetchCryptoDetails(symbol: String) async throws -> Asset {
        let url = "\(APIConstants.coinMarketCapBaseURL)/cryptocurrency/quotes/latest?symbol=\(symbol.uppercased())&convert=USD"
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(APIConstants.coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let cryptoData = dataDict[symbol.uppercased()] as? [String: Any],
              let name = cryptoData["name"] as? String,
              let quoteDict = cryptoData["quote"] as? [String: Any],
              let usdData = quoteDict["USD"] as? [String: Any],
              let price = usdData["price"] as? Double,
              let percentChange24h = usdData["percent_change_24h"] as? Double else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse crypto data"])
        }
        
        return Asset(
            type: .crypto,
            symbol: symbol.uppercased(),
            name: name,
            currentPrice: price,
            formattedPrice: String(format: "%.2f", price),
            priceChangePercentage24H: percentChange24h,
            high24H: price * (1 + abs(percentChange24h/100)),
            low24H: price * (1 - abs(percentChange24h/100)),
            marketCap: 0,
            volume24H: 0,
            circulatingSupply: 0,
            totalSupply: nil,
            maxSupply: nil,
            athPrice: 0,
            athDate: Date(),
            atlPrice: 0,
            atlDate: Date(),
            lastUpdated: Date(),
            marketCapRank: 0,
            description: nil,
            homepageURL: nil,
            githubURL: nil,
            redditURL: nil,
            twitterUsername: nil,
            priceHistory: nil
        )
    }
    
    private func fetchStockDetails(symbol: String) async throws -> Asset {
        let quoteURL = "\(APIConstants.finnhubBaseURL)/quote?symbol=\(symbol)"
        let profileURL = "\(APIConstants.finnhubBaseURL)/stock/profile2?symbol=\(symbol)"
        
        var quoteRequest = URLRequest(url: URL(string: quoteURL)!)
        var profileRequest = URLRequest(url: URL(string: profileURL)!)
        
        quoteRequest.setValue(APIConstants.finnhubAPIKey, forHTTPHeaderField: "X-Finnhub-Token")
        profileRequest.setValue(APIConstants.finnhubAPIKey, forHTTPHeaderField: "X-Finnhub-Token")
        
        async let (quoteData, _) = URLSession.shared.data(for: quoteRequest)
        async let (profileData, _) = URLSession.shared.data(for: profileRequest)
        
        let decoder = JSONDecoder()
        let quote: FintrackModels.FinnhubQuote = try decoder.decode(FintrackModels.FinnhubQuote.self, from: await quoteData)
        let profile: FintrackModels.FinnhubCompanyProfile? = try? decoder.decode(FintrackModels.FinnhubCompanyProfile.self, from: await profileData)
        
        let currentPrice = quote.c > 0 ? quote.c : quote.pc
        guard currentPrice > 0 else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid stock price"])
        }
        
        let percentChange24h = ((currentPrice - quote.pc) / quote.pc) * 100
        
        return Asset(
            type: .stock,
            symbol: symbol.uppercased(),
            name: profile?.name ?? symbol.uppercased(),
            currentPrice: currentPrice,
            formattedPrice: String(format: "%.2f", currentPrice),
            priceChangePercentage24H: percentChange24h,
            high24H: quote.h > 0 ? quote.h : currentPrice * 1.01,
            low24H: quote.l > 0 ? quote.l : currentPrice * 0.99,
            marketCap: (profile?.marketCapitalization ?? 0) * 1_000_000,
            volume24H: Double(quote.v ?? 0) * currentPrice,
            circulatingSupply: profile?.shareOutstanding ?? 0,
            totalSupply: nil,
            maxSupply: nil,
            athPrice: 0,
            athDate: Date(),
            atlPrice: 0,
            atlDate: Date(),
            lastUpdated: Date(),
            marketCapRank: 0,
            description: profile?.description,
            homepageURL: profile?.weburl,
            githubURL: nil,
            redditURL: nil,
            twitterUsername: nil,
            priceHistory: nil
        )
    }
} 
