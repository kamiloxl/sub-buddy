import SwiftUI
import UniformTypeIdentifiers

struct MetricReorderView: View {
    @Binding var configs: [MetricConfig]
    @State private var draggingItem: MetricConfig?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(configs) { config in
                MetricReorderRow(
                    config: config,
                    isDragging: draggingItem?.id == config.id,
                    onToggle: { toggle(config) }
                )
                .onDrag {
                    draggingItem = config
                    return NSItemProvider(object: config.id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ReorderDropDelegate(
                        target: config,
                        items: $configs,
                        dragging: $draggingItem
                    )
                )
            }
        }
    }

    private func toggle(_ config: MetricConfig) {
        guard let idx = configs.firstIndex(where: { $0.id == config.id }) else { return }
        let enabledCount = configs.filter(\.enabled).count
        if configs[idx].enabled && enabledCount <= 1 { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            configs[idx].enabled.toggle()
        }
    }
}

// MARK: - Row

private struct MetricReorderRow: View {
    let config: MetricConfig
    let isDragging: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            Image(systemName: config.icon)
                .font(.system(size: 14))
                .foregroundStyle(config.colour)
                .frame(width: 22)

            Text(config.title)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Toggle("", isOn: Binding(
                get: { config.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(config.enabled ? Color.primary.opacity(0.04) : .clear)
        }
        .overlay {
            if isDragging {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
            }
        }
        .opacity(isDragging ? 0.45 : config.enabled ? 1 : 0.5)
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(
            color: isDragging ? .accentColor.opacity(0.15) : .clear,
            radius: isDragging ? 6 : 0,
            y: isDragging ? 2 : 0
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
    }
}

// MARK: - Drop Delegate

private struct ReorderDropDelegate: DropDelegate {
    let target: MetricConfig
    @Binding var items: [MetricConfig]
    @Binding var dragging: MetricConfig?

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging.id != target.id,
              let fromIdx = items.firstIndex(where: { $0.id == dragging.id }),
              let toIdx = items.firstIndex(where: { $0.id == target.id })
        else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            items.move(
                fromOffsets: IndexSet(integer: fromIdx),
                toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
