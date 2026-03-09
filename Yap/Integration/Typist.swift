import AppKit

@MainActor
struct Typist {
    static func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let output = text

        let pasteboard = NSPasteboard.general
        let savedItems = saveContents(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)

        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restoreContents(pasteboard, items: savedItems)
        }
    }

    private static func simulatePaste() {
        let source  = CGEventSource(stateID: .hidSystemState)
        let vKey:   CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
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
