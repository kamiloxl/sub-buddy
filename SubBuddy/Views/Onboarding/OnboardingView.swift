import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var appeared = false
    @State private var direction: Edge = .trailing

    // Step 1 state
    @State private var keychainGranted = false

    // Step 2 state
    @State private var apiKey = ""
    @State private var projectId = ""

    // Step 3 state
    @State private var metricConfigs = MetricConfig.defaults

    private let totalSteps = 3

    var body: some View {
        ZStack {
            // Floating gradient blobs
            floatingBlobs

            // Centre panel
            panel
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
                .animation(
                    .spring(response: 0.65, dampingFraction: 0.72, blendDuration: 0),
                    value: appeared
                )
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }

    // MARK: - Floating Blobs

    private var floatingBlobs: some View {
        ZStack {
            Circle()
                .fill(.blue.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(
                    x: appeared ? -140 : -220,
                    y: appeared ? -60 : -160
                )
                .animation(
                    .easeInOut(duration: 5).repeatForever(autoreverses: true),
                    value: appeared
                )

            Circle()
                .fill(.purple.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(
                    x: appeared ? 130 : 210,
                    y: appeared ? 80 : 190
                )
                .animation(
                    .easeInOut(duration: 6).repeatForever(autoreverses: true),
                    value: appeared
                )

            Circle()
                .fill(.green.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(
                    x: appeared ? 40 : -60,
                    y: appeared ? -130 : 110
                )
                .animation(
                    .easeInOut(duration: 7).repeatForever(autoreverses: true),
                    value: appeared
                )
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            // Close button + step indicator
            ZStack {
                // Close button — top leading
                HStack {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background {
                                Circle().fill(.quaternary.opacity(0.5))
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Quit")

                    Spacer()
                }
                .padding(.leading, 20)

                stepIndicator
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 28)

            // Step content — scrollable so step 3 never clips
            ScrollView {
                ZStack {
                    if currentStep == 0 {
                        KeychainAccessStep(granted: $keychainGranted)
                            .transition(stepTransition)
                    }
                    if currentStep == 1 {
                        APIKeyStep(apiKey: $apiKey, projectId: $projectId)
                            .transition(stepTransition)
                    }
                    if currentStep == 2 {
                        MetricCustomisationStep(configs: $metricConfigs)
                            .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }

            Divider()
                .padding(.horizontal, 28)

            navigationBar
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
        .frame(width: 500, height: 580)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.35), radius: 50, y: 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction).combined(with: .opacity),
            removal: .move(edge: direction == .trailing ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { step in
                // Circle
                ZStack {
                    Circle()
                        .fill(
                            step <= currentStep
                                ? Color.accentColor
                                : Color.secondary.opacity(0.18)
                        )
                        .frame(width: 34, height: 34)

                    if step < currentStep {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(step + 1)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(step == currentStep ? .white : .secondary)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)

                // Connector line
                if step < totalSteps - 1 {
                    Rectangle()
                        .fill(
                            step < currentStep
                                ? Color.accentColor
                                : Color.secondary.opacity(0.18)
                        )
                        .frame(width: 44, height: 2.5)
                        .clipShape(Capsule())
                        .animation(
                            .spring(response: 0.4).delay(0.08),
                            value: currentStep
                        )
                }
            }
        }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    direction = .leading
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button {
                    direction = .trailing
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        currentStep += 1
                    }
                } label: {
                    Text("Continue")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
            } else {
                Button {
                    completeOnboarding()
                } label: {
                    HStack(spacing: 6) {
                        Text("Get started")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
            }
        }
    }

    private var canContinue: Bool {
        switch currentStep {
        case 0: return keychainGranted
        case 1: return !apiKey.isEmpty && !projectId.isEmpty
        case 2: return metricConfigs.contains(where: \.enabled)
        default: return true
        }
    }

    // MARK: - Complete

    private func completeOnboarding() {
        KeychainService.shared.saveAPIKey(apiKey)

        let settings = AppSettings.shared
        settings.projectId = projectId
        settings.metricConfigs = metricConfigs
        settings.hasCompletedOnboarding = true

        onComplete()
    }
}
