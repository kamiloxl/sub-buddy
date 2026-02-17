import SwiftUI
import Charts

// MARK: - Chart Display Style

enum ChartStyle {
    case line
    case bar
    case area
}

// MARK: - Mini Chart View

struct MiniChartView: View {
    let title: String
    let data: [ChartDataPoint]
    let colour: Color
    let style: ChartStyle
    let format: ValueFormat

    enum ValueFormat {
        case currency(String)
        case number
        case percentage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = data.last?.value {
                    Text(formatValue(last))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(colour)
                }
            }

            if data.count >= 2 {
                Chart(data.indices, id: \.self) { index in
                    let point = data[index]
                    let label = point.date ?? "\(index)"
                    let value = point.value ?? 0

                    switch style {
                    case .line:
                        LineMark(
                            x: .value("Date", label),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(colour.gradient)
                        .interpolationMethod(.catmullRom)

                    case .area:
                        AreaMark(
                            x: .value("Date", label),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(colour.opacity(0.15).gradient)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", label),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(colour.gradient)
                        .interpolationMethod(.catmullRom)

                    case .bar:
                        BarMark(
                            x: .value("Date", label),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(colour.gradient)
                        .cornerRadius(2)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 60)
            } else {
                Text("No data available")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 60)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch format {
        case .currency(let code):
            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = code
            fmt.maximumFractionDigits = 0
            if value >= 1_000 {
                fmt.maximumFractionDigits = 1
                return (fmt.string(from: NSNumber(value: value / 1_000)) ?? "0") + "k"
            }
            return fmt.string(from: NSNumber(value: value)) ?? "0"
        case .number:
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            return fmt.string(from: NSNumber(value: value)) ?? "0"
        case .percentage:
            return String(format: "%.1f%%", value)
        }
    }
}
