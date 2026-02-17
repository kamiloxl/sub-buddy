import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.subbuddy.app", category: "App")

@main
struct SubBuddyApp: App {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        MenuBarExtra {
            MetricsDashboardView(viewModel: viewModel)
                .frame(width: 360)
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
            } else if let data = viewModel.dashboardData {
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
    @Published var dashboardData: DashboardData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSettings = false

    private var refreshTimer: Timer?
    private let settings = AppSettings.shared

    init() {
        logger.info("DashboardViewModel init — onboarded: \(self.settings.hasCompletedOnboarding)")
        if !settings.hasCompletedOnboarding {
            // Onboarding will handle configuration — skip Keychain access
        } else if settings.isConfigured {
            Task { await refresh() }
        } else {
            showSettings = true
        }
        startTimer()
    }

    func refresh() async {
        guard settings.isConfigured else {
            logger.warning("Not configured, opening settings")
            errorMessage = "Please configure your API key and project ID"
            showSettings = true
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let data = try await RevenueCatService.shared.fetchDashboardData()
            dashboardData = data
            errorMessage = nil
            logger.info("Dashboard refreshed — MRR: \(data.mrr)")
        } catch {
            logger.error("Refresh failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

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
