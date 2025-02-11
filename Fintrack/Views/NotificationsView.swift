import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    
    var body: some View {
        ContentUnavailableView(
            "No Notifications",
            systemImage: "bell.slash",
            description: Text("You don't have any notifications yet")
        )
        .task {
            // Clear notifications when view appears
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
        }
    }
}

struct NotificationCell: View {
    let notification: NotificationItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: notification.type == "PRICE_CHANGE" ? "chart.line.uptrend.xyaxis" : "newspaper")
                    .foregroundColor(notification.type == "PRICE_CHANGE" ? .blue : .green)
                Text(notification.title)
                    .font(.headline)
            }
            Text(notification.body)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(notification.timestamp.formatted())
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

class NotificationsViewModel: ObservableObject {
    @Published var notifications: [NotificationItem] = []
    private let db = Firestore.firestore()
    
    init() {
        Task {
            await loadNotifications()
        }
    }
    
    @MainActor
    func loadNotifications() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Clear badge count when loading notifications
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
            
            let snapshot = try await db.collection("users").document(userId)
                .collection("unreadNotifications")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            self.notifications = snapshot.documents.compactMap { document in
                guard let data = document.data()["data"] as? [String: Any],
                      let type = document.data()["type"] as? String,
                      let timestamp = (document.data()["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil as NotificationItem?
                }
                
                switch type {
                case "PRICE_CHANGE":
                    guard let symbol = data["symbol"] as? String,
                          let name = data["name"] as? String,
                          let direction = data["direction"] as? String,
                          let change = data["change"] as? String,
                          let price = data["price"] as? String else {
                        return nil
                    }
                    
                    return NotificationItem(
                        id: document.documentID,
                        type: type,
                        title: "Price Alert: \(symbol)",
                        body: "\(name) has moved \(direction) by \(change)% (Current Price: $\(price))",
                        timestamp: timestamp
                    )
                    
                case "NEWS":
                    guard let title = data["title"] as? String,
                          let source = data["source"] as? String else {
                        return nil
                    }
                    
                    return NotificationItem(
                        id: document.documentID,
                        type: type,
                        title: "Breaking News",
                        body: "\(source): \(title)",
                        timestamp: timestamp
                    )
                    
                default:
                    return nil
                }
            }
        } catch {
            print("Error loading notifications: \(error)")
        }
    }
}

struct NotificationItem: Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String
    let timestamp: Date
} 