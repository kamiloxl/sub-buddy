import SwiftUI

struct MetricsDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Tab bar
            TabBarView(viewModel: viewModel)

            Divider()

            if viewModel.showSettings {
                SettingsView(viewModel: viewModel)
            } else if viewModel.showAddProject {
                ProjectFormView(viewModel: viewModel)
            } else if viewModel.showAIReport {
                AIReportView(viewModel: viewModel)
            } else {
                // Content
                ScrollView {
                    VStack(spacing: 8) {
                        if viewModel.isLoading && viewModel.currentDashboardData == nil {
                            loadingView
                        } else if let error = viewModel.currentError {
                            errorState(error)
                        } else if let data = viewModel.currentDashboardData {
                            metricsGrid(data)
                            if let charts = data.charts {
                                chartsSection(data: data, charts: charts)
                            }
                        } else if viewModel.isLoading {
                            loadingView
                        } else {
                            emptyState
                        }
                    }
                    .padding(12)
                }

                Divider()

                // Footer
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sub Buddy")
                    .font(.system(size: 14, weight: .bold))

                if let data = viewModel.currentDashboardData {
                    Text("Updated \(data.lastUpdatedFormatted)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                        .animation(
                            viewModel.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isLoading
                        )
                }
                .buttonStyle(.plain)
                .help("Refresh data")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showSettings = false
                        viewModel.showAddProject = false
                        viewModel.showAIReport.toggle()
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.showAIReport ? .purple : .primary)
                }
                .buttonStyle(.plain)
                .help("AI report")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showAddProject = false
                        viewModel.showAIReport = false
                        viewModel.showSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Metrics Grid

    private func metricsGrid(_ data: DashboardData) -> some View {
        let metrics = AppSettings.shared.enabledMetrics
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(metrics) { metric in
                MetricCardView(
                    title: metric.title,
                    value: data.formattedValue(for: metric.kind),
                    icon: metric.icon,
                    colour: metric.colour
                )
            }
        }
    }

    // MARK: - Charts Section

    private func chartsSection(data: DashboardData, charts: DashboardCharts) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 8) {
                MiniChartView(
                    title: "MRR",
                    data: charts.mrrTrend,
                    colour: .green,
                    style: .area,
                    format: .currency(data.currency)
                )

                MiniChartView(
                    title: "Subscribers",
                    data: charts.subscriberGrowth,
                    colour: .blue,
                    style: .line,
                    format: .number
                )

                MiniChartView(
                    title: "Revenue",
                    data: charts.revenueTrend,
                    colour: .mint,
                    style: .bar,
                    format: .currency(data.currency)
                )

                MiniChartView(
                    title: "Trial conversion",
                    data: charts.trialConversions,
                    colour: .purple,
                    style: .line,
                    format: .percentage
                )
            }
        }
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)

            Text("Connection failed")
                .font(.system(size: 13, weight: .medium))

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)

            HStack(spacing: 8) {
                Button("Settings") {
                    withAnimation { viewModel.showSettings = true }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Retry") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Fetching metrics...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No data available")
                .font(.system(size: 13, weight: .medium))

            Text("Configure your API key to get started")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button("Open settings") {
                withAnimation { viewModel.showSettings = true }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Quit") {
                viewModel.quit()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Text("v1.0.0")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

}
