import Foundation
import os.log

private let chartLogger = Logger(subsystem: "com.subbuddy.app", category: "ChartData")

// MARK: - Chart Data Point

struct ChartDataPoint: Codable, Sendable {
    let date: String?
    let value: Double?
}

// MARK: - Chart Summary

struct ChartSummary: Codable, Sendable {
    let operation: String?
    let value: Double?
}

// MARK: - Chart Response

struct ChartResponse: Sendable {
    let object: String?
    let displayName: String?
    let description: String?
    let resolution: String?
    let values: [ChartDataPoint]
    let summary: [ChartSummary]
}

extension ChartResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case object
        case displayName = "display_name"
        case description
        case resolution
        case startDate = "start_date"
        case endDate = "end_date"
        case lastComputedAt = "last_computed_at"
        case values
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        object = try container.decodeIfPresent(String.self, forKey: .object)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)

        // Parse values — API returns [[Double]] (v3) or [{date,value}] (v2)
        if let objectValues = try? container.decode([ChartDataPoint].self, forKey: .values) {
            values = objectValues
            chartLogger.debug("Decoded chart values as object array: \(objectValues.count) points")
        } else if let arrayValues = try? container.decode([[Double]].self, forKey: .values) {
            // v3 format: [[val1], [val2], ...] — reconstruct dates from start_date
            let startTimestamp = Self.decodeTimestamp(
                from: container, key: .startDate
            )
            let daySeconds: TimeInterval = 86_400
            let formatter = ISO8601DateFormatter.chartDateFormatter

            values = arrayValues.enumerated().map { index, row in
                let dateString: String?
                if startTimestamp > 0 {
                    let date = Date(timeIntervalSince1970: startTimestamp + Double(index) * daySeconds)
                    dateString = formatter.string(from: date)
                } else {
                    dateString = "\(index)"
                }
                return ChartDataPoint(date: dateString, value: row.first)
            }
            chartLogger.debug("Decoded chart values as 2D array: \(arrayValues.count) points")
        } else {
            values = []
            chartLogger.warning("Could not decode chart values in any known format")
        }

        // Parse summary — API may return {} (object) or [{operation,value}] (array)
        if let summaryArray = try? container.decode([ChartSummary].self, forKey: .summary) {
            summary = summaryArray
        } else {
            summary = []
        }
    }

    private static func decodeTimestamp(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> TimeInterval {
        if let ts = try? container.decode(Double.self, forKey: key) {
            return ts
        }
        if let dateStr = try? container.decode(String.self, forKey: key),
           let date = ISO8601DateFormatter.chartDateFormatter.date(from: dateStr) {
            return date.timeIntervalSince1970
        }
        return 0
    }
}

// MARK: - Chart Names

enum ChartName: String {
    case activesNew = "actives_new"
    case trialConversion = "trial_conversion"
    case actives
    case activesMovement = "actives_movement"
    case revenue
    case mrr
}
