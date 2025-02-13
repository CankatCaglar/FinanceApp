import SwiftUI
import Charts
import FintrackModels
import Combine

// MARK: - Time Range Enum
enum TimeRange: String, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case sixMonths = "6M"
    case year = "1Y"
    case twoYears = "2Y"
    case fiveYears = "5Y"
    
    var title: String { rawValue }
    
    static func availableRanges(for assetType: AssetType) -> [TimeRange] {
        switch assetType {
        case .crypto:
            return [.day, .week, .month, .sixMonths, .year, .twoYears]
        case .stock:
            return allCases
        }
    }
    
    var days: Int {
        switch self {
        case .day: return 1       // Saatlik veri (24 nokta)
        case .week: return 7      // Saatlik veri (168 nokta)
        case .month: return 30    // Saatlik veri (720 nokta)
        case .sixMonths: return 180  // Günlük veri (180 nokta)
        case .year: return 365    // Günlük veri (365 nokta)
        case .twoYears: return 730   // Günlük veri (730 nokta)
        case .fiveYears: return 1825 // Günlük veri (1825 nokta)
        }
    }
    
    var description: String {
        switch self {
        case .day: return "Saatlik veri"
        case .week, .month: return "Saatlik veri"
        case .sixMonths, .year, .twoYears, .fiveYears: return "Günlük veri"
        }
    }
}

// MARK: - Array Extension
fileprivate extension Array {
    func strideArray(by stride: Int) -> [Element] {
        guard stride > 0 else { return self }
        return enumerated()
            .filter { $0.offset % stride == 0 }
            .map { $0.element }
    }
}

// MARK: - Price API Service
class PriceAPIService {
    static let shared = PriceAPIService()
    private let coinMarketCapBaseURL = "https://pro-api.coinmarketcap.com/v2"
    private let coinMarketCapAPIKey = "1bc94c4b-bb47-4da7-9b5d-10d72663324f"
    
    // Rate limit handling
    private var lastRequestTime: Date?
    private var minimumRequestInterval: TimeInterval = 30 // 30 seconds between requests
    
    // CoinMarketCap ID mappings for common cryptocurrencies
    private let coinMarketCapIdMap: [String: Int] = [
        "BTC": 1,
        "ETH": 1027,
        "USDT": 825,
        "BNB": 1839,
        "SOL": 5426,
        "XRP": 52,
        "USDC": 3408,
        "ADA": 2010,
        "AVAX": 5805,
        "DOGE": 74,
        "TRX": 1958,
        "DOT": 6636,
        "LINK": 1975,
        "MATIC": 3890,
        "UNI": 7083,
        "SHIB": 5994,
        "LTC": 2,
        "ATOM": 3794,
        "XLM": 512,
        "BCH": 1831,
        "NEAR": 6535,
        "ALGO": 4030,
        "ICP": 8916,
        "FIL": 2280,
        "VET": 3077,
        "HBAR": 4642,
        "MANA": 1966,
        "SAND": 6210,
        "XTZ": 2011,
        "EOS": 1765,
        "THETA": 2416,
        "AXS": 6783,
        "AAVE": 7278,
        "GRT": 6719,
        "FTM": 3513,
        "NEO": 1376,
        "WAVES": 1274,
        "CHZ": 4066,
        "BAT": 1697,
        "ZIL": 2469,
        "ENJ": 2130,
        "DASH": 131,
        "CAKE": 7186,
        "ONE": 3945,
        "HOT": 2682,
        "XEM": 873,
        "QTUM": 1684,
        "ZRX": 1896,
        "OMG": 1808
    ]
    
    // Cache for dynamic coin IDs
    private var dynamicCoinIds: [String: Int] = [:]
    
    private func fetchCoinId(for symbol: String) async throws -> Int? {
        // Check cache first
        if let cachedId = dynamicCoinIds[symbol.uppercased()] {
            return cachedId
        }
        
        // If not in cache, fetch from API
        let urlString = "https://pro-api.coinmarketcap.com/v1/cryptocurrency/map"
        var components = URLComponents(string: urlString)!
        
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol.uppercased())
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.addValue(coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("CoinMarketCap Map Response Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("CoinMarketCap Map Error Response: \(responseString)")
                }
                throw URLError(.badServerResponse)
            }
            
            // Debug: Print the map response
            if let responseString = String(data: data, encoding: .utf8) {
                print("CoinMarketCap Map Response for \(symbol): \(responseString)")
            }
        }
        
        struct MapResponse: Codable {
            struct CoinData: Codable {
                let id: Int
                let symbol: String
            }
            let data: [CoinData]
        }
        
        let mapResponse = try JSONDecoder().decode(MapResponse.self, from: data)
        
        // Find the first active listing for this symbol
        if let coin = mapResponse.data.first(where: { $0.symbol == symbol.uppercased() }) {
            // Cache the result
            dynamicCoinIds[symbol.uppercased()] = coin.id
            return coin.id
        }
        
        return nil
    }
    
    private func getCoinMarketCapId(for symbol: String) async throws -> Int? {
        // First check the static map
        if let staticId = coinMarketCapIdMap[symbol.uppercased()] {
            return staticId
        }
        
        // If not found in static map, try to fetch dynamically
        return try await fetchCoinId(for: symbol)
    }
    
    private func fetchCryptoHistoryFromCMC(symbol: String, days: Int) async throws -> [PricePoint] {
        guard let coinId = try await getCoinMarketCapId(for: symbol) else {
            throw NSError(domain: "CoinMarketCap",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Unsupported cryptocurrency: \(symbol)"])
        }
        
        // Calculate time range
        let endTime = Int(Date().timeIntervalSince1970)
        let startTime = endTime - (days * 24 * 60 * 60)
        
        // Determine interval based on time range
        let interval: String
        switch days {
        case 1...7: interval = "1h"  // 1 hour for 1 day to 1 week
        case 8...30: interval = "1h" // 1 hour for 1 month
        case 31...90: interval = "1h" // 1 hour for 3 months
        default: interval = "1d"     // 1 day for longer periods
        }
        
        let urlString = "\(coinMarketCapBaseURL)/cryptocurrency/quotes/historical"
        var components = URLComponents(string: urlString)!
        
        components.queryItems = [
            URLQueryItem(name: "id", value: String(coinId)),
            URLQueryItem(name: "time_start", value: String(startTime)),
            URLQueryItem(name: "time_end", value: String(endTime)),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "convert", value: "USD")
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.addValue(coinMarketCapAPIKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        
        print("CoinMarketCap Request URL: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("CoinMarketCap Response Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("CoinMarketCap Error Response: \(responseString)")
                }
                throw URLError(.badServerResponse)
            }
            
            // Debug: Print response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("CoinMarketCap Response: \(responseString)")
            }
        }
        
        struct CMCQuote: Codable {
            let timestamp: String
            let quote: [String: Quote]
            
            struct Quote: Codable {
                let price: Double
            }
        }
        
        struct CMCResponse: Codable {
            let data: DataResponse
            
            struct DataResponse: Codable {
                let quotes: [CMCQuote]
                
                private enum CodingKeys: String, CodingKey {
                    case quotes = "quotes"
                }
            }
        }
        
        let cmcResponse = try JSONDecoder().decode(CMCResponse.self, from: data)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let quotes = cmcResponse.data.quotes.compactMap { quote -> PricePoint? in
            guard let date = dateFormatter.date(from: quote.timestamp),
                  let usdQuote = quote.quote["USD"] else {
                return nil
            }
            return PricePoint(date: date, price: usdQuote.price)
        }
        
        return quotes.sorted { $0.date < $1.date }
    }
    
    func fetchPriceHistory(for asset: Asset, days: Int) async throws -> [PricePoint] {
        switch asset.type {
        case .crypto:
            return try await fetchCryptoHistoryFromCMC(symbol: asset.symbol, days: days)
        case .stock:
            return try await fetchStockHistory(symbol: asset.symbol, days: days)
        }
    }
    
    private func fetchStockHistory(symbol: String, days: Int) async throws -> [PricePoint] {
        // Calculate time range
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
        
        let interval: String
        switch days {
        case 1: interval = "2m"      // 2-minute intervals for 1 day
        case 2...7: interval = "15m"  // 15-minute intervals for 1 week
        case 8...30: interval = "1h"  // 1-hour intervals for 1 month
        default: interval = "1d"      // Daily intervals for longer periods
        }
        
        // Format dates for Yahoo Finance
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        // Construct Yahoo Finance API URL
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?period1=\(startTimestamp)&period2=\(endTimestamp)&interval=\(interval)"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        print("Yahoo Finance Request URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        let (data, httpResponse) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            print("Yahoo Finance Response Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Yahoo Finance Error Response: \(responseString)")
                }
                throw URLError(.badServerResponse)
            }
            
            // Debug: Print response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("Yahoo Finance Response: \(responseString)")
            }
        }
        
        // Parse Yahoo Finance response
        struct YahooFinanceResponse: Codable {
            let chart: Chart
            
            struct Chart: Codable {
                let result: [Result]?
                let error: YahooError?
                
                struct Result: Codable {
                    let timestamp: [Int]
                    let indicators: Indicators
                    
                    struct Indicators: Codable {
                        let quote: [Quote]
                        
                        struct Quote: Codable {
                            let close: [Double?]
                            let open: [Double?]
                            let high: [Double?]
                            let low: [Double?]
                        }
                    }
                }
                
                struct YahooError: Codable {
                    let code: String
                    let description: String
                }
            }
        }
        
        let yahooResponse = try JSONDecoder().decode(YahooFinanceResponse.self, from: data)
        
        if let error = yahooResponse.chart.error {
            throw NSError(domain: "YahooFinance",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: error.description])
        }
        
        guard let result = yahooResponse.chart.result?.first,
              let quotes = result.indicators.quote.first else {
            throw NSError(domain: "YahooFinance",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No data available"])
        }
        
        // Create price points from the response
        var pricePoints: [PricePoint] = []
        
        for (index, timestamp) in result.timestamp.enumerated() {
            if let closePrice = quotes.close[index] {
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                pricePoints.append(PricePoint(date: date, price: closePrice))
            }
        }
        
        return pricePoints.sorted { $0.date < $1.date }
    }
}

// MARK: - Asset Detail View Model
@MainActor
class AssetDetailViewModel: ObservableObject {
    @Published private(set) var priceHistory: [PricePoint] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let asset: Asset
    private var currentTimeRange: TimeRange = .day
    private var lastFetchTime: [TimeRange: Date] = [:]
    private var currentTask: Task<Void, Never>?
    
    init(asset: Asset) {
        print("Initializing AssetDetailViewModel for \(asset.symbol) (type: \(asset.type))")
        self.asset = asset
        setupPriceUpdates()
    }
    
    private func setupPriceUpdates() {
        // Initial fetch
        Task {
            await fetchPriceHistory(for: currentTimeRange)
        }
        
        // Setup timer for periodic updates
        setupRefreshTimer()
    }
    
    private func setupRefreshTimer() {
        timer?.invalidate()
        
        let interval: TimeInterval
        switch currentTimeRange {
        case .day:
            interval = 120 // 2 minutes for real-time data
        case .week:
            interval = 300 // 5 minutes
        default:
            interval = 600 // 10 minutes for longer timeframes
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.fetchPriceHistory(for: self.currentTimeRange)
            }
        }
    }
    
    func updateTimeRange(_ newRange: TimeRange) {
        guard newRange != currentTimeRange else { return }
        
        // Cancel any ongoing fetch task
        currentTask?.cancel()
        
        // Update current time range immediately
        currentTimeRange = newRange
        
        // Reset data for immediate UI feedback
        priceHistory = []
        error = nil
        
        // Start new fetch task
        currentTask = Task {
            await fetchPriceHistory(for: newRange)
        }
        
        // Update timer interval based on new range
        setupRefreshTimer()
    }
    
    private func shouldFetchData(for timeRange: TimeRange) -> Bool {
        guard let lastFetch = lastFetchTime[timeRange] else {
            return true
        }
        
        let minimumInterval: TimeInterval
        switch timeRange {
        case .day:
            minimumInterval = 30 // 30 seconds
        case .week:
            minimumInterval = 60 // 1 minute
        case .month:
            minimumInterval = 120 // 2 minutes
        default:
            minimumInterval = 300 // 5 minutes
        }
        
        return Date().timeIntervalSince(lastFetch) >= minimumInterval
    }
    
    private func fetchPriceHistory(for timeRange: TimeRange) async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            let newPriceHistory = try await PriceAPIService.shared.fetchPriceHistory(
                for: asset,
                days: timeRange.days
            )
            
            // Check if this is still the current time range
            guard timeRange == currentTimeRange else { return }
            
            await MainActor.run {
                self.priceHistory = newPriceHistory
                self.isLoading = false
                self.lastFetchTime[timeRange] = Date()
            }
        } catch {
            // Check if this is still the current time range
            guard timeRange == currentTimeRange else { return }
            
            await MainActor.run {
                self.error = error
                self.isLoading = false
                print("Error fetching price history: \(error)")
            }
        }
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        currentTask?.cancel()
    }
}

struct AssetDetailView: View {
    let asset: Asset
    @StateObject private var viewModel: AssetDetailViewModel
    @State private var selectedTimeRange: TimeRange = .day
    @State private var showingAddToPortfolio = false
    @State private var quantity = ""
    @Environment(\.colorScheme) private var colorScheme
    
    init(asset: Asset) {
        print("Initializing AssetDetailView for \(asset.symbol) (type: \(asset.type))")
        self.asset = asset
        _viewModel = StateObject(wrappedValue: AssetDetailViewModel(asset: asset))
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AssetHeaderView(asset: asset)
                
                if viewModel.isLoading && viewModel.priceHistory.isEmpty {
                    ProgressView()
                        .frame(height: 250)
                } else if !viewModel.priceHistory.isEmpty {
                    PriceChartView(
                        priceHistory: viewModel.priceHistory,
                        selectedTimeRange: $selectedTimeRange,
                        priceChangePercentage24H: asset.priceChangePercentage24H
                    )
                    .id(selectedTimeRange) // Force view refresh when time range changes
                }
                
                if let error = viewModel.error {
                    Text("Failed to load price data: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .padding()
                }
                
                TimeRangeSelectorView(asset: asset, selectedTimeRange: $selectedTimeRange)
                    .onChange(of: selectedTimeRange) { newRange in
                        print("Time range changed to: \(newRange)")
                        viewModel.updateTimeRange(newRange)
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
    
    private func formatPrice(_ price: Double) -> String {
        if price < 0.0001 {
            return String(format: "$%.8f", price)
        } else if price < 0.01 {
            return String(format: "$%.6f", price)
        } else if price < 1 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.2f", price)
        }
    }
    
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
            
            Text(formatPrice(asset.currentPrice))
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
    @State private var selectedPrice: Double?
    @State private var selectedDate: Date?
    @State private var location: CGPoint = .zero
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemBackground) : .white
    }
    
    private var chartColor: Color {
        guard !priceHistory.isEmpty else { return .green }
        let startPrice = priceHistory.first!.price
        let endPrice = priceHistory.last!.price
        return endPrice >= startPrice ? .green : .red
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price < 0.0001 {
            return String(format: "$%.8f", price)
        } else if price < 0.01 {
            return String(format: "$%.6f", price)
        } else if price < 1 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.2f", price)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Price and date display
            if let selectedPrice = selectedPrice {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatPrice(selectedPrice))
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let selectedDate = selectedDate {
                        Text(formatDate(selectedDate))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 4)
            }
            
            // Chart
            if !priceHistory.isEmpty {
                Chart(priceHistory) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Price", point.price)
                    )
                    .foregroundStyle(chartColor.gradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    if let selectedDate = selectedDate,
                       let selectedPrice = selectedPrice,
                       selectedDate == point.date {
                        PointMark(
                            x: .value("Date", selectedDate),
                            y: .value("Price", selectedPrice)
                        )
                        .foregroundStyle(chartColor)
                        .symbolSize(150)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            let showMark = shouldShowAxisMark(for: date, calendar: calendar)
                            
                            if showMark {
                        AxisGridLine()
                        AxisTick()
                                AxisValueLabel {
                                    Text(formatAxisLabel(date))
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .currency(code: "USD"))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        location = value.location
                                        updateSelectedPrice(proxy: proxy, geometry: geometry)
                                    }
                                    .onEnded { _ in
                                        selectedDate = nil
                                        selectedPrice = nil
                                    }
                            )
                    }
                }
                .frame(height: 250)
                .id("\(selectedTimeRange)_\(priceHistory.count)")
            } else {
                Text("No price data available")
                    .foregroundColor(.secondary)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .onChange(of: selectedTimeRange) { _ in
            selectedDate = nil
            selectedPrice = nil
        }
    }
    
    private func shouldShowAxisMark(for date: Date, calendar: Calendar) -> Bool {
        switch selectedTimeRange {
        case .day:
            // Her 4 saatte bir işaret (günde 6 işaret)
            let hour = calendar.component(.hour, from: date)
            return hour % 4 == 0
            
        case .week:
            // Her gün için işaret
            let hour = calendar.component(.hour, from: date)
            return hour == 0 // Günün başlangıcı
            
        case .month:
            // Her 5 günde bir işaret (ayda 6 işaret)
            let day = calendar.component(.day, from: date)
            let hour = calendar.component(.hour, from: date)
            return day % 5 == 1 && hour == 0
            
        case .sixMonths:
            // Her ay için işaret
            let day = calendar.component(.day, from: date)
            return day == 1 // Ayın ilk günü
            
        case .year:
            // Her 2 ayda bir işaret (yılda 6 işaret)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return day == 1 && month % 2 == 1
            
        case .twoYears:
            // Her 4 ayda bir işaret
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return day == 1 && month % 4 == 1
            
        case .fiveYears:
            // Her 6 ayda bir işaret
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return day == 1 && month % 6 == 1
        }
    }
    
    private func formatAxisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        switch selectedTimeRange {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week, .month:
            formatter.dateFormat = "d MMM"
        case .sixMonths:
            formatter.dateFormat = "MMM"
        case .year:
            formatter.dateFormat = "MMM"
        case .twoYears, .fiveYears:
            formatter.dateFormat = "MMM yyyy"
        }
        
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        switch selectedTimeRange {
        case .day:
            formatter.dateFormat = "HH:mm, d MMM"
        case .week:
            formatter.dateFormat = "E, d MMM HH:mm"
        case .month:
            formatter.dateFormat = "d MMM, HH:mm"
        case .sixMonths, .year, .twoYears, .fiveYears:
            formatter.dateFormat = "d MMM yyyy"
        }
        
        return formatter.string(from: date)
    }
    
    private func updateSelectedPrice(proxy: ChartProxy, geometry: GeometryProxy) {
        let xPosition = location.x - geometry.frame(in: .local).origin.x
        guard let date: Date = proxy.value(atX: xPosition),
              let closestPoint = priceHistory.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else {
            return
        }
        
        selectedDate = closestPoint.date
        selectedPrice = closestPoint.price
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
    let asset: Asset
    @Binding var selectedTimeRange: TimeRange
    @Environment(\.colorScheme) private var colorScheme
    
    private var buttonBackgroundColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var selectedTextColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var unselectedTextColor: Color {
        .gray.opacity(0.8)
    }
    
    private func buttonStyle(for range: TimeRange) -> some View {
        Text(range.title)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTimeRange == range ? buttonBackgroundColor : Color.clear)
            )
            .foregroundColor(selectedTimeRange == range ? selectedTextColor : unselectedTextColor)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TimeRange.availableRanges(for: asset.type), id: \.self) { range in
                Button(action: {
                        if selectedTimeRange != range {
                            withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTimeRange = range
                            }
                        }
                    }) {
                        buttonStyle(for: range)
                    }
                    .id("\(range)_\(selectedTimeRange == range)")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add to Portfolio Button
private struct AddToPortfolioButton: View {
    @Binding var showingAddToPortfolio: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var buttonTextColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var buttonBackgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
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
            .foregroundColor(buttonTextColor)
            .padding(.vertical, 16)
            .background(buttonBackgroundColor)
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
    
    private var buttonTextColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var buttonBackgroundColor: Color {
        colorScheme == .dark ? .white : .black
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
                                .foregroundColor(isValidQuantity ? buttonTextColor : .gray)
                                .padding(.vertical, 16)
                                .background(isValidQuantity ? buttonBackgroundColor : Color(uiColor: .systemGray5))
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

