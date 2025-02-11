import Foundation

struct APIConstants {
    static let finnhubBaseURL = "https://finnhub.io/api/v1"
    static let coinMarketCapBaseURL = "https://pro-api.coinmarketcap.com/v1"
    static let finnhubAPIKey = "cudqf91r01qiosq0svdgcudqf91r01qiosq0sve0"
    static let coinMarketCapAPIKey = "1bc94c4b-bb47-4da7-9b5d-10d72663324f"
    
    // Finnhub Endpoints
    static func finnhubStockNews(symbol: String) -> String {
        return "\(finnhubBaseURL)/company-news?symbol=\(symbol)"
    }
    
    static func finnhubStockQuote(symbol: String) -> String {
        return "\(finnhubBaseURL)/quote?symbol=\(symbol)"
    }
    
    // CoinMarketCap Endpoints
    static let cryptoListingsLatest = "\(coinMarketCapBaseURL)/cryptocurrency/listings/latest"
    static let cryptoQuotesLatest = "\(coinMarketCapBaseURL)/cryptocurrency/quotes/latest"
} 