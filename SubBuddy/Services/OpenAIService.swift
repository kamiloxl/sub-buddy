import Foundation
import os.log

private let logger = Logger(subsystem: "com.subbuddy.app", category: "OpenAI")

// MARK: - OpenAI Errors

enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case unauthorized
    case rateLimited
    case serverError(Int, String?)
    case networkError(Error)
    case decodingError(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .unauthorized:
            return "Invalid OpenAI API key — check your credentials"
        case .rateLimited:
            return "Rate limited — try again shortly"
        case .serverError(let code, let body):
            if let body { return "OpenAI error (\(code)): \(body)" }
            return "OpenAI error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .emptyResponse:
            return "OpenAI returned an empty response"
        }
    }
}

// MARK: - OpenAI API Response Models

private struct ChatCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String?
    }
}

// MARK: - OpenAI Service

final class OpenAIService {
    static let shared = OpenAIService()

    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"
    private let maxAttempts = 5
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Agentic Report Generation

    func generateReportWithAgentLoop(
        projectName: String,
        dateRange: ClosedRange<Date>,
        currentData: DashboardData,
        currentCharts: ReportCharts,
        previousCharts: ReportCharts,
        currentMarketingData: AppsFlyerReportData? = nil,
        previousMarketingData: AppsFlyerReportData? = nil,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let apiKey = KeychainService.shared.getOpenAIKey(), !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }

        let dataPrompt = buildDataPrompt(
            projectName: projectName,
            dateRange: dateRange,
            data: currentData,
            currentCharts: currentCharts,
            previousCharts: previousCharts,
            currentMarketing: currentMarketingData,
            previousMarketing: previousMarketingData
        )

        appLog("Starting agentic report loop for \"\(projectName)\" (\(dateRange.lowerBound.formatted(date: .abbreviated, time: .omitted))–\(dateRange.upperBound.formatted(date: .abbreviated, time: .omitted)))", category: "OpenAI")

        var currentDraft = ""

        for attempt in 1...maxAttempts {
            // --- Generator ---
            onProgress("Generating draft... (attempt \(attempt)/\(maxAttempts))")
            appLog("Generator attempt \(attempt)/\(maxAttempts)", level: .debug, category: "OpenAI")

            let generatorMessages = buildGeneratorMessages(
                dataPrompt: dataPrompt,
                previousDraft: attempt > 1 ? currentDraft : nil,
                criticFeedback: attempt > 1 ? currentDraft : nil
            )

            currentDraft = try await callChatAPI(
                apiKey: apiKey,
                messages: generatorMessages,
                temperature: 0.7
            )

            appLog("Draft \(attempt) generated — \(currentDraft.count) chars", category: "OpenAI")

            if attempt == maxAttempts {
                appLog("Max attempts reached — using final draft", level: .warning, category: "OpenAI")
                onProgress("Maximum attempts reached — using final draft")
                break
            }

            // --- Critic ---
            onProgress("Quality review... (attempt \(attempt)/\(maxAttempts))")
            appLog("Critic reviewing draft \(attempt)…", level: .debug, category: "OpenAI")

            let criticMessages = buildCriticMessages(
                dataPrompt: dataPrompt,
                draft: currentDraft
            )

            let criticResponse = try await callChatAPI(
                apiKey: apiKey,
                messages: criticMessages,
                temperature: 0.3
            )

            appLog("Critic response: \(criticResponse.prefix(120))", level: .debug, category: "OpenAI")

            if criticResponse.uppercased().hasPrefix("APPROVED") {
                appLog("Report APPROVED on attempt \(attempt)", category: "OpenAI")
                onProgress("Approved after \(attempt) \(attempt == 1 ? "attempt" : "attempts")")
                return currentDraft
            }

            appLog("Critic NEEDS_REVISION (attempt \(attempt)): \(criticResponse.prefix(200))", level: .warning, category: "OpenAI")

            let feedback = criticResponse
                .replacingOccurrences(of: "NEEDS_REVISION:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            currentDraft = """
            PREVIOUS DRAFT:
            \(currentDraft)

            CRITIC FEEDBACK:
            \(feedback)
            """
        }

        return currentDraft
    }

    // MARK: - Generator Prompt

    private static let generatorSystemPrompt = """
        You are a senior subscription and growth analytics consultant. \
        Your job is to analyse mobile/SaaS subscription metrics and marketing performance, \
        then write detailed, actionable reports that can be sent directly as an e-mail to stakeholders.

        Your report MUST include all of the following sections:
        1. Executive summary (2-3 sentences)
        2. Subscriber metrics — active subscriptions count, change vs previous period (absolute + %)
        3. Trial metrics — active trials, trial conversion rate, change vs previous period
        4. MRR analysis — current MRR, trend direction, change vs previous period (absolute + %)
        5. Revenue breakdown — daily revenue trend, total revenue for the period
        6. Churn analysis — estimated churn rate based on subscriber movement data, whether improving or worsening
        7. Marketing performance (ONLY if marketing data is provided) — total installs, cost, CPI, ROAS, \
           top campaigns, cohort retention (D1/D7/D30), comparison with previous period
        8. Key observations — 2-3 notable patterns or anomalies
        9. Recommendations — 2-3 specific, actionable next steps

        Marketing guidelines (when marketing data is available):
        - Always state total installs, total spend, average CPI, and ROAS (if data is present; \
          if spend is zero or missing, note it explicitly — do not invent numbers)
        - Name specific top campaigns with their installs and CPI
        - If in-app funnel data is present (trials started, paywall views, attributed subscriptions), \
          analyse the acquisition funnel: install → trial start rate → paywall conversion rate
        - If paywall dismissal rate is high, highlight this as a conversion bottleneck
        - Comment on cohort retention (D1/D7/D30) if available; if not, note it's unavailable
        - Compare marketing efficiency with the previous period (CPI trend, ROAS trend)
        - Highlight best and worst performing campaigns

        General guidelines:
        - Use British English
        - Write in a professional but approachable tone
        - Always include specific numbers and percentage changes — never use vague language
        - Compare current period with the previous period of equal length
        - Keep the entire report under 600 words (or 400 if no marketing data)
        - Format for plain-text e-mail (no markdown headers, use dashes for bullet lists)
        - Do not include a subject line — just the body
        - If data for a metric is unavailable, note it explicitly rather than omitting it
        """

    private func buildGeneratorMessages(
        dataPrompt: String,
        previousDraft: String?,
        criticFeedback: String?
    ) -> [[String: String]] {
        var messages: [[String: String]] = [
            ["role": "system", "content": Self.generatorSystemPrompt]
        ]

        if let previous = previousDraft {
            messages.append([
                "role": "user",
                "content": """
                    Here is the data and a previous draft that needs improvement:

                    \(dataPrompt)

                    \(previous)

                    Please write an improved version addressing the feedback above.
                    """
            ])
        } else {
            messages.append([
                "role": "user",
                "content": dataPrompt
            ])
        }

        return messages
    }

    // MARK: - Critic Prompt

    private static let criticSystemPrompt = """
        You are a strict quality reviewer for subscription and growth analytics reports. \
        Your job is to evaluate whether a report meets all quality criteria.

        Criteria — the report MUST:
        1. Contain specific numbers (not vague statements like "grew" or "increased")
        2. Compare current period with the previous period, including percentage changes
        3. Cover: subscriber count, trial metrics, MRR, churn rate
        4. If marketing data is present in SOURCE DATA: cover installs, CPI, ROAS, and at least \
           one named campaign with its performance metrics
        5. End with 2-3 actionable recommendations
        6. Be formatted as a plain-text e-mail body (no markdown)
        7. Stay under 600 words

        Your response must be EXACTLY one of:
        - "APPROVED" — if all criteria are met
        - "NEEDS_REVISION: <specific issues>" — listing what is missing or wrong

        Be strict. If even one criterion is not properly addressed, respond with NEEDS_REVISION.
        """

    private func buildCriticMessages(
        dataPrompt: String,
        draft: String
    ) -> [[String: String]] {
        [
            ["role": "system", "content": Self.criticSystemPrompt],
            ["role": "user", "content": """
                SOURCE DATA:
                \(dataPrompt)

                REPORT TO REVIEW:
                \(draft)
                """]
        ]
    }

    // MARK: - Data Prompt Builder

    private func buildDataPrompt(
        projectName: String,
        dateRange: ClosedRange<Date>,
        data: DashboardData,
        currentCharts: ReportCharts,
        previousCharts: ReportCharts,
        currentMarketing: AppsFlyerReportData? = nil,
        previousMarketing: AppsFlyerReportData? = nil
    ) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: dateRange.lowerBound)
        let endStr = fmt.string(from: dateRange.upperBound)

        var prompt = """
            Generate a subscription performance report for "\(projectName)" \
            covering \(startStr) to \(endStr).

            CURRENT METRICS (snapshot):
            - MRR: \(data.mrrFullFormatted)
            - MRR change (24h): \(data.mrrChangeFormatted)
            - Active subscriptions: \(data.activeSubscriptions)
            - Active trials: \(data.activeTrials)
            - New subscribers today: \(data.newTodayBest)
            - Trials converting today: \(data.trialsConvertingToday)
            - Trial prediction: \(data.trialPrediction)
            - Currency: \(data.currency)
            """

        if let churn = currentCharts.estimatedChurnRate {
            prompt += String(format: "\n- Estimated churn rate (period): %.1f%%", churn)
        }

        prompt += "\n\nCURRENT PERIOD DAILY DATA (\(startStr) to \(endStr)):\n"
        prompt += formatChartSection("MRR trend", currentCharts.mrrTrend, format: "%.2f")
        prompt += formatChartSection("Subscriber count", currentCharts.subscriberGrowth, format: "%.0f")
        prompt += formatChartSection("Daily revenue", currentCharts.revenueTrend, format: "%.2f")
        prompt += formatChartSection("Trial conversion rate (%)", currentCharts.trialConversions, format: "%.1f")
        prompt += formatChartSection("Subscriber movement (net)", currentCharts.activesMovement, format: "%.0f")

        let prevHasData = !previousCharts.mrrTrend.isEmpty || !previousCharts.subscriberGrowth.isEmpty
        if prevHasData {
            prompt += "\n\nPREVIOUS PERIOD DATA (comparison baseline):\n"
            prompt += formatChartSection("MRR trend", previousCharts.mrrTrend, format: "%.2f")
            prompt += formatChartSection("Subscriber count", previousCharts.subscriberGrowth, format: "%.0f")
            prompt += formatChartSection("Daily revenue", previousCharts.revenueTrend, format: "%.2f")
            prompt += formatChartSection("Trial conversion rate (%)", previousCharts.trialConversions, format: "%.1f")
            prompt += formatChartSection("Subscriber movement (net)", previousCharts.activesMovement, format: "%.0f")

            if let prevChurn = previousCharts.estimatedChurnRate {
                prompt += String(format: "\n- Previous period estimated churn rate: %.1f%%", prevChurn)
            }
        }

        prompt += "\n\nNOTE: RevenueCat API does not provide per-product breakdown. " +
            "Infer package popularity from MRR / subscriber ratio if relevant."

        // Marketing data section
        if let marketing = currentMarketing, !marketing.campaignRows.isEmpty || !marketing.cohorts.isEmpty {
            prompt += "\n\n" + formatMarketingSection(marketing, label: "CURRENT PERIOD")
        }
        if let prevMarketing = previousMarketing, !prevMarketing.campaignRows.isEmpty || !prevMarketing.cohorts.isEmpty {
            prompt += "\n\n" + formatMarketingSection(prevMarketing, label: "PREVIOUS PERIOD")
        }

        return prompt
    }

    private func formatMarketingSection(_ data: AppsFlyerReportData, label: String) -> String {
        var section = "MARKETING PERFORMANCE (\(label)):\n"
        section += String(format: "- Total installs: %d\n", data.totalInstalls)

        if data.totalCost > 0 {
            section += String(format: "- Total ad spend: %.2f %@\n", data.totalCost, data.currency)
            section += String(format: "- Average CPI: %.2f %@\n", data.averageCPI, data.currency)
        } else {
            section += "- Total ad spend: not available (organic/untracked traffic only)\n"
        }

        if data.totalRevenue > 0 {
            section += String(format: "- Total attributed revenue: %.2f %@\n", data.totalRevenue, data.currency)
            section += String(format: "- ROAS: %.1f%%\n", data.overallROAS)
        }

        // In-app funnel events
        if data.hasFunnelData {
            section += "\nIn-app funnel (attributed installs):\n"
            if data.totalRegistrations > 0 {
                section += String(format: "- Registrations: %d\n", data.totalRegistrations)
            }
            if data.totalTrialsStarted > 0 {
                section += String(format: "- Trials started: %d", data.totalTrialsStarted)
                if let rate = data.trialStartRate {
                    section += String(format: " (%.1f%% of installs)", rate * 100)
                }
                section += "\n"
            }
            if data.totalPaywallViews > 0 {
                section += String(format: "- Paywall views: %d\n", data.totalPaywallViews)
            }
            if data.totalAttributedSubscriptions > 0 {
                section += String(format: "- Subscriptions (attributed): %d", data.totalAttributedSubscriptions)
                if let convRate = data.paywallConversionRate {
                    section += String(format: " (%.1f%% paywall conversion)", convRate * 100)
                }
                section += "\n"
            }
            if data.totalPaywallViews > 0 && data.totalPaywallViews > data.totalAttributedSubscriptions {
                let dismissRate = 1.0 - (data.paywallConversionRate ?? 0)
                section += String(format: "- Paywall dismissal rate: %.1f%%\n", dismissRate * 100)
            }
        }

        let topCampaigns = data.topCampaigns
        if !topCampaigns.isEmpty {
            section += "\nTop campaigns by installs:\n"
            for (i, campaign) in topCampaigns.prefix(5).enumerated() {
                var line = String(
                    format: "  %d. %@ — %d installs",
                    i + 1, campaign.displayName, campaign.installs
                )
                if campaign.cost > 0 {
                    line += String(format: ", %.2f %@ spend, CPI %.2f %@", campaign.cost, data.currency, campaign.cpi, data.currency)
                }
                if campaign.roas > 0 {
                    line += String(format: ", ROAS %.1f%%", campaign.roas)
                }
                if let trialRate = campaign.trialStartRate {
                    line += String(format: ", trial rate %.1f%%", trialRate * 100)
                }
                if let convRate = campaign.paywallConversionRate {
                    line += String(format: ", paywall conv. %.1f%%", convRate * 100)
                }
                section += line + "\n"
            }
        }

        if !data.cohorts.isEmpty {
            section += "\nCohort retention (top campaigns):\n"
            for cohort in data.cohorts.prefix(5) {
                var retStr = ""
                if let d1 = cohort.retentionD1 { retStr += String(format: "D1=%.0f%% ", d1 * 100) }
                if let d7 = cohort.retentionD7 { retStr += String(format: "D7=%.0f%% ", d7 * 100) }
                if let d30 = cohort.retentionD30 { retStr += String(format: "D30=%.0f%% ", d30 * 100) }
                let name = cohort.campaign.isEmpty ? cohort.mediaSource : "\(cohort.mediaSource) — \(cohort.campaign)"
                section += String(
                    format: "  %@ — %d users, revenue %.2f %@, ROI %.1f%% %@\n",
                    name, cohort.users, cohort.revenue, data.currency, cohort.roi, retStr
                )
            }
        } else {
            section += "\nCohort retention: not available (requires AppsFlyer advanced plan)\n"
        }

        return section
    }

    private func formatChartSection(_ title: String, _ points: [ChartDataPoint], format: String) -> String {
        guard !points.isEmpty else { return "" }
        var section = "\n\(title):\n"
        for point in points {
            let date = point.date ?? "?"
            let value = point.value.map { String(format: format, $0) } ?? "n/a"
            section += "  \(date): \(value)\n"
        }
        return section
    }

    // MARK: - API Call

    private func callChatAPI(
        apiKey: String,
        messages: [[String: String]],
        temperature: Double
    ) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": 1500
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            appLog("OpenAI network error: \(error.localizedDescription)", level: .error, category: "OpenAI")
            throw OpenAIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.serverError(0, nil)
        }

        appLog("OpenAI API ← \(httpResponse.statusCode) (\(data.count) bytes)", level: httpResponse.statusCode == 200 ? .debug : .error, category: "OpenAI")

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw OpenAIError.unauthorized
        case 429:
            throw OpenAIError.rateLimited
        default:
            let body = String(data: data.prefix(300), encoding: .utf8)
            throw OpenAIError.serverError(httpResponse.statusCode, body)
        }

        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
                throw OpenAIError.emptyResponse
            }
            return content
        } catch is OpenAIError {
            throw OpenAIError.emptyResponse
        } catch {
            logger.error("Decoding failed: \(error.localizedDescription)")
            throw OpenAIError.decodingError(error)
        }
    }
}
