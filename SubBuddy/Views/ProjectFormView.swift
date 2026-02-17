import SwiftUI

struct ProjectFormView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var editingProject: AppProject?

    @State private var name: String = ""
    @State private var projectId: String = ""
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus: Equatable {
        case idle, testing, success, failed(String)
    }

    private var isEditing: Bool { editingProject != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !projectId.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canTest: Bool {
        !apiKey.isEmpty && !projectId.isEmpty && connectionStatus != .testing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                HStack {
                    Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                    Text(isEditing ? "Edit project" : "Add project")
                        .font(.system(size: 14, weight: .bold))
                }

                // Form fields
                formSection("Project details") {
                    fieldRow("Name") {
                        TextField("My App", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    fieldRow("Project ID") {
                        TextField("proj1ab2c3d4", text: $projectId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API key (v2)")
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
                        }
                    }
                }

                // Test connection
                HStack {
                    Button {
                        testConnection()
                    } label: {
                        HStack(spacing: 4) {
                            if connectionStatus == .testing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.6)
                            }
                            Text(connectionStatus == .testing ? "Testing..." : "Test connection")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canTest)

                    Spacer()

                    statusLabel
                }

                Divider()

                // Actions
                HStack {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showAddProject = false
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                    Spacer()

                    Button(isEditing ? "Save" : "Add project") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSave)
                }
            }
            .padding(12)
        }
        .onAppear {
            if let project = editingProject {
                name = project.name
                projectId = project.projectId
                apiKey = KeychainService.shared.getAPIKey(forProjectId: project.id) ?? ""
            }
        }
    }

    // MARK: - Status Label

    @ViewBuilder
    private var statusLabel: some View {
        switch connectionStatus {
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.green)
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func formSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

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

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func testConnection() {
        withAnimation { connectionStatus = .testing }

        Task {
            do {
                try await RevenueCatService.shared.testConnection(
                    apiKey: apiKey, projectId: projectId
                )
                await MainActor.run {
                    withAnimation(.spring(response: 0.4)) {
                        connectionStatus = .success
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.4)) {
                        connectionStatus = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedProjectId = projectId.trimmingCharacters(in: .whitespaces)
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespaces)

        if let existing = editingProject {
            let updated = AppProject(id: existing.id, name: trimmedName, projectId: trimmedProjectId)
            viewModel.updateProject(updated, apiKey: trimmedApiKey)
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.showAddProject = false
            }
        } else {
            viewModel.addProject(
                name: trimmedName,
                projectId: trimmedProjectId,
                apiKey: trimmedApiKey
            )
        }
    }
}
