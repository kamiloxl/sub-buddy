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

    var cpi: Double {
        guard installs > 0 else { return 0 }
        return cost / Double(installs)
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

    var totalInstalls: Int {
        Set(campaignRows.map { "\($0.date)-\($0.mediaSource)-\($0.campaign)" })
            .isEmpty ? 0 : campaignRows.reduce(0) { $0 + $1.installs }
    }

    var totalCost: Double {
        campaignRows.reduce(0) { $0 + $1.cost }
    }

    var totalRevenue: Double {
        campaignRows.reduce(0) { $0 + $1.revenue }
    }

    var averageCPI: Double {
        guard totalInstalls > 0 else { return 0 }
        return totalCost / Double(totalInstalls)
    }

    var overallROAS: Double {
        guard totalCost > 0 else { return 0 }
        return (totalRevenue / totalCost) * 100
    }

    // Aggregate by campaign name (sum across dates)
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
                map[key] = existing
            } else {
                map[key] = CampaignTotal(
                    mediaSource: row.mediaSource,
                    campaign: row.campaign,
                    impressions: row.impressions,
                    clicks: row.clicks,
                    installs: row.installs,
                    cost: row.cost,
                    revenue: row.revenue
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

    var cpi: Double {
        guard installs > 0 else { return 0 }
        return cost / Double(installs)
    }

    var roas: Double {
        guard cost > 0 else { return 0 }
        return (revenue / cost) * 100
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

    // MARK: - Public

    func fetchMarketingData(
        appId: String,
        token: String,
        currency: String,
        startDate: Date,
        endDate: Date
    ) async -> AppsFlyerReportData {
        async let campaignRows = fetchCampaignRows(appId: appId, token: token, currency: currency, startDate: startDate, endDate: endDate)
        async let cohorts = fetchCohorts(appId: appId, token: token, currency: currency, startDate: startDate, endDate: endDate)

        let (rows, cohortData) = await (campaignRows, cohorts)

        logger.info("AF data fetched — \(rows.count) campaign rows, \(cohortData.count) cohorts")
        return AppsFlyerReportData(campaignRows: rows, cohorts: cohortData, currency: currency)
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
            logger.error("Invalid Pull API URL: \(urlString)")
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }

            logger.debug("Pull API response: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
                logger.error("Pull API error \(httpResponse.statusCode): \(body)")
                return []
            }

            let csv = String(data: data, encoding: .utf8) ?? ""
            return parseCSV(csv)
        } catch {
            logger.error("Pull API network error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - CSV Parsing

    private func parseCSV(_ csv: String) -> [CampaignDayRow] {
        var lines = csv.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return [] }

        let headerLine = lines.removeFirst()
        let headers = parseCSVLine(headerLine)

        // Map column names to indices (AppsFlyer CSV headers vary slightly)
        func idx(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let i = headers.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == candidate.lowercased() }) {
                    return i
                }
            }
            return nil
        }

        let dateIdx = idx(["date", "day"])
        let mediaIdx = idx(["media source", "media_source", "partner"])
        let campaignIdx = idx(["campaign", "campaign name"])
        let impressionsIdx = idx(["impressions"])
        let clicksIdx = idx(["clicks"])
        let installsIdx = idx(["installs"])
        let costIdx = idx(["cost", "total cost"])
        let revenueIdx = idx(["revenue", "total revenue"])

        logger.debug("CSV headers: \(headers.joined(separator: ", "))")

        var rows: [CampaignDayRow] = []

        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count > 1 else { continue }

            func col(_ idx: Int?) -> String {
                guard let i = idx, i < cols.count else { return "" }
                return cols[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let row = CampaignDayRow(
                date: col(dateIdx),
                mediaSource: col(mediaIdx),
                campaign: col(campaignIdx),
                impressions: Int(col(impressionsIdx)) ?? 0,
                clicks: Int(col(clicksIdx)) ?? 0,
                installs: Int(col(installsIdx)) ?? 0,
                cost: Double(col(costIdx)) ?? 0,
                revenue: Double(col(revenueIdx)) ?? 0
            )

            if !row.mediaSource.isEmpty {
                rows.append(row)
            }
        }

        logger.info("Parsed \(rows.count) campaign rows from CSV")
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
            logger.error("Invalid Cohort API URL")
            return []
        }

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
            logger.error("Failed to encode cohort request body: \(error.localizedDescription)")
            return []
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }

            logger.debug("Cohort API response: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
                logger.error("Cohort API error \(httpResponse.statusCode): \(body)")
                return []
            }

            return parseCohortResponse(data)
        } catch {
            logger.error("Cohort API network error: \(error.localizedDescription)")
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

        logger.warning("Could not parse cohort response in any known format")
        return []
    }
}
