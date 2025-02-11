import SwiftUI
import FintrackModels

struct SearchResultView: View {
    let searchResults: [Asset]
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : .gray
    }
    
    private func formatMarketCap(_ marketCap: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        let formattedNumber: String
        if marketCap >= trillion {
            formattedNumber = String(format: "%.2fT", marketCap / trillion)
        } else if marketCap >= billion {
            formattedNumber = String(format: "%.2fB", marketCap / billion)
        } else if marketCap >= million {
            formattedNumber = String(format: "%.2fM", marketCap / million)
        } else if marketCap >= thousand {
            formattedNumber = String(format: "%.2f", marketCap / thousand)
        } else {
            formattedNumber = String(format: "%.2f", marketCap)
        }
        
        return "$" + formattedNumber
    }
    
    private func formatVolume(_ volume: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        let formattedNumber: String
        if volume >= trillion {
            formattedNumber = String(format: "%.2fT", volume / trillion)
        } else if volume >= billion {
            formattedNumber = String(format: "%.2fB", volume / billion)
        } else if volume >= million {
            formattedNumber = String(format: "%.2fM", volume / million)
        } else if volume >= thousand {
            formattedNumber = String(format: "%.2f", volume / thousand)
        } else {
            formattedNumber = String(format: "%.2f", volume)
        }
        
        return "$" + formattedNumber
    }
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(searchResults) { asset in
                NavigationLink(destination: AssetDetailView(asset: asset)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.symbol)
                                .font(.headline)
                                .foregroundColor(primaryTextColor)
                            Text(asset.name)
                                .font(.subheadline)
                                .foregroundColor(secondaryTextColor)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("$\(asset.formattedPrice)")
                                .font(.headline)
                                .foregroundColor(primaryTextColor)
                            
                            HStack(spacing: 4) {
                                Image(systemName: asset.priceChangePercentage24H >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text("\(String(format: "%.2f", abs(asset.priceChangePercentage24H)))%")
                            }
                            .foregroundColor(asset.priceChangePercentage24H >= 0 ? .green : .red)
                            .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(backgroundColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }
} 