import AppKit
import SwiftUI

class OverlayPanel: NSPanel {
    private var hostingView: NSHostingView<OverlayPanelContent>?
    private(set) var isNotchMode = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }

    func show(driver: OverlayDriver, notchMode: Bool = false) {
        self.isNotchMode = notchMode

        if hostingView == nil || hostingView?.rootView.notchMode != notchMode {
            let content = OverlayPanelContent(driver: driver, notchMode: notchMode)
            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            contentView = hosting
            hostingView = hosting
        }

        if notchMode {
            level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

            let windowWidth:  CGFloat = 300
            let windowHeight: CGFloat = 38

            if let screen = NSScreen.main {
                let x = screen.frame.origin.x + (screen.frame.width - windowWidth) / 2
                let y = screen.frame.origin.y + screen.frame.height - windowHeight
                setFrame(CGRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
            }
        } else {
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let windowWidth:  CGFloat = 300
            let windowHeight: CGFloat = 38

            if let screen = NSScreen.main {
                let x = screen.visibleFrame.midX - windowWidth / 2
                let y = screen.visibleFrame.minY + 30
                setFrame(CGRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
            }
        }

        alphaValue = 1
        orderFront(nil)

        if notchMode {
            DispatchQueue.main.async {
                driver.isVisible = true
            }
        }
    }

    func showIdle(driver: OverlayDriver) {
        self.isNotchMode = true

        if hostingView == nil || hostingView?.rootView.notchMode != true {
            let content = OverlayPanelContent(driver: driver, notchMode: true)
            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            contentView = hosting
            hostingView = hosting
        }

        let windowWidth:  CGFloat = 300
        let windowHeight: CGFloat = 38

        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        if let screen = NSScreen.main {
            let x = screen.frame.origin.x + (screen.frame.width - windowWidth) / 2
            let y = screen.frame.origin.y + screen.frame.height - windowHeight
            setFrame(CGRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
        }

        alphaValue = 1
        orderFront(nil)
    }

    func hide(driver: OverlayDriver? = nil, completion: (@Sendable () -> Void)? = nil) {
        if isNotchMode, let driver {
            driver.liveText   = ""
            driver.isRefining = false
            driver.isActive   = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                driver.isVisible = false
                completion?()
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.orderOut(nil)
                    completion?()
                }
            })
        }
    }

    func dismiss() {
        orderOut(nil)
    }
}

struct OverlayPanelContent: View {
    var driver: OverlayDriver
    var notchMode: Bool = false

    var body: some View {
        SignalBars(
            signalLevel:  driver.signalLevel,
            isActive:     driver.isActive,
            liveText:     driver.liveText,
            isRefining:   driver.isRefining,
            notchMode:    notchMode,
            notchVisible: driver.isVisible,
            onStop:       driver.onStop,
            onCancel:     driver.onCancel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
}
