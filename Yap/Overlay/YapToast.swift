import AppKit
import SwiftUI

@MainActor
final class YapToast {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: Duration = .seconds(3)) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(message: message))

        let p = NSPanel(
            contentRect: .zero,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        p.level               = .floating
        p.isOpaque            = false
        p.backgroundColor     = .clear
        p.hasShadow           = false
        p.ignoresMouseEvents  = true
        p.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView         = hosting

        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.minY + 30
            p.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
        }

        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
        panel = p

        dismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
                if self.panel === p { self.panel = nil }
            })
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .fixedSize()
    }
}
