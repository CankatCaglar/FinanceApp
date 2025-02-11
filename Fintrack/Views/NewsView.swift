import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel.shared
    @StateObject private var authViewModel = AuthViewModel.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    private var navigationTitle: String {
        switch viewModel.selectedCategory {
        case .all:
            return "News"
        case .stocks:
            return "Stock News"
        case .crypto:
            return "Crypto News"
        }
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading news...")
            } else if viewModel.error != nil {
                ContentUnavailableView(
                    "Error Loading News",
                    systemImage: "exclamationmark.triangle",
                    description: Text(viewModel.error ?? "Unknown error")
                )
            } else if viewModel.news.isEmpty {
                ContentUnavailableView(
                    "No News",
                    systemImage: "newspaper",
                    description: Text("Check back later for market updates")
                )
            } else {
                List(viewModel.news) { newsItem in
                    NewsCard(article: newsItem)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 8)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(NewsCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) {
                            viewModel.changeCategory(category)
                        }
                    }
                } label: {
                    Label("Category", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable {
            await viewModel.refreshNews()
        }
        .task {
            await viewModel.refreshNews()
        }
    }
}

struct NewsArticleRow: View {
    let article: NewsItem
    
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: article.publishedAt, relativeTo: Date())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.headline)
                .font(.headline)
                .lineLimit(2)
            
            HStack {
                Text(article.source)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CategorySelectorView: View {
    @Binding var selectedCategory: NewsCategory
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(NewsCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: category == selectedCategory,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct CategoryButton: View {
    let category: NewsCategory
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(category.rawValue)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ? 
                        Color.accentColor : 
                        Color(colorScheme == .dark ? .systemGray5 : .systemGray6)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct NewsCard: View {
    let article: NewsItem
    @Environment(\.colorScheme) private var colorScheme
    
    private let contentWidth: CGFloat = UIScreen.main.bounds.width * 0.93
    private let cornerRadius: CGFloat = 12
    
    var timeAgoText: String {
        let interval = Date().timeIntervalSince(article.publishedAt)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let days = hours / 24
        
        if days > 0 {
            return "\(days)d ago"
        } else if hours > 0 {
            return "\(hours)h ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "Just now"
        }
    }
    
    var body: some View {
        Link(destination: URL(string: article.url)!) {
            VStack(alignment: .leading, spacing: 0) {
                // Image Section
                if let imageUrl = article.imageUrl {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: contentWidth)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                        case .failure:
                            Rectangle()
                                .fill(Color(colorScheme == .dark ? .systemGray5 : .systemGray6))
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: contentWidth)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.title)
                                        .foregroundColor(.gray)
                                }
                        case .empty:
                            Rectangle()
                                .fill(Color(colorScheme == .dark ? .systemGray5 : .systemGray6))
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(width: contentWidth)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Content Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.headline)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .padding(.top, 12)
                        .frame(width: contentWidth, alignment: .leading)
                    
                    Text(article.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(width: contentWidth, alignment: .leading)
                    
                    HStack(spacing: 12) {
                        Text(article.source)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                        
                        Text(timeAgoText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .background(Color(colorScheme == .dark ? .black : .white))
        }
        .buttonStyle(.plain)
    }
} 
