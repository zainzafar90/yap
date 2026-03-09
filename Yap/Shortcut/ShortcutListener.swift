import Foundation
import Carbon
import AppKit

@MainActor
class ShortcutListener {
    var onActivate:   (() -> Void)?
    var onDeactivate: (() -> Void)?

    var shortcut:          ShortcutBinding = .default          // push-to-talk (hold)
    var handsFreeShortcut: ShortcutBinding = .defaultHandsFree  // hands-free (double-tap)

    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Push-to-talk state
    private var pushIsDown = false

    // Hands-free state
    private var freeIsDown      = false
    private var freeIsActive    = false
    private var freeLastTapTime: Date?
    private let doubleTapWindow: TimeInterval = 0.35

    private(set) var isAccessibilityGranted = false

    func resetState() {
        pushIsDown      = false
        freeIsDown      = false
        freeIsActive    = false
        freeLastTapTime = nil
    }

    nonisolated static func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<ShortcutListener>.fromOpaque(refcon).takeUnretainedValue()
                listener.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[ShortcutListener] Failed to create event tap — grant Accessibility permission.")
            isAccessibilityGranted = false
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isAccessibilityGranted = true
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        DispatchQueue.main.async { [self] in
            if shortcut.isValid {
                if let keyCode = shortcut.keyCode {
                    handlePushKeyBased(type: type, event: event, keyCode: keyCode)
                } else {
                    handlePushModifierOnly(type: type, event: event)
                }
            }
            if handsFreeShortcut.isValid {
                if let keyCode = handsFreeShortcut.keyCode {
                    handleFreeKeyBased(type: type, event: event, keyCode: keyCode)
                } else {
                    handleFreeModifierOnly(type: type, event: event)
                }
            }
        }
    }

    // MARK: - Push-to-talk (hold)

    private func handlePushModifierOnly(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        let down = shortcut.matchesExactModifiers(event.flags)
        if down && !pushIsDown  { pushIsDown = true;  onActivate?() }
        if !down && pushIsDown  { pushIsDown = false; onDeactivate?() }
    }

    private func handlePushKeyBased(type: CGEventType, event: CGEvent, keyCode: Int) {
        let eventKey = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            guard eventKey == keyCode, shortcut.matchesExactModifiers(event.flags) else { return }
            guard !pushIsDown else { return }
            pushIsDown = true; onActivate?()
        case .keyUp:
            guard eventKey == keyCode else { return }
            if pushIsDown { pushIsDown = false; onDeactivate?() }
        case .flagsChanged:
            guard pushIsDown else { return }
            if !shortcut.matchesExactModifiers(event.flags) { pushIsDown = false; onDeactivate?() }
        default: return
        }
    }

    // MARK: - Hands-free (double-tap to start, single tap to stop)

    private func onFreeTap() {
        if freeIsActive {
            freeIsActive    = false
            freeLastTapTime = nil
            onDeactivate?()
        } else {
            let now = Date()
            if let last = freeLastTapTime, now.timeIntervalSince(last) <= doubleTapWindow {
                freeIsActive    = true
                freeLastTapTime = nil
                onActivate?()
            } else {
                freeLastTapTime = now
            }
        }
    }

    private func handleFreeModifierOnly(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        let down = handsFreeShortcut.matchesExactModifiers(event.flags)
        if down && !freeIsDown {
            freeIsDown = true
            onFreeTap()
        } else if !down && freeIsDown {
            freeIsDown = false
        }
    }

    private func handleFreeKeyBased(type: CGEventType, event: CGEvent, keyCode: Int) {
        let eventKey = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            guard eventKey == keyCode, handsFreeShortcut.matchesExactModifiers(event.flags) else { return }
            guard !freeIsDown else { return }
            freeIsDown = true
            onFreeTap()
        case .keyUp:
            guard eventKey == keyCode else { return }
            freeIsDown = false
        default: return
        }
    }
}
