import SwiftUI
import AppKit

struct LogsView: View {
    @ObservedObject private var store = LogStore.shared

    @State private var filterLevel: LogEntry.Level? = nil
    @State private var searchText = ""
    @State private var copiedFeedback = false

    private var filtered: [LogEntry] {
        store.entries.filter { entry in
            if let level = filterLevel, entry.level != level { return false }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return entry.message.lowercased().contains(query)
                    || entry.category.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
        .frame(minWidth: 680, minHeight: 400)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Level filter pills
            HStack(spacing: 4) {
                levelPill(nil, label: "All")
                ForEach(LogEntry.Level.allCases, id: \.self) { level in
                    levelPill(level, label: level.rawValue)
                }
            }

            Divider().frame(height: 16)

            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 140)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text("\(filtered.count) entries")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Divider().frame(height: 16)

            Button {
                copyToClipboard()
            } label: {
                Label(copiedFeedback ? "Copied!" : "Copy all", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(copiedFeedback ? .green : .secondary)

            Button {
                withAnimation { store.clear() }
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func levelPill(_ level: LogEntry.Level?, label: String) -> some View {
        let isSelected = filterLevel == level
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filterLevel = level }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(isSelected ? levelColor(level).opacity(0.2) : Color.clear)
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? levelColor(level).opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                }
                .foregroundStyle(isSelected ? levelColor(level) : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text("No log entries")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(filtered) { entry in
                            LogRowView(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: store.entries.count) { _ in
                if let last = filtered.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Helpers

    private func levelColor(_ level: LogEntry.Level?) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case nil: return .primary
        }
    }

    private func copyToClipboard() {
        let text = filtered.map { entry in
            let ts = ISO8601DateFormatter().string(from: entry.timestamp)
            return "[\(ts)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { copiedFeedback = false }
        }
    }
}

// MARK: - Log Row

private struct LogRowView: View {
    let entry: LogEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(Self.timeFmt.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 86, alignment: .leading)
                .lineLimit(1)

            // Level badge
            Text(entry.level.emoji)
                .font(.system(size: 11))
                .foregroundStyle(levelColor)
                .frame(width: 12)

            // Category
            Text(entry.category)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(messageColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(rowBackground)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var messageColor: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        default: return .primary
        }
    }

    private var rowBackground: Color {
        switch entry.level {
        case .error: return Color.red.opacity(0.06)
        case .warning: return Color.orange.opacity(0.04)
        default: return .clear
        }
    }
}

// MARK: - Window Controller

final class LogsWindowController {
    static let shared = LogsWindowController()

    private weak var window: NSWindow?

    private init() {}

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LogsView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 500)

        let win = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sub Buddy — Console"
        win.contentView = hosting
        win.minSize = NSSize(width: 580, height: 300)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }
}
