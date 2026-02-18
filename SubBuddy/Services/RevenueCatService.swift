import Foundation
import os.log

private let logger = Logger(subsystem: "com.subbuddy.app", category: "RevenueCatAPI")

// MARK: - RevenueCat API Errors

enum RevenueCatError: LocalizedError {
    case notConfigured
    case invalidURL
    case unauthorized
    case rateLimited
    case forbidden
    case notFound
    case serverError(Int, String?)
    case decodingError(Error, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API key or project ID not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .unauthorized:
            return "Invalid API key — check your credentials"
        case .rateLimited:
            return "Rate limited — try again shortly"
        case .forbidden:
            return "Access denied — check API key permissions"
        case .notFound:
            return "Project not found — check your project ID"
        case .serverError(let code, let body):
            if let body { return "Server error (\(code)): \(body)" }
            return "Server error (\(code))"
        case .decodingError(_, let body):
            return "Unexpected API response: \(body.prefix(200))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - RevenueCat Service

final class RevenueCatService {
    static let shared = RevenueCatService()

    private let baseURL = "https://api.revenuecat.com/v2"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Test

    func testConnection(apiKey: String, projectId: String) async throws {
        let urlString = "\(baseURL)/projects/\(projectId)/metrics/overview"
        let _: OverviewMetricsResponse = try await performRequest(
            urlString: urlString, apiKey: apiKey
        )
    }

    // MARK: - Public API

    func fetchDashboardData(
        projectId: String,
        apiKey: String,
        currency: String
    ) async throws -> DashboardData {
        guard !apiKey.isEmpty, !projectId.isEmpty else {
            logger.error("Not configured — projectId: '\(projectId)'")
            throw RevenueCatError.notConfigured
        }

        logger.info("Fetching dashboard data for project \(projectId)")

        var dashboard = DashboardData(currency: currency)

        let overview = try await fetchOverviewMetrics(
            projectId: projectId,
            apiKey: apiKey,
            currency: currency
        )

        logger.info("Received \(overview.metrics.count) overview metrics")

        for metric in overview.metrics {
            let val = metric.value ?? 0
            logger.debug("Metric: \(metric.id) = \(val)")
            switch metric.id {
            case MetricID.mrr.rawValue:
                dashboard.mrr = val
            case MetricID.activeSubscriptions.rawValue:
                dashboard.activeSubscriptions = Int(val)
            case MetricID.activeTrials.rawValue:
                dashboard.activeTrials = Int(val)
            case MetricID.newCustomers.rawValue:
                dashboard.newCustomersToday = Int(val)
            default:
                break
            }
        }

        async let newSubsResult = fetchTodayChartValue(
            projectId: projectId,
            apiKey: apiKey,
            chartName: .activesNew,
            currency: currency
        )
        async let trialConvResult = fetchTodayChartValue(
            projectId: projectId,
            apiKey: apiKey,
            chartName: .trialConversion,
            currency: currency
        )

        let (newSubs, trialConv) = try await (newSubsResult, trialConvResult)
        dashboard.newSubscriptionsToday = Int(newSubs)
        dashboard.trialsConvertingToday = Int(trialConv)

        let charts = await fetchAllCharts(
            projectId: projectId,
            apiKey: apiKey,
            currency: currency,
            days: 7
        )
        dashboard.charts = charts

        // MRR 24h change: compare last two daily data points
        if charts.mrrTrend.count >= 2 {
            let latest = charts.mrrTrend.last?.value ?? 0
            let previous = charts.mrrTrend[charts.mrrTrend.count - 2].value ?? 0
            dashboard.mrrChange24h = latest - previous
            logger.info("MRR 24h change: \(dashboard.mrrChange24h) (latest: \(latest), previous: \(previous))")
        }

        // Trial prediction: active trials × average conversion rate from last 7 days
        if !charts.trialConversions.isEmpty {
            let values = charts.trialConversions.compactMap(\.value)
            let avgRate = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            dashboard.trialConversionRate = avgRate
            dashboard.trialPrediction = Int((Double(dashboard.activeTrials) * avgRate / 100).rounded())
        }

        dashboard.lastUpdated = Date()

        logger.info("Dashboard data fetched — MRR: \(dashboard.mrr), subs: \(dashboard.activeSubscriptions)")

        return dashboard
    }

    // MARK: - Overview Metrics

    private func fetchOverviewMetrics(
        projectId: String,
        apiKey: String,
        currency: String
    ) async throws -> OverviewMetricsResponse {
        let urlString = "\(baseURL)/projects/\(projectId)/metrics/overview?currency=\(currency)"
        return try await performRequest(urlString: urlString, apiKey: apiKey)
    }

    // MARK: - Chart Data

    private func fetchTodayChartValue(
        projectId: String,
        apiKey: String,
        chartName: ChartName,
        currency: String
    ) async throws -> Double {
        let today = ISO8601DateFormatter.chartDateFormatter.string(from: Date())
        let urlString = "\(baseURL)/projects/\(projectId)/charts/\(chartName.rawValue)"
            + "?start_date=\(today)&end_date=\(today)&currency=\(currency)&resolution=0"

        do {
            let chart: ChartResponse = try await performRequest(urlString: urlString, apiKey: apiKey)

            if let lastValue = chart.values.last?.value {
                return lastValue
            }

            if let summary = chart.summary.first(where: { $0.operation == "total" }) {
                return summary.value ?? 0
            }

            return 0
        } catch {
            logger.error("Chart \(chartName.rawValue) today fetch failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Chart Series (time-range)

    func fetchChartSeries(
        projectId: String,
        apiKey: String,
        chartName: ChartName,
        currency: String,
        days: Int = 7
    ) async throws -> [ChartDataPoint] {
        let formatter = ISO8601DateFormatter.chartDateFormatter
        let endDate = formatter.string(from: Date())
        let startDate = formatter.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date())!)

        let urlString = "\(baseURL)/projects/\(projectId)/charts/\(chartName.rawValue)"
            + "?start_date=\(startDate)&end_date=\(endDate)&currency=\(currency)&resolution=0"

        do {
            let chart: ChartResponse = try await performRequest(urlString: urlString, apiKey: apiKey)
            logger.info("Chart series \(chartName.rawValue): \(chart.values.count) data points")
            return chart.values
        } catch {
            logger.error("Chart series \(chartName.rawValue) fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchAllCharts(
        projectId: String,
        apiKey: String,
        currency: String,
        days: Int = 7
    ) async -> DashboardCharts {
        async let mrrData = fetchChartSeries(projectId: projectId, apiKey: apiKey, chartName: .mrr, currency: currency, days: days)
        async let subsData = fetchChartSeries(projectId: projectId, apiKey: apiKey, chartName: .actives, currency: currency, days: days)
        async let revenueData = fetchChartSeries(projectId: projectId, apiKey: apiKey, chartName: .revenue, currency: currency, days: days)
        async let trialsData = fetchChartSeries(projectId: projectId, apiKey: apiKey, chartName: .trialConversion, currency: currency, days: days)

        let (mrr, subs, revenue, trials) = await (
            (try? mrrData) ?? [],
            (try? subsData) ?? [],
            (try? revenueData) ?? [],
            (try? trialsData) ?? []
        )

        logger.info("Charts loaded — MRR: \(mrr.count)pts, Subs: \(subs.count)pts, Revenue: \(revenue.count)pts, Trials: \(trials.count)pts")

        return DashboardCharts(
            mrrTrend: mrr,
            subscriberGrowth: subs,
            revenueTrend: revenue,
            trialConversions: trials
        )
    }

    // MARK: - Date-range Chart Series (for AI reports)

    func fetchChartSeriesForRange(
        projectId: String,
        apiKey: String,
        chartName: ChartName,
        currency: String,
        startDate: Date,
        endDate: Date
    ) async -> [ChartDataPoint] {
        let formatter = ISO8601DateFormatter.chartDateFormatter
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        let urlString = "\(baseURL)/projects/\(projectId)/charts/\(chartName.rawValue)"
            + "?start_date=\(startStr)&end_date=\(endStr)&currency=\(currency)&resolution=0"

        do {
            let chart: ChartResponse = try await performRequest(urlString: urlString, apiKey: apiKey)
            logger.info("Chart range \(chartName.rawValue): \(chart.values.count) points (\(startStr)..\(endStr))")
            return chart.values
        } catch {
            logger.error("Chart range \(chartName.rawValue) fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchReportCharts(
        projectId: String,
        apiKey: String,
        currency: String,
        startDate: Date,
        endDate: Date
    ) async -> ReportCharts {
        async let mrrData = fetchChartSeriesForRange(projectId: projectId, apiKey: apiKey, chartName: .mrr, currency: currency, startDate: startDate, endDate: endDate)
        async let subsData = fetchChartSeriesForRange(projectId: projectId, apiKey: apiKey, chartName: .actives, currency: currency, startDate: startDate, endDate: endDate)
        async let revenueData = fetchChartSeriesForRange(projectId: projectId, apiKey: apiKey, chartName: .revenue, currency: currency, startDate: startDate, endDate: endDate)
        async let trialsData = fetchChartSeriesForRange(projectId: projectId, apiKey: apiKey, chartName: .trialConversion, currency: currency, startDate: startDate, endDate: endDate)
        async let movementData = fetchChartSeriesForRange(projectId: projectId, apiKey: apiKey, chartName: .activesMovement, currency: currency, startDate: startDate, endDate: endDate)

        let (mrr, subs, revenue, trials, movement) = await (mrrData, subsData, revenueData, trialsData, movementData)

        return ReportCharts(
            mrrTrend: mrr,
            subscriberGrowth: subs,
            revenueTrend: revenue,
            trialConversions: trials,
            activesMovement: movement
        )
    }

    // MARK: - Network Layer

    private func performRequest<T: Decodable>(urlString: String, apiKey: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw RevenueCatError.invalidURL
        }

        logger.debug("GET \(urlString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw RevenueCatError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RevenueCatError.serverError(0, nil)
        }

        let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
        logger.debug("Response \(httpResponse.statusCode): \(bodyPreview)")

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw RevenueCatError.unauthorized
        case 403:
            throw RevenueCatError.forbidden
        case 404:
            throw RevenueCatError.notFound
        case 429:
            throw RevenueCatError.rateLimited
        default:
            let body = String(data: data.prefix(300), encoding: .utf8)
            throw RevenueCatError.serverError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            logger.error("Decoding failed for \(T.self): \(error)\nBody: \(body)")
            throw RevenueCatError.decodingError(error, body)
        }
    }
}

// MARK: - Date Formatter

extension ISO8601DateFormatter {
    static let chartDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
