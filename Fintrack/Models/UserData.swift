import Foundation
import FirebaseFirestore

struct UserData: Codable, Identifiable {
    var id: String
    var email: String
    var name: String
    var profileImage: String?
    var subscriptionType: String?
    var subscriptionEndDate: Date?
    var createdAt: Date
    var lastUpdated: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case profileImage
        case subscriptionType
        case subscriptionEndDate
        case createdAt
        case lastUpdated
    }
}

// MARK: - Firestore Convenience
extension UserData {
    static func from(_ document: DocumentSnapshot) -> UserData? {
        guard let data = document.data() else { return nil }
        
        return UserData(
            id: document.documentID,
            email: data["email"] as? String ?? "",
            name: data["name"] as? String ?? "",
            profileImage: data["profileImage"] as? String,
            subscriptionType: data["subscriptionType"] as? String,
            subscriptionEndDate: (data["subscriptionEndDate"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            lastUpdated: (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "email": email,
            "name": name,
            "createdAt": Timestamp(date: createdAt),
            "lastUpdated": Timestamp(date: Date())
        ]
        
        // Only include optional fields if they have values
        if let profileImage = profileImage {
            data["profileImage"] = profileImage
        }
        if let subscriptionType = subscriptionType {
            data["subscriptionType"] = subscriptionType
        }
        if let subscriptionEndDate = subscriptionEndDate {
            data["subscriptionEndDate"] = Timestamp(date: subscriptionEndDate)
        }
        
        return data
    }
    
    // Update specific fields
    func updating(name: String? = nil,
                 profileImage: String? = nil,
                 subscriptionType: String? = nil,
                 subscriptionEndDate: Date? = nil) -> UserData {
        var updated = self
        if let name = name {
            updated.name = name
        }
        if let profileImage = profileImage {
            updated.profileImage = profileImage
        }
        if let subscriptionType = subscriptionType {
            updated.subscriptionType = subscriptionType
        }
        if let subscriptionEndDate = subscriptionEndDate {
            updated.subscriptionEndDate = subscriptionEndDate
        }
        updated.lastUpdated = Date()
        return updated
    }
} 