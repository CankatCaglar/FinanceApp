import SwiftUI
import Charts
import FintrackModels

// MARK: - Time Range Enum
enum TimeRange {
    case day, week, month, year, all
}

struct AssetDetailView: View {
    let asset: Asset
    @State private var selectedTimeRange: TimeRange = .day
    @State private var showingAddToPortfolio = false
    @State private var quantity = ""
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var pricePoints: [PricePoint] {
        guard let priceHistory = asset.priceHistory else { return [] }
        return priceHistory
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AssetHeaderView(asset: asset)
                
                if !pricePoints.isEmpty {
                    PriceChartView(
                        priceHistory: pricePoints,
                        selectedTimeRange: $selectedTimeRange,
                        priceChangePercentage24H: asset.priceChangePercentage24H
                    )
                }
                
                MarketStatsView(asset: asset)
                SupplyInfoView(asset: asset)
                
                if asset.type != .stock {
                    AddToPortfolioButton(showingAddToPortfolio: $showingAddToPortfolio)
                }
                
                if let description = asset.description {
                    AssetDescriptionView(description: description)
                }
                
                if asset.type == .stock {
                    AssetLinksView(asset: asset)
                    AddToPortfolioButton(showingAddToPortfolio: $showingAddToPortfolio)
                }
            }
            .padding()
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddToPortfolio) {
            AddToPortfolioSheet(
                asset: asset,
                isPresented: $showingAddToPortfolio,
                quantity: $quantity
            )
        }
    }
}

// MARK: - Header View
private struct AssetHeaderView: View {
    let asset: Asset
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(asset.name)
                    .font(.title)
                    .fontWeight(.bold)
                Text(asset.symbol.uppercased())
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            
            Text("$\(asset.formattedPrice)")
                .font(.system(size: 34, weight: .bold))
            
            Text(String(format: "%@%.2f%%", asset.priceChangePercentage24H >= 0 ? "+" : "", asset.priceChangePercentage24H))
                .font(.title3)
                .foregroundColor(asset.priceChangePercentage24H >= 0 ? .green : .red)
        }
        .padding(.top)
    }
}

// MARK: - Price Chart View
private struct PriceChartView: View {
    let priceHistory: [PricePoint]
    @Binding var selectedTimeRange: TimeRange
    let priceChangePercentage24H: Double
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var filteredPriceHistory: [PricePoint] {
        let calendar = Calendar.current
        let now = Date()
        
        let filteredPoints = priceHistory.filter { point in
            switch selectedTimeRange {
            case .day:
                let dayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
                return point.date >= dayAgo
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return point.date >= weekAgo
            case .month:
                let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return point.date >= monthAgo
            case .year:
                let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
                return point.date >= yearAgo
            case .all:
                return true
            }
        }
        
        return filteredPoints.sorted { $0.date < $1.date }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Price Chart")
                .font(.headline)
            
            if !filteredPriceHistory.isEmpty {
                Chart(filteredPriceHistory) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Price", point.price)
                    )
                    .foregroundStyle(priceChangePercentage24H >= 0 ? .green : .red)
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: selectedTimeRange == .day ? 
                            .dateTime.hour() :
                            selectedTimeRange == .week ? 
                                .dateTime.weekday() :
                                selectedTimeRange == .month ?
                                    .dateTime.day() :
                                    .dateTime.month()
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .currency(code: "USD"))
                    }
                }
            } else {
                Text("No price data available")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            }
            
            TimeRangeSelectorView(selectedTimeRange: $selectedTimeRange)
        }
        .padding()
        .background(backgroundColor)
    }
}

// MARK: - Market Stats View
private struct MarketStatsView: View {
    let asset: Asset
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Market Stats")
                .font(.headline)
            
            MarketStatRow(title: "Market Cap", value: formatCurrency(asset.marketCap))
            if asset.type == .crypto {
                MarketStatRow(title: "24h Volume", value: formatCurrency(asset.volume24H))
            }
            MarketStatRow(title: "24h High", value: String(format: "$%.2f", asset.high24H))
            MarketStatRow(title: "24h Low", value: String(format: "$%.2f", asset.low24H))
            
            if (asset.marketCapRank ?? 0) > 0 {
                MarketStatRow(title: "Market Cap Rank", value: "#\(asset.marketCapRank ?? 0)")
            }
        }
        .padding()
        .background(backgroundColor)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        let formattedNumber: String
        if value >= trillion {
            formattedNumber = String(format: "%.2fT", value / trillion)
        } else if value >= billion {
            formattedNumber = String(format: "%.2fB", value / billion)
        } else if value >= million {
            formattedNumber = String(format: "%.2fM", value / million)
        } else if value >= thousand {
            formattedNumber = String(format: "%.2f", value / thousand)
        } else {
            formattedNumber = String(format: "%.2f", value)
        }
        
        return "$" + formattedNumber
    }
}

// MARK: - Supply Info View
private struct SupplyInfoView: View {
    let asset: Asset
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supply Information")
                .font(.headline)
            
            MarketStatRow(title: "Circulating Supply", value: formatNumber(asset.circulatingSupply))
            
            if let totalSupply = asset.totalSupply {
                MarketStatRow(title: "Total Supply", value: formatNumber(totalSupply))
            }
            
            if let maxSupply = asset.maxSupply {
                MarketStatRow(title: "Max Supply", value: formatNumber(maxSupply))
            }
        }
        .padding()
        .background(backgroundColor)
    }
    
    private func formatNumber(_ value: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        if value >= trillion {
            return String(format: "%.2fT", value / trillion)
        } else if value >= billion {
            return String(format: "%.2fB", value / billion)
        } else if value >= million {
            return String(format: "%.2fM", value / million)
        } else if value >= thousand {
            return String(format: "%.2fK", value / thousand)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Asset Description View
private struct AssetDescriptionView: View {
    let description: String
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(backgroundColor)
    }
}

// MARK: - Asset Links View
private struct AssetLinksView: View {
    let asset: Asset
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links")
                .font(.headline)
            
            if let homepage = asset.homepageURL {
                LinkRow(title: "Website", url: homepage)
            }
            if let github = asset.githubURL {
                LinkRow(title: "GitHub", url: github)
            }
            if let reddit = asset.redditURL {
                LinkRow(title: "Reddit", url: reddit)
            }
            if let twitter = asset.twitterUsername {
                LinkRow(title: "Twitter", url: "https://twitter.com/\(twitter)")
            }
        }
        .padding()
        .background(backgroundColor)
    }
}

// MARK: - Supporting Views
struct MarketStatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct LinkRow: View {
    let title: String
    let url: String
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                    .foregroundColor(.blue)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Time Range Selector View
private struct TimeRangeSelectorView: View {
    @Binding var selectedTimeRange: TimeRange
    @Environment(\.colorScheme) private var colorScheme
    
    private var buttonTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        HStack {
            ForEach([TimeRange.day, .week, .month, .year, .all], id: \.self) { range in
                Button(action: {
                    selectedTimeRange = range
                }) {
                    Text(timeRangeText(range))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTimeRange == range ? Color(red: 0.0, green: 0.478, blue: 1.0) : Color.clear)
                        .foregroundColor(selectedTimeRange == range ? .white : buttonTextColor)
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private func timeRangeText(_ range: TimeRange) -> String {
        switch range {
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .year: return "1Y"
        case .all: return "ALL"
        }
    }
}

// MARK: - Add to Portfolio Button
private struct AddToPortfolioButton: View {
    @Binding var showingAddToPortfolio: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            showingAddToPortfolio = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add to Portfolio")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.black)
            .padding(.vertical, 16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add to Portfolio Sheet
private struct AddToPortfolioSheet: View {
    let asset: Asset
    @Binding var isPresented: Bool
    @Binding var quantity: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var showError = false
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var isValidQuantity: Bool {
        if let value = Double(quantity.replacingOccurrences(of: ",", with: ".")) {
            return value > 0
        }
        return false
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField("Quantity", text: $quantity)
                            .keyboardType(.decimalPad)
                            .onChange(of: quantity) { newValue in
                                // Allow only numbers and one decimal separator
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
                    } header: {
                        Text("Add to Portfolio")
                    } footer: {
                        if showError {
                            Text("Please enter a valid quantity greater than 0")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section {
                        Button(action: {
                            if let quantityValue = Double(quantity.replacingOccurrences(of: ",", with: ".")) {
                                if quantityValue > 0 {
                                    PortfolioViewModel.shared.addAsset(
                                        type: asset.type,
                                        symbol: asset.symbol.uppercased(),
                                        quantity: quantityValue
                                    )
                                    isPresented = false
                                    quantity = ""
                                    showError = false
                                } else {
                                    showError = true
                                }
                            } else {
                                showError = true
                            }
                        }) {
                            Text("Add")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .foregroundColor(isValidQuantity ? .black : .gray)
                                .padding(.vertical, 16)
                                .background(isValidQuantity ? Color.white : Color(uiColor: .systemGray5))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(isValidQuantity ? 0.1 : 0), radius: 2, x: 0, y: 1)
                        }
                        .disabled(!isValidQuantity)
                        .listRowBackground(backgroundColor)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(backgroundColor)
            }
            .background(backgroundColor)
            .navigationTitle(asset.symbol.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
                quantity = ""
            })
        }
    }
} 