import Foundation
import os.log

private let logger = Logger(subsystem: "com.subbuddy.app", category: "AppsFlyer")

// MARK: - AppsFlyer Errors

enum AppsFlyerError: LocalizedError {
    case notConfigured
    case invalidURL
    case unauthorized
    case rateLimited
    case serverError(Int, String?)
    case networkError(Error)
    case parsingError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AppsFlyer app ID or API token not configured"
        case .invalidURL:
            return "Invalid AppsFlyer API URL"
        case .unauthorized:
            return "Invalid AppsFlyer API token — check your credentials"
        case .rateLimited:
            return "AppsFlyer rate limited — try again shortly"
        case .serverError(let code, let body):
            if let body { return "AppsFlyer error (\(code)): \(body)" }
            return "AppsFlyer error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let detail):
            return "Failed to parse AppsFlyer response: \(detail)"
        }
    }
}

// MARK: - Data Models

struct CampaignDayRow: Identifiable {
    var id: String { "\(date)-\(mediaSource)-\(campaign)" }
    let date: String
    let mediaSource: String
    let campaign: String
    let impressions: Int
    let clicks: Int
    let installs: Int
    let cost: Double
    let revenue: Double

    // In-app funnel events (from attributed installs)
    let trialsStarted: Int       // af_start_trial
    let subscriptions: Int       // af_subscribe
    let paywallViews: Int        // paywall_viewed
    let paywallDismissals: Int   // paywall_dismissed
    let registrations: Int       // af_complete_registration

    var cpi: Double {
        guard installs > 0 else { return 0 }
        return cost / Double(installs)
    }

    var trialStartRate: Double? {
        guard installs > 0 else { return nil }
        return Double(trialsStarted) / Double(installs)
    }

    var paywallConversionRate: Double? {
        guard paywallViews > 0 else { return nil }
        return Double(subscriptions) / Double(paywallViews)
    }
}

struct CohortData: Identifiable {
    var id: String { campaign }
    let campaign: String
    let mediaSource: String
    let users: Int
    let cost: Double
    let revenue: Double
    let roi: Double
    let retentionD1: Double?
    let retentionD7: Double?
    let retentionD30: Double?
}

struct AppsFlyerReportData {
    var campaignRows: [CampaignDayRow]
    var cohorts: [CohortData]
    var currency: String

    var totalInstalls: Int { campaignRows.reduce(0) { $0 + $1.installs } }
    var totalCost: Double { campaignRows.reduce(0) { $0 + $1.cost } }
    var totalRevenue: Double { campaignRows.reduce(0) { $0 + $1.revenue } }

    var averageCPI: Double {
        guard totalInstalls > 0 else { return 0 }
        return totalCost / Double(totalInstalls)
    }

    var overallROAS: Double {
        guard totalCost > 0 else { return 0 }
        return (totalRevenue / totalCost) * 100
    }

    // Funnel aggregates
    var totalTrialsStarted: Int { campaignRows.reduce(0) { $0 + $1.trialsStarted } }
    var totalAttributedSubscriptions: Int { campaignRows.reduce(0) { $0 + $1.subscriptions } }
    var totalPaywallViews: Int { campaignRows.reduce(0) { $0 + $1.paywallViews } }
    var totalPaywallDismissals: Int { campaignRows.reduce(0) { $0 + $1.paywallDismissals } }
    var totalRegistrations: Int { campaignRows.reduce(0) { $0 + $1.registrations } }

    var trialStartRate: Double? {
        guard totalInstalls > 0, totalTrialsStarted > 0 else { return nil }
        return Double(totalTrialsStarted) / Double(totalInstalls)
    }

    var paywallConversionRate: Double? {
        guard totalPaywallViews > 0 else { return nil }
        return Double(totalAttributedSubscriptions) / Double(totalPaywallViews)
    }

    var hasFunnelData: Bool {
        totalTrialsStarted > 0 || totalPaywallViews > 0 || totalAttributedSubscriptions > 0
    }

    // Aggregate by campaign (sum across dates)
    var campaignTotals: [CampaignTotal] {
        var map: [String: CampaignTotal] = [:]
        for row in campaignRows {
            let key = "\(row.mediaSource)|\(row.campaign)"
            if var existing = map[key] {
                existing.installs += row.installs
                existing.cost += row.cost
                existing.revenue += row.revenue
                existing.impressions += row.impressions
                existing.clicks += row.clicks
                existing.trialsStarted += row.trialsStarted
                existing.subscriptions += row.subscriptions
                existing.paywallViews += row.paywallViews
                map[key] = existing
            } else {
                map[key] = CampaignTotal(
                    mediaSource: row.mediaSource,
                    campaign: row.campaign,
                    impressions: row.impressions,
                    clicks: row.clicks,
                    installs: row.installs,
                    cost: row.cost,
                    revenue: row.revenue,
                    trialsStarted: row.trialsStarted,
                    subscriptions: row.subscriptions,
                    paywallViews: row.paywallViews
                )
            }
        }
        return map.values.sorted { $0.installs > $1.installs }
    }

    var topCampaigns: [CampaignTotal] {
        Array(campaignTotals.prefix(5))
    }
}

struct CampaignTotal: Identifiable {
    var id: String { "\(mediaSource)|\(campaign)" }
    let mediaSource: String
    let campaign: String
    var impressions: Int
    var clicks: Int
    var installs: Int
    var cost: Double
    var revenue: Double
    var trialsStarted: Int
    var subscriptions: Int
    var paywallViews: Int

    var cpi: Double {
        guard installs > 0 else { return 0 }
        return cost / Double(installs)
    }

    var roas: Double {
        guard cost > 0 else { return 0 }
        return (revenue / cost) * 100
    }

    var trialStartRate: Double? {
        guard installs > 0, trialsStarted > 0 else { return nil }
        return Double(trialsStarted) / Double(installs)
    }

    var paywallConversionRate: Double? {
        guard paywallViews > 0, subscriptions > 0 else { return nil }
        return Double(subscriptions) / Double(paywallViews)
    }

    var displayName: String {
        campaign.isEmpty ? mediaSource : "\(mediaSource) — \(campaign)"
    }
}

// MARK: - Cohort API Response Models

private struct CohortResponse: Codable {
    let data: [String: CohortRowData]?
    let rows: [CohortRowRaw]?
}

private struct CohortRowData: Codable {
    let campaignId: String?
    let campaignName: String?
    let users: Double?
    let cost: Double?
    let revenue: Double?
    let roi: Double?
    let retention: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case users, cost, revenue, roi, retention
    }
}

private struct CohortRowRaw: Codable {
    let campaignId: String?
    let campaignName: String?
    let mediaSource: String?
    let users: Double?
    let cost: Double?
    let revenue: Double?
    let roi: Double?
    let day1Retention: Double?
    let day7Retention: Double?
    let day30Retention: Double?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case mediaSource = "media_source"
        case users, cost, revenue, roi
        case day1Retention = "day_1_retention"
        case day7Retention = "day_7_retention"
        case day30Retention = "day_30_retention"
    }
}

// MARK: - AppsFlyer Service

final class AppsFlyerService {
    static let shared = AppsFlyerService()

    private let pullBaseURL = "https://hq1.appsflyer.com/api/agg-data/export/app"
    private let cohortBaseURL = "https://hq1.appsflyer.com/api/cohorts/v1/data/app"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Token Normalisation

    /// Strips an accidental "Bearer " prefix if the user pasted the full header value.
    private func normaliseToken(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("bearer ") {
            t = String(t.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    // MARK: - Connection Test

    enum TestResult {
        case success(appId: String, rows: Int)
        case authError
        case notFound(appId: String)
        case networkError(String)
        case unknownError(Int, String)
    }

    /// Quick validation call — uses Pull API with a 3-day window. Does NOT persist data.
    func testConnection(appId: String, token: String) async -> TestResult {
        let tok = normaliseToken(token)
        let fmt = ISO8601DateFormatter.chartDateFormatter
        let to = fmt.string(from: Date())
        let from = fmt.string(from: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date())

        let urlString = "\(pullBaseURL)/\(appId)/partners_by_date_report/v5?from=\(from)&to=\(to)&currency=USD&timezone=UTC"
        guard let url = URL(string: urlString) else { return .networkError("Invalid URL") }

        appLog("Testing AppsFlyer connection for app_id=\(appId)…", level: .info, category: "AppsFlyer")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .networkError("No HTTP response") }

            appLog("Test connection ← \(http.statusCode) (\(data.count) bytes)", level: http.statusCode == 200 ? .info : .warning, category: "AppsFlyer")

            switch http.statusCode {
            case 200:
                let csv = String(data: data, encoding: .utf8) ?? ""
                let rows = parseCSV(csv)
                appLog("Test OK — \(rows.count) rows in last 3 days", category: "AppsFlyer")
                return .success(appId: appId, rows: rows.count)
            case 401, 403:
                let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
                appLog("Test FAILED — auth error: \(body)", level: .error, category: "AppsFlyer")
                return .authError
            case 404:
                appLog("Test FAILED — app_id not found or no access: \(appId)", level: .error, category: "AppsFlyer")
                return .notFound(appId: appId)
            default:
                let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
                appLog("Test FAILED — HTTP \(http.statusCode): \(body)", level: .error, category: "AppsFlyer")
                return .unknownError(http.statusCode, body)
            }
        } catch {
            appLog("Test FAILED — network: \(error.localizedDescription)", level: .error, category: "AppsFlyer")
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Public

    /// Fetches and merges marketing data for all platform app IDs belonging to one project.
    func fetchMarketingData(
        appIds: [String],
        token: String,
        currency: String,
        startDate: Date,
        endDate: Date
    ) async -> AppsFlyerReportData {
        let tok = normaliseToken(token)
        let nonEmpty = appIds.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpty.isEmpty else {
            return AppsFlyerReportData(campaignRows: [], cohorts: [], currency: currency)
        }

        var allRows: [CampaignDayRow] = []
        var allCohorts: [CohortData] = []

        await withTaskGroup(of: (rows: [CampaignDayRow], cohorts: [CohortData]).self) { group in
            for appId in nonEmpty {
                group.addTask {
                    async let rows = self.fetchCampaignRows(appId: appId, token: tok, currency: currency, startDate: startDate, endDate: endDate)
                    async let cohorts = self.fetchCohorts(appId: appId, token: tok, currency: currency, startDate: startDate, endDate: endDate)
                    return await (rows, cohorts)
                }
            }

            for await result in group {
                allRows.append(contentsOf: result.rows)
                allCohorts.append(contentsOf: result.cohorts)
            }
        }

        appLog("Fetched \(allRows.count) campaign rows and \(allCohorts.count) cohorts for \(nonEmpty.count) platform(s)", category: "AppsFlyer")
        return AppsFlyerReportData(campaignRows: allRows, cohorts: allCohorts, currency: currency)
    }

    // MARK: - Pull API (partners_by_date_report)

    private func fetchCampaignRows(
        appId: String,
        token: String,
        currency: String,
        startDate: Date,
        endDate: Date
    ) async -> [CampaignDayRow] {
        let fmt = ISO8601DateFormatter.chartDateFormatter
        let from = fmt.string(from: startDate)
        let to = fmt.string(from: endDate)

        let urlString = "\(pullBaseURL)/\(appId)/partners_by_date_report/v5?from=\(from)&to=\(to)&currency=\(currency)&timezone=UTC"

        guard let url = URL(string: urlString) else {
            appLog("Invalid Pull API URL: \(urlString)", level: .error, category: "AppsFlyer")
            return []
        }

        appLog("Pull API → GET \(urlString)", level: .debug, category: "AppsFlyer")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }

            appLog("Pull API ← \(httpResponse.statusCode) (\(data.count) bytes) app_id=\(appId)", level: httpResponse.statusCode == 200 ? .info : .error, category: "AppsFlyer")

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data.prefix(300), encoding: .utf8) ?? "(no body)"
                appLog("Pull API error body: \(body)", level: .error, category: "AppsFlyer")
                return []
            }

            let csv = String(data: data, encoding: .utf8) ?? ""
            return parseCSV(csv)
        } catch {
            appLog("Pull API network error: \(error.localizedDescription)", level: .error, category: "AppsFlyer")
            return []
        }
    }

    // MARK: - CSV Parsing

    private func parseCSV(_ csv: String) -> [CampaignDayRow] {
        var lines = csv.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return [] }

        let headerLine = lines.removeFirst()
        let headers = parseCSVLine(headerLine)

        appLog("CSV headers: \(headers.joined(separator: " | "))", level: .debug, category: "AppsFlyer")

        // Match column index — first try exact match, then "starts with / contains" fallback.
        // AppsFlyer appends extra info to headers, e.g. "Media Source (pid)", "Campaign (c)".
        func idx(_ candidates: [String]) -> Int? {
            let normalised = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            // 1. Exact match
            for candidate in candidates {
                if let i = normalised.firstIndex(of: candidate.lowercased()) { return i }
            }
            // 2. Header starts with candidate
            for candidate in candidates {
                let lower = candidate.lowercased()
                if let i = normalised.firstIndex(where: { $0.hasPrefix(lower) }) { return i }
            }
            // 3. Header contains candidate anywhere
            for candidate in candidates {
                let lower = candidate.lowercased()
                if let i = normalised.firstIndex(where: { $0.contains(lower) }) { return i }
            }
            return nil
        }

        // Match a column whose header contains ALL of the given keywords.
        // Used to distinguish e.g. "af_start_trial (Unique users)" from "af_start_trial (Event counter)".
        func idxContainingAll(_ keywords: [String]) -> Int? {
            let normalised = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            return normalised.firstIndex(where: { header in
                keywords.allSatisfy { header.contains($0.lowercased()) }
            })
        }

        let dateIdx        = idx(["date", "day"])
        let mediaIdx       = idx(["media source", "media_source", "partner"])
        let campaignIdx    = idx(["campaign"])
        let impressionsIdx = idx(["impressions"])
        let clicksIdx      = idx(["clicks"])
        let installsIdx    = idx(["installs"])
        let costIdx        = idx(["total cost", "cost"])
        let revenueIdx     = idx(["total revenue", "revenue"])

        // In-app funnel events — "Unique users" variant of each event
        let trialsIdx        = idxContainingAll(["af_start_trial", "unique users"])
        let subsIdx          = idxContainingAll(["af_subscribe", "unique users"])
        let paywallViewIdx   = idxContainingAll(["paywall_viewed", "unique users"])
        let paywallDismissIdx = idxContainingAll(["paywall_dismissed", "unique users"])
        let regIdx           = idxContainingAll(["af_complete_registration", "unique users"])

        appLog(
            "Column map → date:\(dateIdx ?? -1) media:\(mediaIdx ?? -1) campaign:\(campaignIdx ?? -1) installs:\(installsIdx ?? -1) cost:\(costIdx ?? -1) revenue:\(revenueIdx ?? -1) trials:\(trialsIdx ?? -1) subs:\(subsIdx ?? -1) paywall_view:\(paywallViewIdx ?? -1)",
            level: .debug, category: "AppsFlyer"
        )

        var rows: [CampaignDayRow] = []

        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count > 1 else { continue }

            func col(_ idx: Int?) -> String {
                guard let i = idx, i < cols.count else { return "" }
                return cols[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let installs = Int(col(installsIdx)) ?? 0
            let mediaSource = col(mediaIdx)

            // Keep rows that have either a media source or at least one install
            guard !mediaSource.isEmpty || installs > 0 else { continue }

            rows.append(CampaignDayRow(
                date: col(dateIdx),
                mediaSource: mediaSource.isEmpty ? "Organic" : mediaSource,
                campaign: col(campaignIdx),
                impressions: Int(col(impressionsIdx)) ?? 0,
                clicks: Int(col(clicksIdx)) ?? 0,
                installs: installs,
                cost: Double(col(costIdx)) ?? 0,
                revenue: Double(col(revenueIdx)) ?? 0,
                trialsStarted: Int(col(trialsIdx)) ?? 0,
                subscriptions: Int(col(subsIdx)) ?? 0,
                paywallViews: Int(col(paywallViewIdx)) ?? 0,
                paywallDismissals: Int(col(paywallDismissIdx)) ?? 0,
                registrations: Int(col(regIdx)) ?? 0
            ))
        }

        appLog("Parsed \(rows.count) campaign rows from CSV (out of \(lines.count) data lines)", category: "AppsFlyer")
        return rows
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    // MARK: - Cohort API

    private func fetchCohorts(
        appId: String,
        token: String,
        currency: String,
        startDate: Date,
        endDate: Date
    ) async -> [CohortData] {
        let fmt = ISO8601DateFormatter.chartDateFormatter
        let from = fmt.string(from: startDate)
        let to = fmt.string(from: endDate)

        let urlString = "\(cohortBaseURL)/\(appId)"

        guard let url = URL(string: urlString) else {
            appLog("Invalid Cohort API URL: \(urlString)", level: .error, category: "AppsFlyer")
            return []
        }

        appLog("Cohort API → POST \(urlString) from=\(from) to=\(to)", level: .debug, category: "AppsFlyer")

        let body: [String: Any] = [
            "cohort_type": "user_acquisition",
            "min_cohort_size": 1,
            "preferred_timezone": "UTC",
            "from": from,
            "to": to,
            "groupings": ["media_source", "campaign"],
            "kpis": ["users", "cost", "revenue", "roi", "retention"],
            "granularity": "cumulative",
            "partial_data": true,
            "currency": currency
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            appLog("Failed to encode cohort request body: \(error.localizedDescription)", level: .error, category: "AppsFlyer")
            return []
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }

            let isSuccess = httpResponse.statusCode == 200
            appLog("Cohort API ← \(httpResponse.statusCode) (\(data.count) bytes) app_id=\(appId)", level: isSuccess ? .info : .error, category: "AppsFlyer")

            guard isSuccess else {
                // 404 typically means the Cohort API is not enabled for this AppsFlyer plan,
                // or the endpoint has changed. Pull API data will still be used.
                if httpResponse.statusCode == 404 {
                    appLog("Cohort API not available for app_id=\(appId) — endpoint returned 404. This feature may require an AppsFlyer advanced plan. Pull API data will be used without cohort retention.", level: .warning, category: "AppsFlyer")
                } else {
                    let body = String(data: data.prefix(300), encoding: .utf8) ?? "(no body)"
                    appLog("Cohort API error body: \(body)", level: .error, category: "AppsFlyer")
                }
                return []
            }

            let cohorts = parseCohortResponse(data)
            appLog("Parsed \(cohorts.count) cohort entries", category: "AppsFlyer")
            return cohorts
        } catch {
            appLog("Cohort API network error: \(error.localizedDescription)", level: .error, category: "AppsFlyer")
            return []
        }
    }

    private func parseCohortResponse(_ data: Data) -> [CohortData] {
        // AppsFlyer Cohort API returns a flexible JSON structure.
        // We try to parse common known shapes.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Cohort response is not a JSON object")
            return []
        }

        // Shape: { "data": { "<campaign_id>": { ... } } }
        if let dataDict = json["data"] as? [String: [String: Any]] {
            return dataDict.compactMap { (key, value) -> CohortData? in
                let campaign = value["campaign_name"] as? String ?? value["campaign"] as? String ?? key
                let mediaSource = value["media_source"] as? String ?? ""
                let users = (value["users"] as? Double) ?? Double(value["users"] as? Int ?? 0)
                let cost = (value["cost"] as? Double) ?? 0
                let revenue = (value["revenue"] as? Double) ?? 0
                let roi = (value["roi"] as? Double) ?? 0
                let retention = value["retention"] as? [String: Double]

                return CohortData(
                    campaign: campaign,
                    mediaSource: mediaSource,
                    users: Int(users),
                    cost: cost,
                    revenue: revenue,
                    roi: roi,
                    retentionD1: retention?["1"] ?? retention?["day_1"],
                    retentionD7: retention?["7"] ?? retention?["day_7"],
                    retentionD30: retention?["30"] ?? retention?["day_30"]
                )
            }
        }

        // Shape: { "rows": [ { ... } ] }
        if let rows = json["rows"] as? [[String: Any]] {
            return rows.compactMap { row -> CohortData? in
                let campaign = row["campaign_name"] as? String ?? row["campaign"] as? String ?? ""
                let mediaSource = row["media_source"] as? String ?? ""
                let users = (row["users"] as? Double) ?? Double(row["users"] as? Int ?? 0)
                let cost = (row["cost"] as? Double) ?? 0
                let revenue = (row["revenue"] as? Double) ?? 0
                let roi = (row["roi"] as? Double) ?? 0

                return CohortData(
                    campaign: campaign,
                    mediaSource: mediaSource,
                    users: Int(users),
                    cost: cost,
                    revenue: revenue,
                    roi: roi,
                    retentionD1: row["day_1_retention"] as? Double,
                    retentionD7: row["day_7_retention"] as? Double,
                    retentionD30: row["day_30_retention"] as? Double
                )
            }
        }

        appLog("Could not parse cohort response in any known format — keys: \(json.keys.joined(separator: ", "))", level: .warning, category: "AppsFlyer")
        return []
    }
}
