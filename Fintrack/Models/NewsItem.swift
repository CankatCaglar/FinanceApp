import Foundation

public struct NewsItem: Identifiable, Codable {
    public let id: Int
    public let headline: String
    public let summary: String
    public let url: String
    public let source: String
    public let imageUrl: String?
    public let publishedAt: Date
    public var category: NewsCategory
    public var categories: [NewsCategory]
    
    enum CodingKeys: String, CodingKey {
        case id
        case headline
        case summary
        case url
        case source
        case imageUrl
        case publishedAt
        case category
        case categories
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        headline = try container.decode(String.self, forKey: .headline)
        summary = try container.decode(String.self, forKey: .summary)
        url = try container.decode(String.self, forKey: .url)
        source = try container.decode(String.self, forKey: .source)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        
        if let timestamp = try? container.decode(TimeInterval.self, forKey: .publishedAt) {
            publishedAt = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .publishedAt),
                  let date = ISO8601DateFormatter().date(from: dateString) {
            publishedAt = date
        } else {
            publishedAt = Date()
        }
        
        if let categoryString = try? container.decode(String.self, forKey: .category),
           let decodedCategory = NewsCategory(firestoreString: categoryString) {
            category = decodedCategory
        } else {
            category = .all
        }
        
        if let categoryStrings = try? container.decode([String].self, forKey: .categories) {
            categories = categoryStrings.compactMap { NewsCategory(firestoreString: $0) }
        } else {
            categories = [category, .all]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(headline, forKey: .headline)
        try container.encode(summary, forKey: .summary)
        try container.encode(url, forKey: .url)
        try container.encode(source, forKey: .source)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encode(publishedAt.timeIntervalSince1970, forKey: .publishedAt)
        try container.encode(category.firestoreString, forKey: .category)
        try container.encode(categories.map { $0.firestoreString }, forKey: .categories)
    }
    
    public init(id: Int, headline: String, summary: String, url: String, source: String, imageUrl: String?, publishedAt: Date, category: NewsCategory, categories: [NewsCategory] = []) {
        self.id = id
        self.headline = headline
        self.summary = summary
        self.url = url
        self.source = source
        self.imageUrl = imageUrl
        self.publishedAt = publishedAt
        self.category = category
        self.categories = categories.isEmpty ? [category, .all] : categories
    }
} 