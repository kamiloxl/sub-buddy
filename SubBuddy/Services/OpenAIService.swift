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
            previousCharts: previousCharts
        )

        var currentDraft = ""

        for attempt in 1...maxAttempts {
            // --- Generator ---
            onProgress("Generating draft... (attempt \(attempt)/\(maxAttempts))")

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

            logger.info("Draft \(attempt) generated (\(currentDraft.count) chars)")

            if attempt == maxAttempts {
                onProgress("Maximum attempts reached — using final draft")
                break
            }

            // --- Critic ---
            onProgress("Quality review... (attempt \(attempt)/\(maxAttempts))")

            let criticMessages = buildCriticMessages(
                dataPrompt: dataPrompt,
                draft: currentDraft
            )

            let criticResponse = try await callChatAPI(
                apiKey: apiKey,
                messages: criticMessages,
                temperature: 0.3
            )

            logger.info("Critic response (attempt \(attempt)): \(criticResponse.prefix(100))")

            if criticResponse.uppercased().hasPrefix("APPROVED") {
                onProgress("Approved after \(attempt) \(attempt == 1 ? "attempt" : "attempts")")
                logger.info("Report approved on attempt \(attempt)")
                return currentDraft
            }

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
        You are a senior subscription analytics consultant. \
        Your job is to analyse mobile/SaaS subscription metrics and write detailed, \
        actionable reports that can be sent directly as an e-mail to stakeholders.

        Your report MUST include all of the following sections:
        1. Executive summary (2-3 sentences)
        2. Subscriber metrics — active subscriptions count, change vs previous period (absolute + %)
        3. Trial metrics — active trials, trial conversion rate, change vs previous period
        4. MRR analysis — current MRR, trend direction, change vs previous period (absolute + %)
        5. Revenue breakdown — daily revenue trend, total revenue for the period
        6. Churn analysis — estimated churn rate based on subscriber movement data, whether improving or worsening
        7. Key observations — 2-3 notable patterns or anomalies
        8. Recommendations — 2-3 specific, actionable next steps

        Guidelines:
        - Use British English
        - Write in a professional but approachable tone
        - Always include specific numbers and percentage changes — never use vague language
        - Compare current period with the previous period of equal length
        - Keep the entire report under 400 words
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
        You are a strict quality reviewer for subscription analytics reports. \
        Your job is to evaluate whether a report meets all quality criteria.

        Criteria — the report MUST:
        1. Contain specific numbers (not vague statements like "grew" or "increased")
        2. Compare current period with the previous period, including percentage changes
        3. Cover: subscriber count, trial metrics, MRR, churn rate
        4. End with 2-3 actionable recommendations
        5. Be formatted as a plain-text e-mail body (no markdown)
        6. Stay under 400 words

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
        previousCharts: ReportCharts
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

        prompt += """

            \nNOTE: RevenueCat API does not provide per-product breakdown. \
            Infer package popularity from MRR / subscriber ratio if relevant.
            """

        return prompt
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
            logger.error("Network error: \(error.localizedDescription)")
            throw OpenAIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.serverError(0, nil)
        }

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
