import Foundation

// MARK: - CoinMarketCap API Models
public struct CMCListingsResponse: Codable {
    public let data: [CMCCrypto]
    
    public init(data: [CMCCrypto]) {
        self.data = data
    }
}

public struct CMCCrypto: Codable {
    public let id: Int
    public let name: String
    public let symbol: String
    public let cmc_rank: Int
    public let circulating_supply: Double
    public let total_supply: Double?
    public let max_supply: Double?
    public let last_updated: String
    public let quote: [String: CMCUSDQuote]
    
    public init(id: Int, name: String, symbol: String, cmc_rank: Int, circulating_supply: Double, total_supply: Double?, max_supply: Double?, last_updated: String, quote: [String: CMCUSDQuote]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.cmc_rank = cmc_rank
        self.circulating_supply = circulating_supply
        self.total_supply = total_supply
        self.max_supply = max_supply
        self.last_updated = last_updated
        self.quote = quote
    }
}

public struct CMCUSDQuote: Codable {
    public let price: Double
    public let volume_24h: Double
    public let percent_change_24h: Double
    public let market_cap: Double
    public let last_updated: String
    
    public init(price: Double, volume_24h: Double, percent_change_24h: Double, market_cap: Double, last_updated: String) {
        self.price = price
        self.volume_24h = volume_24h
        self.percent_change_24h = percent_change_24h
        self.market_cap = market_cap
        self.last_updated = last_updated
    }
}

public struct CoinMarketCapMapResponse: Codable {
    public let data: [CMCMapCrypto]
    public let status: CMCStatus
    
    public init(data: [CMCMapCrypto], status: CMCStatus) {
        self.data = data
        self.status = status
    }
}

public struct CMCMapCrypto: Codable {
    public let id: Int
    public let name: String
    public let symbol: String
    public let rank: Int?
    public let is_active: Int
    public let first_historical_data: String?
    public let last_historical_data: String?
    public let platform: CMCPlatform?
    
    public init(id: Int, name: String, symbol: String, rank: Int?, is_active: Int, first_historical_data: String?, last_historical_data: String?, platform: CMCPlatform?) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.rank = rank
        self.is_active = is_active
        self.first_historical_data = first_historical_data
        self.last_historical_data = last_historical_data
        self.platform = platform
    }
}

public struct CMCPlatform: Codable {
    public let id: Int
    public let name: String
    public let symbol: String
    public let slug: String
    public let token_address: String
    
    public init(id: Int, name: String, symbol: String, slug: String, token_address: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.slug = slug
        self.token_address = token_address
    }
}

public struct CMCStatus: Codable {
    public let timestamp: String
    public let error_code: Int
    public let error_message: String?
    public let elapsed: Int
    public let credit_count: Int
    
    public init(timestamp: String, error_code: Int, error_message: String?, elapsed: Int, credit_count: Int) {
        self.timestamp = timestamp
        self.error_code = error_code
        self.error_message = error_message
        self.elapsed = elapsed
        self.credit_count = credit_count
    }
}

public struct CoinMarketCapQuotesResponse: Codable {
    public let data: [String: CMCQuoteCrypto]
    public let status: CMCStatus
    
    public init(data: [String: CMCQuoteCrypto], status: CMCStatus) {
        self.data = data
        self.status = status
    }
}

public struct CMCQuoteCrypto: Codable {
    public let id: Int
    public let name: String
    public let symbol: String
    public let circulating_supply: Double?
    public let total_supply: Double?
    public let max_supply: Double?
    public let cmc_rank: Int?
    public let quote: [String: CMCUSDQuote]
    
    public init(id: Int, name: String, symbol: String, circulating_supply: Double?, total_supply: Double?, max_supply: Double?, cmc_rank: Int?, quote: [String: CMCUSDQuote]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.circulating_supply = circulating_supply
        self.total_supply = total_supply
        self.max_supply = max_supply
        self.cmc_rank = cmc_rank
        self.quote = quote
    }
}

// MARK: - Finnhub API Models
public struct FinnhubQuote: Codable {
    public let c: Double  // Current price
    public let h: Double  // High price of the day
    public let l: Double  // Low price of the day
    public let o: Double  // Open price of the day
    public let pc: Double // Previous close price
    public let t: Int     // Timestamp
    public let v: Int?    // Volume (optional)
    
    public init(c: Double, h: Double, l: Double, o: Double, pc: Double, t: Int, v: Int?) {
        self.c = c
        self.h = h
        self.l = l
        self.o = o
        self.pc = pc
        self.t = t
        self.v = v
    }
}

public struct FinnhubCompanyProfile: Codable {
    public let name: String?
    public let marketCapitalization: Double?
    public let shareOutstanding: Double?
    public let weburl: String?
    public let description: String?
    
    public init(name: String?, marketCapitalization: Double?, shareOutstanding: Double?, weburl: String?, description: String?) {
        self.name = name
        self.marketCapitalization = marketCapitalization
        self.shareOutstanding = shareOutstanding
        self.weburl = weburl
        self.description = description
    }
}

public struct FinnhubSearchResponse: Codable {
    public let count: Int
    public let result: [FinnhubSearchResult]
    
    public init(count: Int, result: [FinnhubSearchResult]) {
        self.count = count
        self.result = result
    }
}

public struct FinnhubSearchResult: Codable {
    public let description: String
    public let displaySymbol: String
    public let symbol: String
    public let type: String
    
    public init(description: String, displaySymbol: String, symbol: String, type: String) {
        self.description = description
        self.displaySymbol = displaySymbol
        self.symbol = symbol
        self.type = type
    }
}

public struct StockQuote: Codable {
    public let currentPrice: Double
    public let highPrice: Double
    public let lowPrice: Double
    public let percentChange: Double
    
    public enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
        case highPrice = "h"
        case lowPrice = "l"
        case percentChange = "dp"
    }
    
    public init(currentPrice: Double, highPrice: Double, lowPrice: Double, percentChange: Double) {
        self.currentPrice = currentPrice
        self.highPrice = highPrice
        self.lowPrice = lowPrice
        self.percentChange = percentChange
    }
}

public struct StockProfile: Codable {
    public let name: String
    public let description: String?
    public let weburl: String?
    public let shareOutstanding: Double
    
    public init(name: String, description: String?, weburl: String?, shareOutstanding: Double) {
        self.name = name
        self.description = description
        self.weburl = weburl
        self.shareOutstanding = shareOutstanding
    }
}
