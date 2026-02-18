import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.subbuddy.app", category: "App")

@main
struct SubBuddyApp: App {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            MetricsDashboardView(viewModel: viewModel)
                .frame(width: 380)
                .onAppear {
                    showOnboardingIfNeeded()
                }
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }

    private func showOnboardingIfNeeded() {
        let settings = AppSettings.shared
        guard !settings.hasCompletedOnboarding else { return }

        OnboardingWindowController.shared.show { [viewModel] in
            viewModel.restartTimer()
            Task { await viewModel.refresh() }
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 4) {
            if viewModel.isLoading {
                Image(systemName: "chart.bar.fill")
                Text("...")
            } else if let data = viewModel.totalData {
                Image(systemName: data.mrrDirection.icon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(data.mrrDirection.color)
                Text(data.mrrFormatted)
                    .foregroundStyle(data.mrrDirection.color)
            } else {
                Image(systemName: "chart.bar.fill")
                Text("Sub Buddy")
            }
        }
    }
}

// MARK: - Dashboard ViewModel

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var projectDataMap: [UUID: DashboardData] = [:]
    @Published var projectErrors: [UUID: String] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var showAddProject = false
    @Published var showAIReport = false
    @Published var selectedTab: String = "total"

    private var refreshTimer: Timer?
    private let settings = AppSettings.shared

    init() {
        settings.migrateFromSingleProject()
        selectedTab = settings.selectedTabId

        logger.info("DashboardViewModel init — onboarded: \(self.settings.hasCompletedOnboarding), projects: \(self.settings.projects.count)")
        if !settings.hasCompletedOnboarding {
            // Onboarding will handle configuration
        } else if settings.isConfigured {
            Task { await refresh() }
        } else {
            showAddProject = true
        }
        startTimer()
    }

    // MARK: - Tab Selection

    func selectTab(_ tab: String) {
        selectedTab = tab
        settings.selectedTabId = tab
        showSettings = false
        showAddProject = false
        showAIReport = false
    }

    // MARK: - Current Data

    var currentDashboardData: DashboardData? {
        if selectedTab == "total" {
            return totalData
        }
        if let uuid = UUID(uuidString: selectedTab) {
            return projectDataMap[uuid]
        }
        return nil
    }

    var currentError: String? {
        if selectedTab == "total" {
            guard !settings.projects.isEmpty else { return nil }
            if projectErrors.count == settings.projects.count {
                return "All projects failed to load"
            }
            return nil
        }
        if let uuid = UUID(uuidString: selectedTab) {
            return projectErrors[uuid]
        }
        return nil
    }

    /// Aggregated data across all projects (used for menu bar and total tab)
    var totalData: DashboardData? {
        guard !projectDataMap.isEmpty else { return nil }

        var total = DashboardData(currency: settings.currency)
        for data in projectDataMap.values {
            total.mrr += data.mrr
            total.mrrChange24h += data.mrrChange24h
            total.activeSubscriptions += data.activeSubscriptions
            total.activeTrials += data.activeTrials
            total.newSubscriptionsToday += data.newSubscriptionsToday
            total.newCustomersToday += data.newCustomersToday
            total.trialsConvertingToday += data.trialsConvertingToday
            total.trialPrediction += data.trialPrediction
        }
        total.charts = aggregateCharts()
        total.lastUpdated = projectDataMap.values.compactMap(\.lastUpdated).max()
        return total
    }

    private func aggregateCharts() -> DashboardCharts? {
        let allCharts = projectDataMap.values.compactMap(\.charts)
        guard !allCharts.isEmpty else { return nil }

        return DashboardCharts(
            mrrTrend: mergeChartPoints(allCharts.map(\.mrrTrend)),
            subscriberGrowth: mergeChartPoints(allCharts.map(\.subscriberGrowth)),
            revenueTrend: mergeChartPoints(allCharts.map(\.revenueTrend)),
            trialConversions: mergeChartPoints(allCharts.map(\.trialConversions))
        )
    }

    private func mergeChartPoints(_ series: [[ChartDataPoint]]) -> [ChartDataPoint] {
        guard series.count > 1 else { return series.first ?? [] }

        var dateMap: [String: Double] = [:]
        var dateOrder: [String] = []

        for points in series {
            for point in points {
                guard let date = point.date else { continue }
                if dateMap[date] == nil { dateOrder.append(date) }
                dateMap[date, default: 0] += point.value ?? 0
            }
        }

        return dateOrder.map { ChartDataPoint(date: $0, value: dateMap[$0]) }
    }

    // MARK: - Refresh

    func refresh() async {
        let projects = settings.projects
        let currency = settings.currency

        guard !projects.isEmpty else {
            logger.warning("No projects configured")
            errorMessage = "No projects configured"
            return
        }

        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: (UUID, Result<DashboardData, Error>).self) { group in
            for project in projects {
                let pid = project.id
                let rcProjectId = project.projectId
                group.addTask { [weak self] in
                    guard self != nil else { return (pid, .failure(RevenueCatError.notConfigured)) }
                    do {
                        guard let apiKey = KeychainService.shared.getAPIKey(forProjectId: pid) else {
                            throw RevenueCatError.notConfigured
                        }
                        let data = try await RevenueCatService.shared.fetchDashboardData(
                            projectId: rcProjectId,
                            apiKey: apiKey,
                            currency: currency
                        )
                        return (pid, .success(data))
                    } catch {
                        return (pid, .failure(error))
                    }
                }
            }

            for await (projectId, result) in group {
                switch result {
                case .success(let data):
                    projectDataMap[projectId] = data
                    projectErrors.removeValue(forKey: projectId)
                    logger.info("Project \(projectId) refreshed — MRR: \(data.mrr)")
                case .failure(let error):
                    projectErrors[projectId] = error.localizedDescription
                    logger.error("Project \(projectId) failed: \(error.localizedDescription)")
                }
            }
        }

        isLoading = false
    }

    // MARK: - Project Management

    func addProject(name: String, projectId: String, apiKey: String, colour: ProjectColour = .blue) {
        let project = AppProject(name: name, projectId: projectId, colour: colour)
        settings.addProject(project)
        _ = KeychainService.shared.saveAPIKey(apiKey, forProjectId: project.id)
        selectTab(project.id.uuidString)
        showAddProject = false

        Task { await refreshSingleProject(project) }
    }

    func removeProject(_ id: UUID) {
        settings.removeProject(id)
        _ = KeychainService.shared.deleteAPIKey(forProjectId: id)
        projectDataMap.removeValue(forKey: id)
        projectErrors.removeValue(forKey: id)

        if selectedTab == id.uuidString {
            selectTab("total")
        }
    }

    func updateProject(_ project: AppProject, apiKey: String?) {
        settings.updateProject(project)
        if let apiKey {
            _ = KeychainService.shared.saveAPIKey(apiKey, forProjectId: project.id)
        }

        Task { await refreshSingleProject(project) }
    }

    private func refreshSingleProject(_ project: AppProject) async {
        guard let apiKey = KeychainService.shared.getAPIKey(forProjectId: project.id) else { return }

        do {
            let data = try await RevenueCatService.shared.fetchDashboardData(
                projectId: project.projectId,
                apiKey: apiKey,
                currency: settings.currency
            )
            projectDataMap[project.id] = data
            projectErrors.removeValue(forKey: project.id)
        } catch {
            projectErrors[project.id] = error.localizedDescription
        }
    }

    // MARK: - AI Report

    @Published var reportProgress: String = ""

    func generateReport(
        startDate: Date,
        endDate: Date
    ) async throws -> String {
        let projects = settings.projects
        let currency = settings.currency

        let projectName: String
        let dashboardData: DashboardData

        if selectedTab == "total" {
            projectName = "All projects"
            guard let total = totalData else {
                throw OpenAIError.emptyResponse
            }
            dashboardData = total
        } else if let uuid = UUID(uuidString: selectedTab),
                  let project = projects.first(where: { $0.id == uuid }),
                  let data = projectDataMap[uuid] {
            projectName = project.name
            dashboardData = data
        } else {
            throw OpenAIError.emptyResponse
        }

        await MainActor.run { reportProgress = "Fetching data..." }

        let duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 30
        let previousEnd = Calendar.current.date(byAdding: .day, value: -1, to: startDate)!
        let previousStart = Calendar.current.date(byAdding: .day, value: -duration, to: previousEnd)!

        let currentCharts: ReportCharts
        let previousCharts: ReportCharts

        if selectedTab == "total" {
            var allCurrent: [ReportCharts] = []
            var allPrevious: [ReportCharts] = []

            for project in projects {
                guard let apiKey = KeychainService.shared.getAPIKey(forProjectId: project.id) else { continue }
                async let cur = RevenueCatService.shared.fetchReportCharts(
                    projectId: project.projectId, apiKey: apiKey,
                    currency: currency, startDate: startDate, endDate: endDate
                )
                async let prev = RevenueCatService.shared.fetchReportCharts(
                    projectId: project.projectId, apiKey: apiKey,
                    currency: currency, startDate: previousStart, endDate: previousEnd
                )
                let (c, p) = await (cur, prev)
                allCurrent.append(c)
                allPrevious.append(p)
            }

            currentCharts = mergeReportCharts(allCurrent)
            previousCharts = mergeReportCharts(allPrevious)
        } else if let uuid = UUID(uuidString: selectedTab),
                  let project = projects.first(where: { $0.id == uuid }),
                  let apiKey = KeychainService.shared.getAPIKey(forProjectId: uuid) {
            async let cur = RevenueCatService.shared.fetchReportCharts(
                projectId: project.projectId, apiKey: apiKey,
                currency: currency, startDate: startDate, endDate: endDate
            )
            async let prev = RevenueCatService.shared.fetchReportCharts(
                projectId: project.projectId, apiKey: apiKey,
                currency: currency, startDate: previousStart, endDate: previousEnd
            )
            (currentCharts, previousCharts) = await (cur, prev)
        } else {
            throw OpenAIError.emptyResponse
        }

        let onProgress: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in
                self?.reportProgress = message
            }
        }

        return try await OpenAIService.shared.generateReportWithAgentLoop(
            projectName: projectName,
            dateRange: startDate...endDate,
            currentData: dashboardData,
            currentCharts: currentCharts,
            previousCharts: previousCharts,
            onProgress: onProgress
        )
    }

    private func mergeReportCharts(_ charts: [ReportCharts]) -> ReportCharts {
        guard !charts.isEmpty else { return ReportCharts() }
        guard charts.count > 1 else { return charts[0] }

        return ReportCharts(
            mrrTrend: mergeChartPoints(charts.map(\.mrrTrend)),
            subscriberGrowth: mergeChartPoints(charts.map(\.subscriberGrowth)),
            revenueTrend: mergeChartPoints(charts.map(\.revenueTrend)),
            trialConversions: mergeChartPoints(charts.map(\.trialConversions)),
            activesMovement: mergeChartPoints(charts.map(\.activesMovement))
        )
    }

    // MARK: - Timer

    func startTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(settings.refreshInterval * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    func restartTimer() {
        startTimer()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
