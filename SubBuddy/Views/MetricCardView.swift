import SwiftUI

struct MetricCardView: View {
    let title: String
    let value: String
    let icon: String
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colour)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        MetricCardView(
            title: "MRR",
            value: "$4,230",
            icon: "dollarsign.circle.fill",
            colour: .green
        )
        MetricCardView(
            title: "Active subscriptions",
            value: "1,247",
            icon: "person.2.fill",
            colour: .blue
        )
    }
    .padding()
    .frame(width: 300)
}
