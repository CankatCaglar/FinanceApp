import SwiftUI
import FintrackModels

struct AddAssetSheet: View {
    @Binding var isPresented: Bool
    @Binding var assetType: AssetType
    @Binding var symbol: String
    @Binding var quantity: String
    let onAdd: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @StateObject private var searchVM = SearchViewModel()
    @State private var searchText = ""
    @State private var selectedAsset: Asset?
    @StateObject private var viewModel = PortfolioViewModel.shared
    
    private enum Field {
        case search, quantity
    }
    
    private var isValid: Bool {
        guard selectedAsset != nil else { return false }
        guard let quantityValue = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { return false }
        return quantityValue > 0
    }
    
    private var inputBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
    }
    
    private var buttonBackgroundColor: Color {
        Color.white
    }
    
    private func formatPrice(_ price: Double) -> String {
        return "$" + String(format: "%.2f", price)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        colorScheme == .dark ? Color.black : Color(.systemGray6),
                        colorScheme == .dark ? Color(.systemGray6).opacity(0.1) : Color(.systemBackground)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Section
                    VStack(spacing: 24) {
                        // Asset Type Selector
                        VStack(spacing: 8) {
                            Text("Select Asset Type")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Picker("Asset Type", selection: $assetType) {
                                Text("Cryptocurrency").tag(AssetType.crypto)
                                Text("Stock").tag(AssetType.stock)
                            }
                            .pickerStyle(.segmented)
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(inputBackgroundColor)
                            )
                            .onChange(of: assetType) { _ in
                                searchText = ""
                                selectedAsset = nil
                                searchVM.selectedAssetType = assetType
                            }
                        }
                        
                        // Search and Input Fields
                        VStack(spacing: 20) {
                            // Search Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Search Asset")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .placeholder(when: searchText.isEmpty) {
                                        Text(assetType == .crypto ? "Search cryptocurrencies..." : "Search stocks...")
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .padding()
                                    .background(inputBackgroundColor)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                    .textInputAutocapitalization(.never)
                                    .focused($focusedField, equals: .search)
                                    .onChange(of: searchText) { newValue in
                                        searchVM.search(query: newValue)
                                    }
                            }
                            
                            // Search Results
                            if !searchText.isEmpty {
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(searchVM.searchResults) { asset in
                                            Button(action: {
                                                selectedAsset = asset
                                                symbol = asset.symbol
                                                searchText = ""
                                            }) {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(asset.symbol)
                                                            .font(.headline)
                                                            .foregroundColor(.primary)
                                                        Text(asset.name)
                                                            .font(.subheadline)
                                                            .foregroundColor(.gray)
                                                    }
                                                    Spacer()
                                                    Text(formatPrice(asset.currentPrice))
                                                        .foregroundColor(.primary)
                                                }
                                                .padding()
                                                .background(selectedAsset?.id == asset.id ? buttonBackgroundColor : Color.clear)
                                                .cornerRadius(12)
                                                .shadow(color: Color.black.opacity(selectedAsset?.id == asset.id ? 0.1 : 0), radius: 2, x: 0, y: 1)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            Divider()
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                            }
                            
                            // Selected Asset Display
                            if let asset = selectedAsset {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Selected Asset")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                        Text("\(asset.symbol) - \(asset.name)")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                    Text(formatPrice(asset.currentPrice))
                                        .foregroundColor(.primary)
                                }
                                .padding()
                                .background(inputBackgroundColor)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                            
                            // Quantity Input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Quantity")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("", text: $quantity)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .placeholder(when: quantity.isEmpty) {
                                        Text("Enter amount")
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .padding()
                                    .background(inputBackgroundColor)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .quantity)
                                    .onChange(of: quantity) { newValue in
                                        let filtered = newValue.filter { "0123456789,.".contains($0) }
                                        if filtered != newValue {
                                            quantity = filtered
                                        }
                                        
                                        // Ensure only one decimal separator
                                        let dots = filtered.filter { $0 == "." }.count
                                        let commas = filtered.filter { $0 == "," }.count
                                        if dots + commas > 1 {
                                            let parts = filtered.split { $0 == "." || $0 == "," }
                                            if parts.count > 1 {
                                                quantity = String(parts[0]) + "." + String(parts[1])
                                            }
                                        }
                                        
                                        // Allow up to 8 decimal places
                                        let parts = quantity.split(separator: ".")
                                        if parts.count == 2 && parts[1].count > 8 {
                                            quantity = String(parts[0]) + "." + String(parts[1].prefix(8))
                                        }
                                    }
                            }
                        }
                    }
                    .padding(24)
                    
                    Spacer()
                    
                    // Add Button
                    Button(action: {
                        onAdd()
                        dismiss()
                    }) {
                        Text("Add to Portfolio")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isValid ? buttonBackgroundColor : Color(uiColor: .systemGray5))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(isValid ? 0.1 : 0), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isValid)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .padding(.top, -20)
                }
            }
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.primary)
                }
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
} 
