import SwiftUI
import RevenueCat
import FirebaseAuth
import FirebaseFirestore

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var revenueCat = RevenueCatManager.shared
    @State private var selectedPlan: SubscriptionPlan = .monthly
    
    enum SubscriptionPlan {
        case monthly, yearly
    }
    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header with Animation
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Upgrade to Premium")
                            .font(.system(size: 32, weight: .bold))
                        
                        Text("Start with 1-week free trial")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Text("Take your financial tracking to the next level")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)
                    
                    // Plan Selection Cards
                    VStack(spacing: 16) {
                        // Monthly Plan Card
                        PlanCard(
                            isSelected: selectedPlan == .monthly,
                            planType: "Monthly",
                            price: "$1.99",
                            period: "month",
                            trialText: "7 days free trial",
                            action: { withAnimation { selectedPlan = .monthly } }
                        )
                        
                        // Yearly Plan Card
                        PlanCard(
                            isSelected: selectedPlan == .yearly,
                            planType: "Yearly",
                            price: "$14.99",
                            period: "year",
                            trialText: "7 days free trial",
                            savings: "Save 37%",
                            action: { withAnimation { selectedPlan = .yearly } }
                        )
                    }
                    .padding(.horizontal)
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Everything in Premium")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        VStack(spacing: 20) {
                            FeatureRowView(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Advanced Analytics",
                                description: "Deep insights into your finances"
                            )
                            
                            FeatureRowView(
                                icon: "bell.badge.fill",
                                title: "Smart Alerts",
                                description: "Customizable notifications for your goals"
                            )
                            
                            FeatureRowView(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Automated Tracking",
                                description: "Auto-sync with your accounts"
                            )
                            
                            FeatureRowView(
                                icon: "chart.pie.fill",
                                title: "Portfolio Analysis",
                                description: "Advanced investment insights"
                            )
                            
                            FeatureRowView(
                                icon: "person.2.fill",
                                title: "Priority Support",
                                description: "24/7 premium customer service"
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 32)
                    
                    // Subscribe Button and Terms
                    VStack(spacing: 12) {
                        Button {
                            handleSubscription()
                        } label: {
                            HStack {
                                Text("Start Premium")
                                    .font(.headline)
                                Image(systemName: "arrow.right")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal)
                        
                        VStack(spacing: 4) {
                            Text("Cancel anytime")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button {
                                Task {
                                    try? await revenueCat.restorePurchases()
                                }
                            } label: {
                                Text("Restore Purchases")
                                    .font(.footnote)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
    }
    
    private func handleSubscription() {
        Task {
            if let offerings = revenueCat.offerings,
               let offering = offerings.current,
               let package = selectedPlan == .monthly ? offering.monthly : offering.annual {
                do {
                    try await revenueCat.purchase(package: package)
                    dismiss()
                } catch {
                    print("Purchase failed:", error.localizedDescription)
                }
            }
        }
    }
}

struct PlanCard: View {
    let isSelected: Bool
    let planType: String
    let price: String
    let period: String
    var trialText: String? = nil
    var savings: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planType)
                        .font(.headline)
                    
                    if let trialText = trialText {
                        Text(trialText)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.system(size: 28, weight: .bold))
                        Text("/ \(period)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    if let savings = savings {
                        Text(savings)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
} 