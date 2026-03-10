import AppKit
import ApplicationServices

@MainActor
struct Typist {
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let savedItems = saveContents(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste(pid: focusedPid())

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restoreContents(pasteboard, items: savedItems)
        }
    }

    private static func focusedPid() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
            return nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedApp as! AXUIElement, &pid) == .success else {
            return nil
        }
        return pid
    }

    private static func simulatePaste(pid: pid_t? = nil) {
        let source  = CGEventSource(stateID: .hidSystemState)
        let vKey:   CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand

        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private struct SavedItem {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private static func saveContents(_ pasteboard: NSPasteboard) -> [[SavedItem]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return SavedItem(type: type, data: data)
            }
        }
    }

    private static func restoreContents(_ pasteboard: NSPasteboard, items: [[SavedItem]]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        let pbItems = items.map { savedItems -> NSPasteboardItem in
            let item = NSPasteboardItem()
            savedItems.forEach { item.setData($0.data, forType: $0.type) }
            return item
        }
        pasteboard.writeObjects(pbItems)
    }
}
