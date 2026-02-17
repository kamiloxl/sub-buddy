import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var settings = AppSettings.shared

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus {
        case idle, saving, saved, error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // API Key
                settingsSection("API Configuration") {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project ID")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("proj1ab2c3d4", text: $settings.projectId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                // Preferences
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
                    Button("Cancel") {
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

                    Button("Save & Connect") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiKey.isEmpty || settings.projectId.isEmpty)
                }
            }
            .padding(12)
        }
        .onAppear {
            apiKey = KeychainService.shared.getAPIKey() ?? ""
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

    // MARK: - Save

    private func save() {
        withAnimation { saveStatus = .saving }

        let saved = KeychainService.shared.saveAPIKey(apiKey)
        if !saved {
            withAnimation { saveStatus = .error("Failed to save API key") }
            return
        }

        withAnimation { saveStatus = .saved }

        viewModel.restartTimer()

        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showSettings = false
                }
            }
            await viewModel.refresh()
        }
    }
}
