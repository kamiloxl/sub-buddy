import Foundation
import SwiftUI

// MARK: - Metric Kind

enum MetricKind: String, Codable, CaseIterable {
    case mrr
    case activeSubs = "active_subs"
    case activeTrials = "active_trials"
    case newToday = "new_today"
    case trialsConverting = "trials_converting"
    case trialPrediction = "trial_prediction"

    var title: String {
        switch self {
        case .mrr: return "MRR"
        case .activeSubs: return "Active subs"
        case .activeTrials: return "Active trials"
        case .newToday: return "New today"
        case .trialsConverting: return "Trials converting"
        case .trialPrediction: return "Trial prediction"
        }
    }

    var icon: String {
        switch self {
        case .mrr: return "dollarsign.circle.fill"
        case .activeSubs: return "person.2.fill"
        case .activeTrials: return "clock.badge.checkmark.fill"
        case .newToday: return "plus.circle.fill"
        case .trialsConverting: return "arrow.right.circle.fill"
        case .trialPrediction: return "wand.and.stars"
        }
    }

    var colour: Color {
        switch self {
        case .mrr: return .green
        case .activeSubs: return .blue
        case .activeTrials: return .orange
        case .newToday: return .mint
        case .trialsConverting: return .purple
        case .trialPrediction: return .indigo
        }
    }
}

// MARK: - Metric Config

struct MetricConfig: Codable, Identifiable, Equatable, Hashable {
    let kind: MetricKind
    var enabled: Bool

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var icon: String { kind.icon }
    var colour: Color { kind.colour }

    static let defaults: [MetricConfig] = MetricKind.allCases.map {
        MetricConfig(kind: $0, enabled: true)
    }

    // Exclude non-Codable Color from encoding
    enum CodingKeys: String, CodingKey {
        case kind, enabled
    }
}

// MARK: - Dashboard Data Metric Accessor

extension DashboardData {
    func formattedValue(for kind: MetricKind) -> String {
        switch kind {
        case .mrr: return mrrFullFormatted
        case .activeSubs: return Self.formatInt(activeSubscriptions)
        case .activeTrials: return Self.formatInt(activeTrials)
        case .newToday: return Self.formatInt(newTodayBest)
        case .trialsConverting: return Self.formatInt(trialsConvertingToday)
        case .trialPrediction: return "~\(Self.formatInt(trialPrediction))"
        }
    }

    private static func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - App Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("projectId") var projectId: String = ""
    @AppStorage("currency") var currency: String = "USD"
    @AppStorage("refreshInterval") var refreshInterval: Int = 5 // minutes
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("metricConfigsJSON") var metricConfigsJSON: String = ""

    var isConfigured: Bool {
        !projectId.isEmpty && KeychainService.shared.getAPIKey() != nil
    }

    var metricConfigs: [MetricConfig] {
        get {
            guard !metricConfigsJSON.isEmpty,
                  let data = metricConfigsJSON.data(using: .utf8),
                  let configs = try? JSONDecoder().decode([MetricConfig].self, from: data)
            else { return MetricConfig.defaults }
            return configs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                metricConfigsJSON = json
            }
        }
    }

    var enabledMetrics: [MetricConfig] {
        metricConfigs.filter(\.enabled)
    }

    static let availableCurrencies = [
        "USD", "EUR", "GBP", "AUD", "CAD",
        "JPY", "BRL", "KRW", "CNY", "MXN"
    ]

    static let refreshIntervals = [1, 2, 5, 10, 15, 30]
}
