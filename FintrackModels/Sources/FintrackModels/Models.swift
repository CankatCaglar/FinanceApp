import Foundation

// MARK: - Asset Types
public enum AssetType: String, Codable {
    case crypto
    case stock
}

// MARK: - Portfolio Asset Model
public struct PortfolioAsset: Identifiable, Codable {
    public var id: String { symbol }
    public let type: AssetType
    public let symbol: String
    public let name: String
    public var quantity: Double
    public var currentPrice: Double
    public var priceChangePercentage24H: Double
    public let purchaseDate: Date
    
    public init(type: AssetType, symbol: String, name: String, quantity: Double, currentPrice: Double, priceChangePercentage24H: Double, purchaseDate: Date) {
        self.type = type
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.currentPrice = currentPrice
        self.priceChangePercentage24H = priceChangePercentage24H
        self.purchaseDate = purchaseDate
    }
    
    public var currentValue: Double {
        quantity * currentPrice
    }
    
    public var formattedPrice: String {
        if currentPrice < 0.000001 {
            return String(format: "%.8f", currentPrice)
        } else if currentPrice < 0.00001 {
            return String(format: "%.7f", currentPrice)
        } else if currentPrice < 0.0001 {
            return String(format: "%.6f", currentPrice)
        } else if currentPrice < 0.001 {
            return String(format: "%.5f", currentPrice)
        } else if currentPrice < 0.01 {
            return String(format: "%.4f", currentPrice)
        } else if currentPrice < 1 {
            return String(format: "%.4f", currentPrice)
        } else if currentPrice < 10 {
            return String(format: "%.3f", currentPrice)
        } else {
            return String(format: "%.2f", currentPrice)
        }
    }
    
    public var formattedValue: String {
        let value = currentValue
        if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.2f", value)
        } else {
            return String(format: "$%.2f", value)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, symbol, name, quantity, currentPrice, priceChangePercentage24H, purchaseDate
    }
    
    public static func fromFirestore(_ data: [String: Any]) -> PortfolioAsset? {
        guard let typeString = data["type"] as? String,
              let type = AssetType(rawValue: typeString),
              let symbol = data["symbol"] as? String,
              let name = data["name"] as? String,
              let quantity = data["quantity"] as? Double,
              let currentPrice = data["currentPrice"] as? Double,
              let priceChangePercentage24H = data["priceChangePercentage24H"] as? Double else {
            return nil
        }
        
        let purchaseDate: Date
        if let timestamp = data["purchaseDate"] as? TimeInterval {
            purchaseDate = Date(timeIntervalSince1970: timestamp)
        } else {
            purchaseDate = Date()
        }
        
        return PortfolioAsset(
            type: type,
            symbol: symbol,
            name: name,
            quantity: quantity,
            currentPrice: currentPrice,
            priceChangePercentage24H: priceChangePercentage24H,
            purchaseDate: purchaseDate
        )
    }
}

// MARK: - Asset Model
public struct Asset: Identifiable, Codable {
    public let id: UUID
    public let type: AssetType
    public let symbol: String
    public let name: String
    public let currentPrice: Double
    public let formattedPrice: String
    public let priceChangePercentage24H: Double
    public let high24H: Double
    public let low24H: Double
    public let marketCap: Double
    public let volume24H: Double
    public let circulatingSupply: Double
    public let totalSupply: Double?
    public let maxSupply: Double?
    public let athPrice: Double
    public let athDate: Date
    public let atlPrice: Double
    public let atlDate: Date
    public let lastUpdated: Date
    public let marketCapRank: Int?
    public let description: String?
    public let homepageURL: String?
    public let githubURL: String?
    public let redditURL: String?
    public let twitterUsername: String?
    public let priceHistory: [PricePoint]?
    
    public init(type: AssetType,
               symbol: String,
               name: String,
               currentPrice: Double,
               formattedPrice: String,
               priceChangePercentage24H: Double,
               high24H: Double,
               low24H: Double,
               marketCap: Double,
               volume24H: Double,
               circulatingSupply: Double,
               totalSupply: Double?,
               maxSupply: Double?,
               athPrice: Double,
               athDate: Date,
               atlPrice: Double,
               atlDate: Date,
               lastUpdated: Date,
               marketCapRank: Int?,
               description: String? = nil,
               homepageURL: String? = nil,
               githubURL: String? = nil,
               redditURL: String? = nil,
               twitterUsername: String? = nil,
               priceHistory: [PricePoint]? = nil) {
        self.id = UUID()
        self.type = type
        self.symbol = symbol
        self.name = name
        self.currentPrice = currentPrice
        self.formattedPrice = formattedPrice
        self.priceChangePercentage24H = priceChangePercentage24H
        self.high24H = high24H
        self.low24H = low24H
        self.marketCap = marketCap
        self.volume24H = volume24H
        self.circulatingSupply = circulatingSupply
        self.totalSupply = totalSupply
        self.maxSupply = maxSupply
        self.athPrice = athPrice
        self.athDate = athDate
        self.atlPrice = atlPrice
        self.atlDate = atlDate
        self.lastUpdated = lastUpdated
        self.marketCapRank = marketCapRank
        self.description = description
        self.homepageURL = homepageURL
        self.githubURL = githubURL
        self.redditURL = redditURL
        self.twitterUsername = twitterUsername
        self.priceHistory = priceHistory
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, type, symbol, name, currentPrice, formattedPrice, priceChangePercentage24H
        case high24H, low24H, marketCap, volume24H, circulatingSupply, totalSupply, maxSupply
        case athPrice, athDate, atlPrice, atlDate, lastUpdated, marketCapRank
        case description, homepageURL, githubURL, redditURL, twitterUsername, priceHistory
    }
}

// MARK: - Price Point Model
public struct PricePoint: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let price: Double
    
    public init(date: Date, price: Double) {
        self.id = UUID()
        self.date = date
        self.price = price
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, date, price
    }
}