import Foundation
import SwiftUI

// MARK: - Project Colour

enum ProjectColour: String, Codable, CaseIterable, Equatable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink

    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .mint:   return .mint
        case .teal:   return .teal
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - App Project

struct AppProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var projectId: String
    var colour: ProjectColour

    init(id: UUID = UUID(), name: String, projectId: String, colour: ProjectColour = .blue) {
        self.id = id
        self.name = name
        self.projectId = projectId
        self.colour = colour
    }

    enum CodingKeys: String, CodingKey {
        case id, name, projectId, colour
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        projectId = try container.decode(String.self, forKey: .projectId)
        colour = (try? container.decode(ProjectColour.self, forKey: .colour)) ?? .blue
    }
}

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
    @AppStorage("projectsData") var projectsData: String = ""
    @AppStorage("selectedTabId") var selectedTabId: String = "total"

    // MARK: - Multi-project Support

    var projects: [AppProject] {
        get {
            guard !projectsData.isEmpty,
                  let data = projectsData.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([AppProject].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                projectsData = json
            }
            objectWillChange.send()
        }
    }

    func addProject(_ project: AppProject) {
        var current = projects
        current.append(project)
        projects = current
    }

    func removeProject(_ id: UUID) {
        var current = projects
        current.removeAll { $0.id == id }
        projects = current
    }

    func updateProject(_ project: AppProject) {
        var current = projects
        if let index = current.firstIndex(where: { $0.id == project.id }) {
            current[index] = project
            projects = current
        }
    }

    /// Migrate from single-project storage to multi-project
    func migrateFromSingleProject() {
        guard projects.isEmpty, !projectId.isEmpty else { return }
        guard let apiKey = KeychainService.shared.getAPIKey(), !apiKey.isEmpty else { return }

        let project = AppProject(name: "My App", projectId: projectId)
        addProject(project)
        _ = KeychainService.shared.saveAPIKey(apiKey, forProjectId: project.id)
    }

    var isConfigured: Bool {
        projects.contains { project in
            KeychainService.shared.getAPIKey(forProjectId: project.id) != nil
        }
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
