import Foundation
import FirebaseAuth

struct User: Identifiable, Codable {
    let id: String
    let email: String
    var fullName: String
    var photoURL: String?
    var notificationsEnabled: Bool
    
    var name: String { fullName }
    var profileImage: String? { photoURL }
    
    init(id: String, email: String, fullName: String, photoURL: String? = nil, notificationsEnabled: Bool = false) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.photoURL = photoURL
        self.notificationsEnabled = notificationsEnabled
    }
    
    init(from firebaseUser: FirebaseAuth.User) {
        self.id = firebaseUser.uid
        self.email = firebaseUser.email ?? ""
        self.fullName = firebaseUser.displayName ?? ""
        self.photoURL = firebaseUser.photoURL?.absoluteString
        self.notificationsEnabled = false
    }
    
    init(from userData: UserData) {
        self.id = userData.id
        self.email = userData.email
        self.fullName = userData.name
        self.photoURL = userData.profileImage
        self.notificationsEnabled = false
    }
    
    func toUserData() -> UserData {
        UserData(
            id: id,
            email: email,
            name: fullName,
            profileImage: photoURL,
            subscriptionType: nil,
            subscriptionEndDate: nil,
            createdAt: Date(),
            lastUpdated: Date()
        )
    }
} 