import SwiftUI
import Security

// MARK: - Step 1 — Keychain Access

struct KeychainAccessStep: View {
    @Binding var granted: Bool

    @State private var testing = false
    @State private var pulseIcon = false
    @State private var keychainNative = true

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.10))
                    .frame(width: 88, height: 88)
                    .scaleEffect(pulseIcon ? 1.12 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: pulseIcon
                    )

                Image(systemName: granted ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(granted ? .green : .blue)
            }

            VStack(spacing: 10) {
                Text("Secure storage")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Text("Your API keys are stored securely in macOS Keychain, protected by your system credentials.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 340)
            }

            if !granted {
                Button {
                    testKeychainAccess()
                } label: {
                    HStack(spacing: 8) {
                        if testing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                        Text(testing ? "Checking..." : "Grant access")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(testing)
            } else {
                VStack(spacing: 6) {
                    Label("Access granted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.green)

                    if !keychainNative {
                        Text("Using secure file storage (unsigned build)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .onAppear { pulseIcon = true }
    }

    private func testKeychainAccess() {
        testing = true
        let testService = "com.subbuddy.app.onboarding-test"
        let testAccount = "access-check"
        let testData = "test".data(using: .utf8)!

        DispatchQueue.global(qos: .userInitiated).async {
            // Cleanup any leftover test item
            let baseQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService,
                kSecAttrAccount as String: testAccount
            ]
            SecItemDelete(baseQuery as CFDictionary)

            // Attempt add
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = testData
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let status = SecItemAdd(addQuery as CFDictionary, nil)

            // Cleanup
            SecItemDelete(baseQuery as CFDictionary)

            let nativeOK = status == errSecSuccess

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    keychainNative = nativeOK
                    granted = true
                    testing = false
                }
            }
        }
    }
}

// MARK: - Step 2 — API Key

struct APIKeyStep: View {
    @Binding var apiKey: String
    @Binding var projectId: String

    @State private var showAPIKey = false
    @State private var animateIcon = false
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus: Equatable {
        case idle, testing, success, failed(String)
    }

    private var canTest: Bool {
        !apiKey.isEmpty && !projectId.isEmpty && connectionStatus != .testing
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.orange.opacity(0.10))
                    .frame(width: 88, height: 88)
                    .scaleEffect(animateIcon ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                        value: animateIcon
                    )

                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 10) {
                Text("Connect RevenueCat")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Text("Enter your RevenueCat v2 API key and project ID to start tracking metrics.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 340)
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
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
                                .font(.system(size: 12))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(showAPIKey ? "Hide key" : "Show key")
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Project ID")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("proj1ab2c3d4", text: $projectId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            .frame(maxWidth: 360)

            // Test connection
            VStack(spacing: 8) {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 8) {
                        if connectionStatus == .testing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                        Text(connectionStatus == .testing ? "Connecting..." : "Test connection")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!canTest)

                // Status feedback
                Group {
                    switch connectionStatus {
                    case .success:
                        Label("Connected successfully", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    default:
                        EmptyView()
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .onAppear { animateIcon = true }
        .onChange(of: apiKey) { _ in resetStatus() }
        .onChange(of: projectId) { _ in resetStatus() }
    }

    private func resetStatus() {
        if connectionStatus != .idle && connectionStatus != .testing {
            withAnimation(.easeOut(duration: 0.2)) { connectionStatus = .idle }
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
}

// MARK: - Step 3 — Metric Customisation

struct MetricCustomisationStep: View {
    @Binding var configs: [MetricConfig]

    @State private var animateIcon = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            ZStack {
                Circle()
                    .fill(.indigo.opacity(0.10))
                    .frame(width: 64, height: 64)
                    .scaleEffect(animateIcon ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                        value: animateIcon
                    )

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.indigo)
            }

            VStack(spacing: 6) {
                Text("Customise your dashboard")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("Choose which metrics to display and drag to reorder them.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            // Drag & drop list
            MetricReorderView(configs: $configs)

            // Mini preview
            metricPreview
        }
        .onAppear { animateIcon = true }
    }

    private var metricPreview: some View {
        let enabled = configs.filter(\.enabled)
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]

        return VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(enabled) { config in
                    HStack(spacing: 4) {
                        Image(systemName: config.icon)
                            .font(.system(size: 8))
                            .foregroundStyle(config.colour)
                        Text(config.title)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                    }
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.06))
        }
        .animation(.spring(response: 0.35), value: enabled.map(\.id))
    }
}
