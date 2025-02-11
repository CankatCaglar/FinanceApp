import Foundation
import FirebaseFirestore

public enum NewsCategory: String, CaseIterable, Codable {
    case all = "All"
    case stocks = "Stocks"
    case crypto = "Crypto"
    
    var firestoreField: String {
        switch self {
        case .all: return "category"
        case .stocks: return "category"
        case .crypto: return "category"
        }
    }
    
    var finnhubCategory: String {
        switch self {
        case .all: return "general"
        case .stocks: return "business"
        case .crypto: return "crypto"
        }
    }
    
    static func fromFinnhubCategory(_ category: String) -> NewsCategory {
        let lowercased = category.lowercased()
        if lowercased.contains("crypto") {
            return .crypto
        } else if lowercased.contains("stock") || 
                  lowercased == "general" || 
                  lowercased == "business" || 
                  lowercased == "forex" || 
                  lowercased == "merger" ||
                  lowercased == "top news" ||
                  lowercased == "company news" {
            return .stocks
        }
        return .all
    }
    
    public func next() -> NewsCategory {
        let allCases = NewsCategory.allCases
        guard let currentIndex = allCases.firstIndex(of: self) else { return .all }
        let nextIndex = (currentIndex + 1) % allCases.count
        return allCases[nextIndex]
    }
}

// MARK: - String Conversion
extension NewsCategory {
    public init?(firestoreString: String) {
        let normalized = firestoreString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()
        
        switch lowercased {
        case "stocks", "stock", "business", "forex", "merger", "general", "top news", "company news":
            self = .stocks
        case "crypto", "cryptocurrency":
            self = .crypto
        case "all":
            self = .all
        default:
            if let category = NewsCategory(rawValue: normalized) {
                self = category
            } else if let category = NewsCategory(rawValue: normalized.capitalized) {
                self = category
            } else {
                return nil
            }
        }
    }
    
    public var firestoreString: String {
        return self.rawValue.lowercased()
    }
}

// MARK: - CustomStringConvertible
extension NewsCategory: CustomStringConvertible {
    public var description: String {
        return self.rawValue
    }
} 