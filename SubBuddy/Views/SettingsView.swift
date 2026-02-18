import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var settings = AppSettings.shared

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var openAIKey: String = ""
    @State private var showOpenAIKey = false
    @State private var appsFlyerAppIds: [String] = []
    @State private var appsFlyerToken: String = ""
    @State private var showAppsFlyerToken = false
    @State private var afTestStatus: AFTestStatus = .idle

    enum AFTestStatus: Equatable {
        case idle, testing, success(String), failure(String)
    }
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
                // General settings (always visible)
                generalSection

                // Per-app settings (only when a project tab is selected)
                if let project = currentProject {
                    projectSection(project)
                    appsFlyerSection(project)
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

                    Button("Save") {
                        saveAllSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
        .onAppear {
            loadSettings()
        }
        .onChange(of: viewModel.selectedTab) { _ in
            loadSettings()
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        settingsSection("General") {
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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Group {
                        if showOpenAIKey {
                            TextField("sk-...", text: $openAIKey)
                        } else {
                            SecureField("sk-...", text: $openAIKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    Button {
                        showOpenAIKey.toggle()
                    } label: {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(showOpenAIKey ? "Hide key" : "Show key")
                }

                Text("Used for AI-generated reports. Your key is stored locally in the keychain.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Project Section

    private func projectSection(_ project: AppProject) -> some View {
        settingsSection("App: \(project.name)") {
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

    // MARK: - AppsFlyer Section

    private func appsFlyerSection(_ project: AppProject) -> some View {
        settingsSection("AppsFlyer (optional)") {
            Text("Add one App ID per platform (iOS bundle ID, Android package name). One API token covers all platforms.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("App IDs")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        appsFlyerAppIds.append("")
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Add platform app ID")
                }

                if appsFlyerAppIds.isEmpty {
                    Text("No app IDs added yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appsFlyerAppIds.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            TextField(index == 0 ? "com.myapp.ios" : "com.myapp.android", text: $appsFlyerAppIds[index])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            Button {
                                appsFlyerAppIds.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Remove this app ID")
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API token (v2)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Group {
                        if showAppsFlyerToken {
                            TextField("Bearer token...", text: $appsFlyerToken)
                        } else {
                            SecureField("Bearer token...", text: $appsFlyerToken)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    Button {
                        showAppsFlyerToken.toggle()
                    } label: {
                        Image(systemName: showAppsFlyerToken ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help(showAppsFlyerToken ? "Hide token" : "Show token")
                }

                Text("Obtain your V2 API token from the AppsFlyer dashboard under API Access.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Test connection button + status
            HStack(spacing: 8) {
                Button {
                    runConnectionTest()
                } label: {
                    if case .testing = afTestStatus {
                        ProgressView().controlSize(.small)
                        Text("Testing…")
                            .font(.system(size: 11))
                    } else {
                        Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(afTestStatus == .testing || appsFlyerAppIds.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.isEmpty || appsFlyerToken.trimmingCharacters(in: .whitespaces).isEmpty)

                switch afTestStatus {
                case .idle:
                    EmptyView()
                case .testing:
                    EmptyView()
                case .success(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .lineLimit(2)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
    }

    private func runConnectionTest() {
        let firstId = appsFlyerAppIds.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let tok = appsFlyerToken.trimmingCharacters(in: .whitespaces)
        guard !firstId.isEmpty, !tok.isEmpty else { return }

        withAnimation { afTestStatus = .testing }

        Task {
            let result = await AppsFlyerService.shared.testConnection(appId: firstId, token: tok)
            await MainActor.run {
                withAnimation {
                    switch result {
                    case .success(_, let rows):
                        let rowsText = rows == 0 ? "Connected — no data in last 3 days" : "Connected — \(rows) rows found"
                        afTestStatus = .success(rowsText)
                    case .authError:
                        afTestStatus = .failure("Auth failed — use V2 API token from AppsFlyer > Settings > API Access")
                    case .notFound(let id):
                        afTestStatus = .failure("App ID not found: \(id)")
                    case .networkError(let msg):
                        afTestStatus = .failure("Network error: \(msg)")
                    case .unknownError(let code, let body):
                        afTestStatus = .failure("Error \(code): \(body.prefix(80))")
                    }
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

    private func loadSettings() {
        openAIKey = KeychainService.shared.getOpenAIKey() ?? ""
        showOpenAIKey = false

        guard let project = currentProject else {
            apiKey = ""
            projectName = ""
            projectIdText = ""
            appsFlyerAppIds = []
            appsFlyerToken = ""
            return
        }
        projectName = project.name
        projectIdText = project.projectId
        selectedColour = project.colour
        apiKey = KeychainService.shared.getAPIKey(forProjectId: project.id) ?? ""
        appsFlyerAppIds = project.appsFlyerAppIds
        appsFlyerToken = KeychainService.shared.getAppsFlyerToken(forProjectId: project.id) ?? ""
        showAPIKey = false
        showAppsFlyerToken = false
        saveStatus = .idle
        afTestStatus = .idle
        showDeleteConfirm = false
    }

    private func saveAllSettings() {
        withAnimation { saveStatus = .saving }

        // Save OpenAI key
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespaces)
        if trimmedOpenAIKey.isEmpty {
            KeychainService.shared.deleteOpenAIKey()
        } else {
            KeychainService.shared.saveOpenAIKey(trimmedOpenAIKey)
        }

        // Save project settings if a project is selected
        if let project = currentProject {
            let cleanedIds = appsFlyerAppIds
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let updated = AppProject(
                id: project.id,
                name: projectName.trimmingCharacters(in: .whitespaces),
                projectId: projectIdText.trimmingCharacters(in: .whitespaces),
                colour: selectedColour,
                appsFlyerAppIds: cleanedIds
            )
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
            viewModel.updateProject(updated, apiKey: trimmedKey)

            // Save AppsFlyer token — strip accidental "Bearer " prefix
            var trimmedAFToken = appsFlyerToken.trimmingCharacters(in: .whitespaces)
            if trimmedAFToken.lowercased().hasPrefix("bearer ") {
                trimmedAFToken = String(trimmedAFToken.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            if trimmedAFToken.isEmpty {
                KeychainService.shared.deleteAppsFlyerToken(forProjectId: project.id)
            } else {
                KeychainService.shared.saveAppsFlyerToken(trimmedAFToken, forProjectId: project.id)
                // Update field to show clean token (without "Bearer " prefix)
                appsFlyerToken = trimmedAFToken
            }
        }

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
