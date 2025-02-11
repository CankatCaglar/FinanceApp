import Foundation
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import SwiftUI
import FirebaseMessaging

@MainActor
class AuthViewModel: NSObject, ObservableObject {
    static let shared = AuthViewModel()
    
    @Published var currentUser: User?
    @Published var userSession: User?
    @Published var firebaseUser: FirebaseAuth.User?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var profileImage: UIImage?
    @Published var isAuthenticated = false
    @Published var error: Error?
    
    private let auth = Auth.auth()
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private var currentNonce: String?
    
    override init() {
        super.init()
        // Initialize with current auth state
        if let currentUser = Auth.auth().currentUser {
            self.firebaseUser = currentUser
            Task {
                do {
                    try await loadUserData(currentUser)
                } catch {
                    print("❌ Error in init: \(error)")
                }
            }
        }
        setupAuthStateListener()
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func getProfileImagePath(for userId: String) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("profile_\(userId).jpg")
    }
    
    private func saveImageToFile(_ image: UIImage, userId: String) {
        do {
            guard let data = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Failed to convert image to data")
                return
            }
            
            let fileURL = getProfileImagePath(for: userId)
            print("📝 Attempting to save image to: \(fileURL.path)")
            
            // Ensure the directory exists
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
            
            // Write the file with atomic option
            try data.write(to: fileURL, options: .atomic)
            print("✅ Successfully saved image to: \(fileURL.path)")
            
            // Verify the file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("✅ Verified file exists at: \(fileURL.path)")
            } else {
                print("❌ File does not exist after saving!")
            }
        } catch {
            print("❌ Failed to save image: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
        }
    }
    
    private func loadImageFromFile(userId: String) -> UIImage? {
        let fileURL = getProfileImagePath(for: userId)
        print("🔍 Attempting to load image from: \(fileURL.path)")
        
        // Check if file exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                if let image = UIImage(data: data) {
                    print("✅ Successfully loaded image from file system")
                    return image
                } else {
                    print("❌ Failed to create UIImage from data")
                }
            } catch {
                print("❌ Failed to load image from file: \(error.localizedDescription)")
            }
        } else {
            print("❌ No image file found at path: \(fileURL.path)")
        }
        
        // Try UserDefaults as fallback
        print("🔍 Trying to load from UserDefaults...")
        if let imageData = UserDefaults.standard.data(forKey: "userProfilePhotoData_\(userId)") {
            if let image = UIImage(data: imageData) {
                print("✅ Successfully loaded image from UserDefaults")
                // Save back to file system for next time
                saveImageToFile(image, userId: userId)
                return image
            } else {
                print("❌ Failed to create UIImage from UserDefaults data")
            }
        } else {
            print("❌ No image data found in UserDefaults")
        }
        
        return nil
    }
    
    private func deleteImageFromFile(userId: String) {
        let fileURL = getProfileImagePath(for: userId)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    private func setupAuthStateListener() {
        auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                let wasAuthenticated = self?.isAuthenticated ?? false
                self?.isAuthenticated = user != nil
                self?.firebaseUser = user
                
                if let user = user {
                    Task {
                        do {
                            try await self?.loadUserData(user)
                            // Setup notifications
                            await NotificationManager.shared.setupNotificationsAfterAuth()
                        } catch {
                            print("❌ Error in auth state listener: \(error)")
                        }
                    }
                } else {
                    self?.currentUser = nil
                    self?.userSession = nil
                }
            }
        }
    }
    
    private func createUserSession(for userId: String) async {
        do {
            // Check if this is a new user
            let userDoc = try await db.collection("users").document(userId).getDocument()
            let isNewUser = !userDoc.exists || userDoc.data()?["createdAt"] == nil
            
            // Create session document
            let sessionData: [String: Any] = [
                "userId": userId,
                "deviceInfo": UIDevice.current.systemVersion,
                "platform": "iOS",
                "createdAt": FieldValue.serverTimestamp(),
                "isNewUser": isNewUser,
                "fcmToken": try await Messaging.messaging().token() ?? ""
            ]
            
            // Add to userSessions collection
            try await db.collection("userSessions").addDocument(data: sessionData)
            print("✅ Created new user session")
            
            // Update user's FCM token
            try await db.collection("users").document(userId).setData([
                "fcmToken": try await Messaging.messaging().token() ?? "",
                "notificationsEnabled": true,
                "lastTokenUpdate": FieldValue.serverTimestamp(),
                "lastLoginAt": FieldValue.serverTimestamp()
            ], merge: true)
            print("✅ Updated user FCM token")
            
        } catch {
            print("❌ Error creating user session: \(error.localizedDescription)")
        }
    }
    
    private func setupNotificationsAfterAuth() async {
        do {
            // Always request notification permissions and update token
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                if let token = try? await Messaging.messaging().token(),
                   let userId = auth.currentUser?.uid {
                    // Update Firestore with the new token
                    try await db.collection("users").document(userId).setData([
                        "fcmToken": token,
                        "notificationsEnabled": true,
                        "lastTokenUpdate": FieldValue.serverTimestamp()
                    ], merge: true)
                    print("✅ Updated FCM token: \(token)")
                }
            }
        } catch {
            print("❌ Error setting up notifications: \(error.localizedDescription)")
        }
    }
    
    private func loadUserData(_ firebaseUser: FirebaseAuth.User) async throws {
        do {
            let docRef = db.collection("users").document(firebaseUser.uid)
            let document = try await docRef.getDocument()
            
            if let data = document.data() {
                // First load profile photo from local storage
                if let savedImage = loadImageFromFile(userId: firebaseUser.uid) {
                    await MainActor.run {
                        self.profileImage = savedImage
                        print("📸 Loaded profile photo from local storage")
                    }
                }
                
                // Update user data
                let userData = UserData(
                    id: firebaseUser.uid,
                    email: data["email"] as? String ?? firebaseUser.email ?? "",
                    name: data["fullName"] as? String ?? firebaseUser.displayName ?? "",
                    profileImage: data["photoURL"] as? String ?? firebaseUser.photoURL?.absoluteString,
                    subscriptionType: data["subscriptionType"] as? String,
                    subscriptionEndDate: (data["subscriptionEndDate"] as? Timestamp)?.dateValue(),
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    lastUpdated: (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
                )
                
                let user = User(from: userData)
                await MainActor.run {
                    self.currentUser = user
                    self.userSession = user
                }
                
                // If Firebase has a profile photo URL and we couldn't load from local storage, load from URL
                if let photoURL = data["photoURL"] as? String,
                   let url = URL(string: photoURL),
                   self.profileImage == nil {
                    await loadProfileImage(from: url, userId: firebaseUser.uid)
                }
            } else {
                // Create new user document
                let user = User(from: firebaseUser)
                let userData = user.toUserData()
                try await docRef.setData(userData.firestoreData)
                
                await MainActor.run {
                    self.currentUser = user
                    self.userSession = user
                }
            }
        } catch {
            print("❌ Error loading user data: \(error.localizedDescription)")
            await MainActor.run {
                let user = User(from: firebaseUser)
                self.currentUser = user
                self.userSession = user
            }
            throw error
        }
    }
    
    private func loadProfileImage(from url: URL, userId: String) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                // Save locally first
                saveImageToFile(image, userId: userId)
                
                // Then update UI
                await MainActor.run {
                    self.profileImage = image
                    print("📸 Profile photo loaded from URL and saved locally")
                }
            }
        } catch {
            print("❌ Error loading profile image from URL: \(error.localizedDescription)")
            
            // Try local storage as fallback
            if let savedImage = loadImageFromFile(userId: userId) {
                await MainActor.run {
                    self.profileImage = savedImage
                    print("📸 Loaded profile photo from local storage (fallback)")
                }
            }
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            self.firebaseUser = result.user
            try await loadUserData(result.user)
            await MainActor.run {
                self.isAuthenticated = true
                self.error = nil
            }
            
            // Create new session for welcome back notification from Cloud Functions
            if let token = try? await Messaging.messaging().token() {
                try await db.collection("userSessions").addDocument(data: [
                    "userId": result.user.uid,
                    "deviceInfo": UIDevice.current.systemVersion,
                    "platform": "iOS",
                    "createdAt": FieldValue.serverTimestamp(),
                    "isNewUser": false,
                    "fcmToken": token
                ])
            }
            
        } catch {
            await MainActor.run {
                self.error = error
            }
            throw error
        }
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            
            // Setup notifications first to get FCM token
            await setupNotificationsAfterAuth()
            
            // Create user document in Firestore
            try await db.collection("users").document(result.user.uid).setData([
                "email": email,
                "createdAt": FieldValue.serverTimestamp(),
                "lastLoginAt": FieldValue.serverTimestamp(),
                "notificationsEnabled": true,
                "deviceInfo": [
                    "platform": "iOS",
                    "version": UIDevice.current.systemVersion,
                    "model": UIDevice.current.model
                ]
            ])
            
            self.firebaseUser = result.user
            try await loadUserData(result.user)
            await MainActor.run {
                self.isAuthenticated = true
                self.error = nil
            }
            
            // Create initial session document for welcome notification from Cloud Functions
            if let token = try? await Messaging.messaging().token() {
                try await db.collection("userSessions").addDocument(data: [
                    "userId": result.user.uid,
                    "deviceInfo": UIDevice.current.systemVersion,
                    "platform": "iOS",
                    "createdAt": FieldValue.serverTimestamp(),
                    "isNewUser": true,
                    "fcmToken": token
                ])
            }
            
        } catch {
            await MainActor.run {
                self.error = error
            }
            throw error
        }
    }
    
    func signOut() async throws {
        do {
            // Clear notifications
            await NotificationManager.shared.clearNotificationSetup()
            
            // Sign out from Firebase
            try Auth.auth().signOut()
            
            await MainActor.run {
                self.currentUser = nil
                self.userSession = nil
                self.firebaseUser = nil
                self.isAuthenticated = false
                self.profileImage = nil
            }
            
            // Clear local data
            UserDefaults.standard.removeObject(forKey: "fcmToken")
            
            print("👤 User signed out successfully")
        } catch {
            print("❌ Error signing out: \(error)")
            throw error
        }
    }
    
    func resetPassword(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            await MainActor.run {
                self.error = error
            }
            throw error
        }
    }
    
    func updateProfile(fullName: String) async throws {
        guard let userId = auth.currentUser?.uid else {
            throw NSError(domain: "", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        do {
            // Update Firebase Auth display name first
            let changeRequest = auth.currentUser?.createProfileChangeRequest()
            changeRequest?.displayName = fullName
            try await changeRequest?.commitChanges()
            
            // Then update Firestore document
            try await db.collection("users").document(userId).setData([
                "fullName": fullName,
                "lastUpdated": Timestamp(date: Date())
            ], merge: true)
            
            // Update local user object immediately for UI
            if var updatedUser = currentUser {
                updatedUser.fullName = fullName
                currentUser = updatedUser
            }
        } catch let error as NSError {
            // Convert Firebase errors to user-friendly messages
            let errorMessage: String
            switch error.code {
            case AuthErrorCode.requiresRecentLogin.rawValue:
                errorMessage = "Please sign in again to change your profile"
            case AuthErrorCode.networkError.rawValue:
                errorMessage = "Network connection error. Please try again"
            case AuthErrorCode.invalidEmail.rawValue:
                errorMessage = "Invalid email format"
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                errorMessage = "Email is already in use"
            case 7: // Firestore permission denied
                errorMessage = "Permission denied. Please sign in again"
            default:
                errorMessage = error.localizedDescription
            }
            throw NSError(domain: "", code: error.code,
                         userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
    
    func updateProfilePhoto(_ image: UIImage) async {
        guard let userId = auth.currentUser?.uid else {
            print("❌ No user ID available")
            return
        }
        
        do {
            print("🔄 Starting profile photo update process...")
            
            // 1. Save to local storage first
            saveImageToFile(image, userId: userId)
            
            // 2. Save to UserDefaults as backup
            if let imageData = image.jpegData(compressionQuality: 0.7) {
                UserDefaults.standard.set(imageData, forKey: "userProfilePhotoData_\(userId)")
                print("✅ Saved image data to UserDefaults")
            }
            
            // 3. Update UI immediately
            await MainActor.run {
                self.profileImage = image
                print("✅ Updated UI with new image")
            }
            
            // 4. Update Firestore
            let localPath = "profile_\(userId).jpg"
            let userData: [String: Any] = [
                "photoURL": localPath,
                "lastUpdated": Timestamp(date: Date()),
                "hasProfilePhoto": true,
                "photoLastUpdated": Timestamp(date: Date())
            ]
            
            try await db.collection("users").document(userId).setData(userData, merge: true)
            print("✅ Updated Firestore with new photo data")
            
            // 5. Update local user object
            if var updatedUser = currentUser {
                updatedUser.photoURL = localPath
                await MainActor.run {
                    self.currentUser = updatedUser
                    print("✅ Updated local user object")
                }
            }
            
            print("✅ Profile photo update completed successfully")
            
        } catch {
            print("❌ Error updating profile photo: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
            errorMessage = "Failed to update profile photo: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let email = auth.currentUser?.email else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user email found"])
        }
        
        // First, reauthenticate the user
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        try await auth.currentUser?.reauthenticate(with: credential)
        
        // Then change the password
        try await auth.currentUser?.updatePassword(to: newPassword)
        
        // Update the last updated timestamp in Firestore
        if let userId = auth.currentUser?.uid {
            try await db.collection("users").document(userId).setData([
                "lastUpdated": Timestamp(date: Date())
            ], merge: true)
        }
    }
    
    func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
                
                guard let idToken = result.user.idToken?.tokenString else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "ID token missing"])
                }
                
                let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                            accessToken: result.user.accessToken.tokenString)
                
                let authResult = try await auth.signIn(with: credential)
                
                // Save user data to Firestore
                let userData = [
                    "email": authResult.user.email ?? "",
                    "fullName": authResult.user.displayName ?? "",
                    "photoURL": authResult.user.photoURL?.absoluteString ?? "",
                    "lastUpdated": Timestamp(date: Date())
                ]
                try await db.collection("users").document(authResult.user.uid).setData(userData, merge: true)
                
                // Load user data including Firestore data
                try await loadUserData(authResult.user)
                
                // Create new session for welcome/welcome back notification
                if let token = try? await Messaging.messaging().token() {
                    try await db.collection("userSessions").addDocument(data: [
                        "userId": authResult.user.uid,
                        "deviceInfo": UIDevice.current.systemVersion,
                        "platform": "iOS",
                        "createdAt": FieldValue.serverTimestamp(),
                        "isNewUser": false,
                        "fcmToken": token
                    ])
                }
                
            } catch {
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }
    
    func signInWithApple() {
        let nonce = randomNonceString()
        currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            String(charset[Int(byte) % charset.count])
        }.joined()
        return nonce
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
    
    func requestAuthorization() async -> Bool {
        return await NotificationManager.shared.requestAuthorization()
    }
    
    func updateNotifications(enabled: Bool) async {
        if enabled {
            // Setup notifications
            await NotificationManager.shared.setupNotificationsAfterAuth()
        } else {
            // Clear notifications
            await NotificationManager.shared.clearNotificationSetup()
        }
    }
    
    func updateUserActiveStatus() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                try await db.collection("users").document(userId).updateData([
                    "lastActive": FieldValue.serverTimestamp(),
                    "fcmToken": UserDefaults.standard.string(forKey: "fcmToken") ?? ""
                ])
            } catch {
                print("Error updating user active status: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthViewModel: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("Unable to fetch identity token")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
                return
            }
            
            let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                    idToken: idTokenString,
                                                    rawNonce: nonce)
            
            Task {
                do {
                    let result = try await auth.signIn(with: credential)
                    
                    // Save user data to Firestore
                    let userData = [
                        "email": result.user.email ?? "",
                        "fullName": result.user.displayName ?? appleIDCredential.fullName?.givenName ?? "",
                        "photoURL": result.user.photoURL?.absoluteString ?? "",
                        "lastUpdated": Timestamp(date: Date())
                    ]
                    try await db.collection("users").document(result.user.uid).setData(userData, merge: true)
                    
                    // Load user data including Firestore data
                    try await loadUserData(result.user)
                    
                    // Setup notifications after successful Apple sign in
                    await NotificationManager.shared.setupNotificationsAfterAuth()
                    
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window found")
        }
        return window
    }
} 
