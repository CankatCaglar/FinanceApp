import Foundation
import RevenueCat
import FirebaseAuth
import FirebaseFirestore

class RevenueCatManager: ObservableObject {
    static let shared = RevenueCatManager()
    
    @Published var offerings: Offerings?
    @Published var customerInfo: CustomerInfo?
    @Published var isSubscribed = false
    
    private let monthlyId = "fintrack_pro_monthly"
    private let yearlyId = "fintrack_pro_yearly"
    
    private init() {
        // Configure RevenueCat
        Purchases.configure(withAPIKey: "appl_SSGijvZKouqdwkweuqZOvLRTfnw")
        
        // Initial fetch
        Task {
            try? await fetchOfferings()
            try? await updateCustomerInfo()
        }
        
        // Setup authentication listener
        setupAuthenticationListener()
    }
    
    private func setupAuthenticationListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let userId = user?.uid {
                Task {
                    do {
                        let (customerInfo, _) = try await Purchases.shared.logIn(userId)
                        await MainActor.run {
                            self?.customerInfo = customerInfo
                            self?.isSubscribed = customerInfo.entitlements["premium"]?.isActive == true
                        }
                    } catch {
                        print("RevenueCat login error:", error.localizedDescription)
                    }
                }
            } else {
                // User logged out
                Task {
                    try? await Purchases.shared.logOut()
                }
            }
        }
    }
    
    @MainActor
    func fetchOfferings() async throws {
        offerings = try await Purchases.shared.offerings()
    }
    
    @MainActor
    func updateCustomerInfo() async throws {
        customerInfo = try await Purchases.shared.customerInfo()
        isSubscribed = customerInfo?.entitlements["premium"]?.isActive == true
    }
    
    func purchase(package: Package) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "RevenueCatManager",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let result = try await Purchases.shared.purchase(package: package)
        
        // Update Firestore with subscription info
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        
        let data: [String: Any] = [
            "subscriptionType": package.identifier,
            "subscriptionEndDate": result.customerInfo.latestExpirationDate as Any,
            "lastUpdated": Timestamp(date: Date())
        ]
        
        try await userRef.setData(data, merge: true)
        
        // Update local state
        await MainActor.run {
            self.customerInfo = result.customerInfo
            self.isSubscribed = result.customerInfo.entitlements["premium"]?.isActive == true
        }
    }
    
    func restorePurchases() async throws {
        let customerInfo = try await Purchases.shared.restorePurchases()
        await MainActor.run {
            self.customerInfo = customerInfo
            self.isSubscribed = customerInfo.entitlements["premium"]?.isActive == true
        }
    }
    
    func checkSubscriptionStatus() async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            return customerInfo.entitlements["premium"]?.isActive == true
        } catch {
            print("Error checking subscription status:", error.localizedDescription)
            return false
        }
    }
} 