import SwiftUI
import FintrackModels

struct AssetDetails: View {
    let asset: FintrackModels.Asset
    @Environment(\.colorScheme) private var colorScheme
    
    private func formatMarketCap(_ value: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1_000.0
        
        if value >= billion {
            return String(format: "%.2fB", value / billion)
        } else if value >= million {
            return String(format: "%.2fM", value / million)
        } else if value >= thousand {
            return String(format: "%.2fK", value / thousand)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Price Section
                VStack(spacing: 8) {
                    Text(asset.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("$\(asset.formattedPrice)")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        Image(systemName: asset.priceChangePercentage24H >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(String(format: "%.2f", abs(asset.priceChangePercentage24H)))%")
                    }
                    .foregroundColor(asset.priceChangePercentage24H >= 0 ? .green : .red)
                    .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                .cornerRadius(12)
                
                // 24h High/Low Section
                VStack(spacing: 8) {
                    Text("24h Range")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("Low")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("$\(String(format: "%.2f", asset.low24H))")
                                .font(.headline)
                        }
                        
                        Rectangle()
                            .frame(width: 1, height: 30)
                            .foregroundColor(.secondary.opacity(0.3))
                        
                        VStack(spacing: 4) {
                            Text("High")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("$\(String(format: "%.2f", asset.high24H))")
                                .font(.headline)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                .cornerRadius(12)
                
                // Market Stats Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Market Stats")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            MarketStatCell(title: "Market Cap", value: formatMarketCap(asset.marketCap))
                            if asset.type == .crypto {
                                MarketStatCell(title: "24h Volume", value: formatMarketCap(asset.volume24H))
                            }
                        }
                        
                        if asset.circulatingSupply > 0 {
                            HStack(spacing: 16) {
                                MarketStatCell(title: "Circulating Supply", value: formatNumber(asset.circulatingSupply))
                                if asset.type == .crypto, let totalSupply = asset.totalSupply {
                                    MarketStatCell(title: "Total Supply", value: formatNumber(totalSupply))
                                }
                            }
                        }
                        
                        if asset.type == .crypto, let maxSupply = asset.maxSupply {
                            HStack(spacing: 16) {
                                MarketStatCell(title: "Max Supply", value: formatNumber(maxSupply))
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle(asset.symbol)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MarketStatCell: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 