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

// MARK: - Report Period

enum ReportPeriod: String, CaseIterable, Identifiable {
    case week = "week"
    case month = "month"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }

    var label: String {
        switch self {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
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
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generate Report

    func generateReport(
        projectName: String,
        period: ReportPeriod,
        dashboardData: DashboardData,
        charts: DashboardCharts?
    ) async throws -> String {
        guard let apiKey = KeychainService.shared.getOpenAIKey(), !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }

        let systemPrompt = buildSystemPrompt()
        let userPrompt = buildUserPrompt(
            projectName: projectName,
            period: period,
            data: dashboardData,
            charts: charts
        )

        logger.info("Generating AI report for \(projectName), period: \(period.rawValue)")

        return try await callChatAPI(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt() -> String {
        """
        You are a senior subscription analytics consultant. \
        Your job is to analyse mobile/SaaS subscription metrics and write concise, \
        actionable reports that can be sent directly as an e-mail to stakeholders.

        Guidelines:
        - Write in a professional but approachable tone
        - Use British English
        - Start with a brief executive summary (2-3 sentences)
        - Highlight key trends (growth, decline, anomalies)
        - Include specific numbers and percentage changes where possible
        - End with 2-3 actionable recommendations
        - Keep the entire report under 300 words
        - Format for plain-text e-mail (no markdown headers, use dashes for lists)
        - Do not include a subject line — just the body
        """
    }

    private func buildUserPrompt(
        projectName: String,
        period: ReportPeriod,
        data: DashboardData,
        charts: DashboardCharts?
    ) -> String {
        var prompt = """
        Generate a subscription performance report for "\(projectName)" \
        covering the \(period.label.lowercased()).

        CURRENT METRICS:
        - MRR: \(data.mrrFullFormatted)
        - MRR change (24h): \(data.mrrChangeFormatted)
        - Active subscriptions: \(data.activeSubscriptions)
        - Active trials: \(data.activeTrials)
        - New subscribers today: \(data.newTodayBest)
        - Trials converting today: \(data.trialsConvertingToday)
        - Trial prediction: \(data.trialPrediction)
        - Currency: \(data.currency)
        """

        if let charts {
            prompt += "\n\nDAILY TREND DATA (\(period.label)):\n"

            if !charts.mrrTrend.isEmpty {
                prompt += "\nMRR trend:\n"
                for point in charts.mrrTrend {
                    let date = point.date ?? "?"
                    let value = point.value.map { String(format: "%.2f", $0) } ?? "n/a"
                    prompt += "  \(date): \(value)\n"
                }
            }

            if !charts.subscriberGrowth.isEmpty {
                prompt += "\nSubscriber count:\n"
                for point in charts.subscriberGrowth {
                    let date = point.date ?? "?"
                    let value = point.value.map { String(format: "%.0f", $0) } ?? "n/a"
                    prompt += "  \(date): \(value)\n"
                }
            }

            if !charts.revenueTrend.isEmpty {
                prompt += "\nDaily revenue:\n"
                for point in charts.revenueTrend {
                    let date = point.date ?? "?"
                    let value = point.value.map { String(format: "%.2f", $0) } ?? "n/a"
                    prompt += "  \(date): \(value)\n"
                }
            }

            if !charts.trialConversions.isEmpty {
                prompt += "\nTrial conversion rate (%):\n"
                for point in charts.trialConversions {
                    let date = point.date ?? "?"
                    let value = point.value.map { String(format: "%.1f", $0) } ?? "n/a"
                    prompt += "  \(date): \(value)\n"
                }
            }
        }

        return prompt
    }

    // MARK: - API Call

    private func callChatAPI(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7,
            "max_tokens": 1000
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
            logger.info("Report generated successfully (\(content.count) characters)")
            return content
        } catch is OpenAIError {
            throw OpenAIError.emptyResponse
        } catch {
            logger.error("Decoding failed: \(error.localizedDescription)")
            throw OpenAIError.decodingError(error)
        }
    }
}
