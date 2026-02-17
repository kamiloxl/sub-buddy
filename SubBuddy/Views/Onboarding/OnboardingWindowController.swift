import AppKit
import SwiftUI

// Borderless windows refuse keyboard input by default.
// Subclass to allow text fields and other key-accepting views.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var onComplete: (() -> Void)?

    private init() {}

    func show(onComplete: @escaping () -> Void) {
        guard window == nil, let screen = NSScreen.main else { return }
        self.onComplete = onComplete

        let panelSize = NSSize(width: 520, height: 600)
        let origin = NSPoint(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.midY - panelSize.height / 2
        )
        let contentRect = NSRect(origin: origin, size: panelSize)

        let window = KeyableWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(
            rootView: OnboardingView { [weak self] in
                self?.dismiss()
            }
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window?.close()
            self?.window = nil
            self?.onComplete?()
            self?.onComplete = nil
        }
    }
}
