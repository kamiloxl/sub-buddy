import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var settings = AppSettings.shared

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var projectName: String = ""
    @State private var projectIdText: String = ""
    @State private var selectedColour: ProjectColour = .blue
    @State private var showDeleteConfirm = false

    enum SaveStatus {
        case idle, saving, saved, error(String)
    }

    /// The project for the currently selected tab (nil if on "total")
    private var currentProject: AppProject? {
        guard let uuid = UUID(uuidString: viewModel.selectedTab) else { return nil }
        return settings.projects.first { $0.id == uuid }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Per-project settings (only when a project tab is selected)
                if let project = currentProject {
                    projectSection(project)
                }

                // Global preferences
                settingsSection("Preferences") {
                    HStack {
                        Text("Currency")
                            .font(.system(size: 12))

                        Spacer()

                        Picker("", selection: $settings.currency) {
                            ForEach(AppSettings.availableCurrencies, id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .frame(width: 100)
                    }

                    HStack {
                        Text("Refresh interval")
                            .font(.system(size: 12))

                        Spacer()

                        Picker("", selection: $settings.refreshInterval) {
                            ForEach(AppSettings.refreshIntervals, id: \.self) { interval in
                                Text("\(interval) min").tag(interval)
                            }
                        }
                        .frame(width: 100)
                    }
                }

                // Actions
                HStack {
                    Button("Close") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showSettings = false
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if case .saved = saveStatus {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    if case .error(let msg) = saveStatus {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .transition(.opacity)
                    }

                    if currentProject != nil {
                        Button("Save") {
                            saveProjectSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKey.isEmpty || projectIdText.isEmpty || projectName.isEmpty)
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            loadProjectSettings()
        }
        .onChange(of: viewModel.selectedTab) { _ in
            loadProjectSettings()
        }
    }

    // MARK: - Project Section

    private func projectSection(_ project: AppProject) -> some View {
        settingsSection("Project: \(project.name)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Display name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("My App", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            ColourPickerRow(selection: $selectedColour)

            VStack(alignment: .leading, spacing: 6) {
                Text("Project ID")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("proj1ab2c3d4", text: $projectIdText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("RevenueCat API key (v2)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Group {
                        if showAPIKey {
                            TextField("sk_...", text: $apiKey)
                        } else {
                            SecureField("sk_...", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(showAPIKey ? "Hide key" : "Show key")
                }
            }

            // Delete project
            if settings.projects.count > 1 {
                Divider()

                if showDeleteConfirm {
                    HStack {
                        Text("Remove this project?")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Cancel") {
                            withAnimation { showDeleteConfirm = false }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                        Button("Remove") {
                            viewModel.removeProject(project.id)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.showSettings = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        withAnimation { showDeleteConfirm = true }
                    } label: {
                        Label("Remove project", systemImage: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Section Helper

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            }
        }
    }

    // MARK: - Load / Save

    private func loadProjectSettings() {
        guard let project = currentProject else {
            apiKey = ""
            projectName = ""
            projectIdText = ""
            return
        }
        projectName = project.name
        projectIdText = project.projectId
        selectedColour = project.colour
        apiKey = KeychainService.shared.getAPIKey(forProjectId: project.id) ?? ""
        showAPIKey = false
        saveStatus = .idle
        showDeleteConfirm = false
    }

    private func saveProjectSettings() {
        guard let project = currentProject else { return }

        withAnimation { saveStatus = .saving }

        let updated = AppProject(
            id: project.id,
            name: projectName.trimmingCharacters(in: .whitespaces),
            projectId: projectIdText.trimmingCharacters(in: .whitespaces),
            colour: selectedColour
        )
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        viewModel.updateProject(updated, apiKey: trimmedKey)

        withAnimation { saveStatus = .saved }

        viewModel.restartTimer()

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showSettings = false
                }
            }
        }
    }
}
