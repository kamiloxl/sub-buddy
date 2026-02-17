import SwiftUI

struct ColourPickerRow: View {
    @Binding var selection: ProjectColour

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Colour")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(ProjectColour.allCases, id: \.self) { colour in
                    ColourDot(
                        colour: colour.color,
                        isSelected: selection == colour
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = colour
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Colour Dot

private struct ColourDot: View {
    let colour: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(colour)
                    .frame(width: 18, height: 18)

                if isSelected {
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 18, height: 18)

                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: isSelected ? colour.opacity(0.4) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help(colour.description)
    }
}
