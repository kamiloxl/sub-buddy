import SwiftUI

struct TabBarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                // Total tab
                TabPill(
                    title: "Total",
                    icon: "chart.pie.fill",
                    isSelected: viewModel.selectedTab == "total"
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectTab("total")
                    }
                }

                if !settings.projects.isEmpty {
                    dividerDot
                }

                // Project tabs
                ForEach(settings.projects) { project in
                    TabPill(
                        title: project.name,
                        icon: "app.fill",
                        colour: project.colour.color,
                        isSelected: viewModel.selectedTab == project.id.uuidString
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectTab(project.id.uuidString)
                        }
                    }
                }

                // Add button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showSettings = false
                        viewModel.showAddProject = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background {
                            Circle()
                                .fill(.quaternary.opacity(0.5))
                        }
                }
                .buttonStyle(.plain)
                .help("Add project")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var dividerDot: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 3, height: 3)
    }
}

// MARK: - Tab Pill

struct TabPill: View {
    let title: String
    let icon: String
    var colour: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    private var accentColour: Color {
        colour ?? Color.accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let colour {
                    Circle()
                        .fill(colour)
                        .frame(width: 6, height: 6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                }
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? accentColour.opacity(0.15) : Color.clear)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}
