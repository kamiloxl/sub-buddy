import Foundation
import SwiftUI

// MARK: - Overview Metrics Response

struct OverviewMetricsResponse: Codable {
    let object: String
    let metrics: [OverviewMetric]
}

struct OverviewMetric: Codable, Identifiable {
    let object: String?
    let id: String
    let name: String?
    let description: String?
    let unit: String?
    let period: String?
    let value: Double?
    let lastUpdatedAt: Int64?
    let lastUpdatedAtIso8601: String?

    enum CodingKeys: String, CodingKey {
        case object, id, name, description, unit, period, value
        case lastUpdatedAt = "last_updated_at"
        case lastUpdatedAtIso8601 = "last_updated_at_iso8601"
    }
}

// MARK: - Known Metric IDs

enum MetricID: String {
    case activeTrials = "active_trials"
    case activeSubscriptions = "active_subscriptions"
    case mrr
    case revenue
    case newCustomers = "new_customers"
    case activeUsers = "active_users"
}

// MARK: - MRR Trend Direction

enum MRRDirection {
    case up, down, flat

    var icon: String {
        switch self {
        case .up:    return "arrow.up.right"
        case .down:  return "arrow.down.right"
        case .flat:  return "chart.bar.fill"
        }
    }

    var color: Color {
        switch self {
        case .up:    return .green
        case .down:  return .red
        case .flat:  return .primary
        }
    }
}

// MARK: - Parsed Dashboard Data

struct DashboardData {
    var mrr: Double = 0
    var mrrChange24h: Double = 0
    var activeSubscriptions: Int = 0
    var activeTrials: Int = 0
    var newSubscriptionsToday: Int = 0
    var newCustomersToday: Int = 0
    var trialsConvertingToday: Int = 0
    var trialPrediction: Int = 0
    var trialConversionRate: Double = 0
    var lastUpdated: Date?
    var currency: String = "USD"
    var charts: DashboardCharts?

    var mrrDirection: MRRDirection {
        if mrrChange24h > 0 { return .up }
        if mrrChange24h < 0 { return .down }
        return .flat
    }

    var mrrChangeFormatted: String {
        let absValue = abs(mrrChange24h)
        let prefix = mrrChange24h >= 0 ? "+" : "-"

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0

        if absValue >= 1_000_000 {
            formatter.maximumFractionDigits = 1
            let scaled = absValue / 1_000_000
            return prefix + (formatter.string(from: NSNumber(value: scaled)) ?? "$0") + "M"
        } else if absValue >= 1_000 {
            formatter.maximumFractionDigits = 1
            let scaled = absValue / 1_000
            return prefix + (formatter.string(from: NSNumber(value: scaled)) ?? "$0") + "k"
        }
        return prefix + (formatter.string(from: NSNumber(value: absValue)) ?? "$0")
    }

    /// Best available "new today" value — prefers overview metric, falls back to chart
    var newTodayBest: Int {
        max(newCustomersToday, newSubscriptionsToday)
    }

    var mrrFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0

        if mrr >= 1_000_000 {
            formatter.maximumFractionDigits = 1
            let value = mrr / 1_000_000
            return (formatter.string(from: NSNumber(value: value)) ?? "$0") + "M"
        } else if mrr >= 1_000 {
            formatter.maximumFractionDigits = 1
            let value = mrr / 1_000
            return (formatter.string(from: NSNumber(value: value)) ?? "$0") + "k"
        }
        return formatter.string(from: NSNumber(value: mrr)) ?? "$0"
    }

    var mrrFullFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: mrr)) ?? "$0"
    }

    var lastUpdatedFormatted: String {
        guard let date = lastUpdated else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Dashboard Charts

struct DashboardCharts {
    var mrrTrend: [ChartDataPoint] = []
    var subscriberGrowth: [ChartDataPoint] = []
    var revenueTrend: [ChartDataPoint] = []
    var trialConversions: [ChartDataPoint] = []
}

// MARK: - Report Charts (extended for AI reports)

struct ReportCharts {
    var mrrTrend: [ChartDataPoint] = []
    var subscriberGrowth: [ChartDataPoint] = []
    var revenueTrend: [ChartDataPoint] = []
    var trialConversions: [ChartDataPoint] = []
    var activesMovement: [ChartDataPoint] = []

    var estimatedChurnRate: Double? {
        let movementValues = activesMovement.compactMap(\.value)
        let subsValues = subscriberGrowth.compactMap(\.value)
        guard !movementValues.isEmpty, let avgSubs = subsValues.first, avgSubs > 0 else {
            return nil
        }
        let negativeMovement = movementValues.filter { $0 < 0 }.map { abs($0) }
        guard !negativeMovement.isEmpty else { return nil }
        let totalChurned = negativeMovement.reduce(0, +)
        return (totalChurned / avgSubs) * 100
    }
}
