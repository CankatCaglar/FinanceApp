import SwiftUI
import FintrackModels

struct PortfolioView: View {
    @StateObject private var viewModel = PortfolioViewModel.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddAsset = false
    @State private var selectedAssetType: AssetType = .crypto
    @State private var selectedSymbol = ""
    @State private var quantity = ""
    @State private var assetToDelete: PortfolioAsset? = nil
    @State private var showingDeleteAlert = false
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var totalValue: Double {
        viewModel.portfolioAssets.reduce(into: 0.0) { result, asset in
            result += asset.currentValue
        }
    }
    
    private func assetColor(for index: Int) -> Color {
        let hue = Double(index) / Double(max(1, viewModel.portfolioAssets.count))
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Portfolio Value Section
                VStack(spacing: 8) {
                    Text("Total Portfolio Value")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(totalValue))
                        .font(.system(size: 34, weight: .bold))
                }
                .padding(.top, 20)
                
                if !viewModel.portfolioAssets.isEmpty {
                    // Portfolio Distribution Chart
                    VStack(alignment: .leading, spacing: 8) {
                        // Chart
                        PortfolioDistributionChart(assets: viewModel.portfolioAssets, colorForIndex: assetColor)
                            .frame(height: 200)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 16)
                    
                    // Assets List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Assets")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 20)
                        
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.portfolioAssets.sorted { $0.currentValue > $1.currentValue }) { asset in
                                AssetRow(
                                    asset: asset,
                                    onDelete: {
                                        assetToDelete = asset
                                        showingDeleteAlert = true
                                    }
                                )
                                .background(Color(UIColor.systemBackground))
                                .cornerRadius(12)
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Assets")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Add some assets to your portfolio")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.refreshPortfolio()
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Portfolio")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddAsset = true }) {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .alert("Delete Asset", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let asset = assetToDelete,
                   let index = viewModel.portfolioAssets.firstIndex(where: { $0.id == asset.id }) {
                    withAnimation {
                        viewModel.removeAssets(at: IndexSet(integer: index))
                    }
                }
            }
        } message: {
            if let asset = assetToDelete {
                Text("Are you sure you want to delete \(asset.symbol) from your portfolio? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showingAddAsset) {
            AddAssetSheet(
                isPresented: $showingAddAsset,
                assetType: $selectedAssetType,
                symbol: $selectedSymbol,
                quantity: $quantity,
                onAdd: {
                    if let quantityValue = Double(quantity.replacingOccurrences(of: ",", with: ".")) {
                        viewModel.addAsset(
                            type: selectedAssetType,
                            symbol: selectedSymbol,
                            quantity: quantityValue
                        )
                    }
                    selectedSymbol = ""
                    quantity = ""
                }
            )
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Portfolio Distribution Chart
struct PortfolioDistributionChart: View {
    let assets: [PortfolioAsset]
    let colorForIndex: (Int) -> Color
    @Environment(\.colorScheme) private var colorScheme
    
    private var data: [(String, Double, Color)] {
        // Remove duplicates and sort by value
        let uniqueAssets = Dictionary(grouping: assets) { $0.symbol }
            .mapValues { assets in
                assets.reduce(0.0) { $0 + $1.currentValue }
            }
            .map { (symbol, totalValue) in
                (symbol, totalValue)
            }
            .sorted { $0.1 > $1.1 }
        
        return uniqueAssets.enumerated().map { (index, asset) in
            (asset.0, asset.1, colorForIndex(index))
        }
    }
    
    private var totalValue: Double {
        data.reduce(0) { $0 + $1.1 }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<data.count, id: \.self) { index in
                        PieSlice(
                            startAngle: startAngle(for: index),
                            endAngle: endAngle(for: index)
                        )
                        .fill(data[index].2)
                    }
                    
                    // Add percentage labels
                    ForEach(0..<data.count, id: \.self) { index in
                        let percentage = (data[index].1 / totalValue) * 100
                        if percentage >= 5 { // Only show label if segment is at least 5%
                            Text(String(format: "%.1f%%", percentage))
                                .font(.caption)
                                .foregroundColor(.white)
                                .position(
                                    labelPosition(
                                        for: index,
                                        in: geometry.size,
                                        percentage: percentage
                                    )
                                )
                        }
                    }
                }
            }
            
            // Legend with FlowLayout
            FlowLayout(spacing: 8) {
                ForEach(data, id: \.0) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.2)
                            .frame(width: 8, height: 8)
                        Text(item.0)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.0))
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func startAngle(for index: Int) -> Angle {
        let total = data.reduce(0) { $0 + $1.1 }
        let upToIndex = data[..<index].reduce(0) { $0 + $1.1 }
        return .degrees(upToIndex / total * 360)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let total = data.reduce(0) { $0 + $1.1 }
        let upToIndexPlusOne = data[...index].reduce(0) { $0 + $1.1 }
        return .degrees(upToIndexPlusOne / total * 360)
    }
    
    private func labelPosition(for index: Int, in size: CGSize, percentage: Double) -> CGPoint {
        let radius = min(size.width, size.height) / 2
        let labelRadius = radius * 0.7 // Position label at 70% of radius
        
        let startAngleInDegrees = startAngle(for: index).degrees
        let endAngleInDegrees = endAngle(for: index).degrees
        let midAngleInRadians = ((startAngleInDegrees + endAngleInDegrees) / 2 - 90) * .pi / 180
        
        let x = size.width / 2 + labelRadius * cos(midAngleInRadians)
        let y = size.height / 2 + labelRadius * sin(midAngleInRadians)
        
        return CGPoint(x: x, y: y)
    }
}

struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center,
                   radius: radius,
                   startAngle: Angle(degrees: -90) + startAngle,
                   endAngle: Angle(degrees: -90) + endAngle,
                   clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - FlowLayout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth {
                // Move to next row
                currentX = 0
                currentY += currentRowHeight + spacing
                currentRowHeight = 0
            }
            
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        
        height = currentY + currentRowHeight
        
        return CGSize(width: maxWidth, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var currentRowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            
            if currentX + size.width > bounds.maxX {
                // Move to next row
                currentX = bounds.minX
                currentY += currentRowHeight + spacing
                currentRowHeight = 0
            }
            
            view.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

// MARK: - Asset Row
struct AssetRow: View {
    let asset: PortfolioAsset
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.systemBackground) : .white
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.symbol)
                    .font(.headline)
                Text("\(formatQuantity(asset.quantity)) units")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(asset.currentValue))
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Image(systemName: asset.priceChangePercentage24H >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(abs(asset.priceChangePercentage24H), specifier: "%.2f")%")
                }
                .foregroundColor(asset.priceChangePercentage24H >= 0 ? .green : .red)
                .font(.subheadline)
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .padding(.leading, 12)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value == 0 {
            return "0"
        }
        
        // For very small numbers (less than 0.0001), use scientific notation
        if value < 0.0001 {
            return String(format: "%.8f", value)
        }
        
        // For numbers between 0.0001 and 1, show up to 8 decimal places
        if value < 1 {
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 8
            formatter.minimumIntegerDigits = 1
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
        
        // For whole numbers
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        
        // For numbers greater than 1, show necessary decimals
        let parts = String(value).split(separator: ".")
        if parts.count == 2 {
            let decimals = parts[1]
            let trimmedDecimals = decimals.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            if trimmedDecimals.isEmpty {
                return String(format: "%.0f", value)
            } else {
                return String(format: "%.\(trimmedDecimals.count)f", value)
            }
        }
        return String(value)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
} 




