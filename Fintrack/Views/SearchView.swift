import SwiftUI
import FintrackModels

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Asset Type Selector
            Picker("Asset Type", selection: $viewModel.selectedAssetType) {
                Text("Crypto")
                    .tag(AssetType.crypto)
                Text("Stocks")
                    .tag(AssetType.stock)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Search Results
            ScrollView {
                VStack(spacing: 0) {
                    if searchText.isEmpty {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.top, 40)
                        } else if !viewModel.popularAssets.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Popular \(viewModel.selectedAssetType == .crypto ? "Cryptocurrencies" : "Stocks")")
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top)
                                
                                SearchResultView(searchResults: viewModel.popularAssets)
                            }
                        } else {
                            ContentUnavailableView("Popular Assets", systemImage: "chart.line.uptrend.xyaxis")
                                .padding(.top, 40)
                        }
                    } else {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.top, 40)
                        } else if let error = viewModel.error {
                            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                                .padding(.top, 40)
                        } else if viewModel.searchResults.isEmpty {
                            ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try searching with a different keyword"))
                                .padding(.top, 40)
                        } else {
                            SearchResultView(searchResults: viewModel.searchResults)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: viewModel.selectedAssetType == .crypto ? "Search cryptocurrencies..." : "Search stocks...")
        .focused($isSearchFocused)
        .onChange(of: searchText) { newValue in
            viewModel.search(query: newValue)
        }
        .onChange(of: viewModel.selectedAssetType) { _ in
            searchText = ""
            viewModel.clearResults()
            viewModel.loadPopularAssets()
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .background(backgroundColor)
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .primary
    }
}

struct DataCell: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 