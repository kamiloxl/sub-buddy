import SwiftUI
import AppKit

struct AIReportView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    @State private var endDate = Date()
    @State private var reportText: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var copied = false

    private var hasOpenAIKey: Bool {
        guard let key = KeychainService.shared.getOpenAIKey() else { return false }
        return !key.isEmpty
    }

    private var isDateRangeValid: Bool {
        endDate >= startDate && startDate <= Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow

                if !hasOpenAIKey {
                    noKeyView
                } else {
                    controlsView

                    if isGenerating {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if !reportText.isEmpty {
                        reportView
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple)

            Text("AI report")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showAIReport = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - No API Key

    private var noKeyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("OpenAI API key required")
                .font(.system(size: 13, weight: .medium))

            Text("Add your OpenAI API key in settings to generate AI-powered reports.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open settings") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showAIReport = false
                    viewModel.showSettings = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Date range pickers
            HStack {
                Text("From")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)

                DatePicker(
                    "",
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }

            HStack {
                Text("To")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)

                DatePicker(
                    "",
                    selection: $endDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }

            // Quick shortcuts
            HStack(spacing: 6) {
                shortcutButton("7 days", days: 7)
                shortcutButton("30 days", days: 30)
                shortcutButton("90 days", days: 90)
            }

            Button {
                generateReport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text("Generate report")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isGenerating || !isDateRangeValid)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        }
    }

    private func shortcutButton(_ label: String, days: Int) -> some View {
        let target = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let isActive = Calendar.current.isDate(startDate, inSameDayAs: target)
            && Calendar.current.isDate(endDate, inSameDayAs: Date())

        return Button(label) {
            withAnimation(.easeInOut(duration: 0.15)) {
                startDate = target
                endDate = Date()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .font(.system(size: 10))
        .foregroundStyle(isActive ? .purple : .primary)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)

            Text(viewModel.reportProgress.isEmpty ? "Preparing..." : viewModel.reportProgress)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: viewModel.reportProgress)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try again") {
                generateReport()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Report Display

    private var reportView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Report")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !viewModel.reportProgress.isEmpty {
                    Text("(\(viewModel.reportProgress))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(copied ? .green : .primary)
            }

            Text(reportText)
                .font(.system(size: 11))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                }
        }
    }

    // MARK: - Actions

    private func generateReport() {
        isGenerating = true
        errorMessage = nil
        reportText = ""
        copied = false

        Task {
            do {
                let report = try await viewModel.generateReport(
                    startDate: startDate,
                    endDate: endDate
                )
                await MainActor.run {
                    reportText = report
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)

        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation { copied = false }
            }
        }
    }
}
