import SwiftUI

struct CampaignsSectionView: View {
    let data: AppsFlyerReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)

                Text("Campaigns (last 7 days)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            // 2x2 metric cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetricCardView(
                    title: "Installs",
                    value: data.totalInstalls.formatted(),
                    icon: "arrow.down.app.fill",
                    colour: .cyan
                )

                MetricCardView(
                    title: "Ad spend",
                    value: formatCurrency(data.totalCost, currency: data.currency),
                    icon: "creditcard.fill",
                    colour: .orange
                )

                MetricCardView(
                    title: "Avg CPI",
                    value: formatCurrency(data.averageCPI, currency: data.currency),
                    icon: "dollarsign.arrow.circlepath",
                    colour: .yellow
                )

                MetricCardView(
                    title: "ROAS",
                    value: String(format: "%.0f%%", data.overallROAS),
                    icon: "chart.line.uptrend.xyaxis",
                    colour: .green
                )
            }

            // Top campaigns list
            if !data.topCampaigns.isEmpty {
                topCampaignsList
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        }
    }

    private var topCampaignsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top campaigns")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(Array(data.topCampaigns.prefix(3).enumerated()), id: \.offset) { index, campaign in
                    CampaignRowView(rank: index + 1, campaign: campaign, currency: data.currency)
                }
            }
        }
        .padding(.top, 2)
    }

    private func formatCurrency(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency) \(value)"
    }
}

// MARK: - Campaign Row

private struct CampaignRowView: View {
    let rank: Int
    let campaign: CampaignTotal
    let currency: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank).")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)

            Text(campaign.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(campaign.installs.formatted()) installs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)

                Text(formattedCPI)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.4))
        }
    }

    private var formattedCPI: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: campaign.cpi)) ?? "") + " CPI"
    }
}
