import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private weak var orchestrator: AppOrchestrator?
    private var settingsController:  NSWindowController?
    private var onboardingController: NSWindowController?

    init(orchestrator: AppOrchestrator) {
        self.orchestrator = orchestrator
    }

    func openSettings() {
        if let window = settingsController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let orc = orchestrator else { return }

        let root = SettingsRoot(
            whisperCatalog: orc.whisperCatalog,
            fluidCatalog:   orc.fluidCatalog,
            activityLog:    orc.activityLog,
            wordBank:       orc.wordBank
        )
        .frame(minWidth: 480, maxWidth: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 500, height: 800)
        window.maxSize = NSSize(width: 500, height: 800)
        window.center()
        window.title = "Yap Settings"
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        settingsController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    func showOnboarding(completion: @escaping () -> Void) {
        let flow = SetupFlow {
            self.onboardingController?.window?.close()
            self.onboardingController = nil
            completion()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yap"
        window.contentViewController = NSHostingController(rootView: flow)
        window.isReleasedWhenClosed = false

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size  = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: frame.midX - size.width  / 2,
                y: frame.midY - size.height / 2
            ))
        }

        let controller = NSWindowController(window: window)
        onboardingController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
}
