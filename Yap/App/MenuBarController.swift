import AppKit
import Sparkle

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var orchestrator: AppOrchestrator?

    init(orchestrator: AppOrchestrator) {
        self.orchestrator = orchestrator
        super.init()
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let icon = NSImage(named: "menubar-icon") {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Yap")
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    func updateIndicator(isActive: Bool, anyModelLoaded: Bool) {
        guard let statusItem, let button = statusItem.button else { return }
        let muted = !isActive && !anyModelLoaded

        statusItem.length = NSStatusItem.squareLength
        button.attributedTitle = NSAttributedString(string: "")

        if isActive {
            button.alphaValue = 1.0
            button.contentTintColor = .controlAccentColor
        } else {
            button.alphaValue = muted ? 0.45 : 1.0
            button.contentTintColor = muted ? NSColor.tertiaryLabelColor : nil
        }
    }


    func menuWillOpen(_ menu: NSMenu) {
        guard let orc = orchestrator else { return }
        populateMenu(menu, orchestrator: orc)
    }

    private func populateMenu(_ menu: NSMenu, orchestrator orc: AppOrchestrator) {
        menu.removeAllItems()

        let pasteItem = NSMenuItem(title: "Paste last transcript", action: #selector(pasteLastTranscript), keyEquivalent: "V")
        pasteItem.keyEquivalentModifierMask = [.control, .command]
        pasteItem.target = self
        pasteItem.isEnabled = !orc.activityLog.records.isEmpty
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        // ENGINE
        menu.addItem(sectionHeader("Engine"))
        let engineRaw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine) ?? ""
        let currentEngine = TranscriptionEngine(rawValue: engineRaw) ?? .dictation
        for engine in TranscriptionEngine.allCases {
            let needsDownload = engine.requiresModelDownload && !orc.isEngineReady(engine)
            let title = needsDownload ? "\(engine.title) — needs download" : engine.title
            let item = NSMenuItem(title: title, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue as NSString
            item.state = engine == currentEngine ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // OVERLAY
        menu.addItem(sectionHeader("Overlay"))
        let notchOn = UserDefaults.standard.bool(forKey: AppPreferenceKey.notchMode)
        let pillItem = NSMenuItem(title: "Pill — floating at bottom", action: #selector(selectOverlay(_:)), keyEquivalent: "")
        pillItem.target = self
        pillItem.representedObject = false as AnyObject
        pillItem.state = notchOn ? .off : .on
        menu.addItem(pillItem)

        let notchItem = NSMenuItem(title: "Notch — extends from notch", action: #selector(selectOverlay(_:)), keyEquivalent: "")
        notchItem.target = self
        notchItem.representedObject = true as AnyObject
        notchItem.state = notchOn ? .on : .off
        menu.addItem(notchItem)

        menu.addItem(.separator())

        // MICROPHONE (stays as submenu — dynamic list)
        let currentMicUID = UserDefaults.standard.string(forKey: AppPreferenceKey.selectedMicrophoneID) ?? ""
        let micSubmenu = NSMenu()
        let defaultItem = NSMenuItem(title: "System Default", action: #selector(selectMic(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = "" as NSString
        defaultItem.state = currentMicUID.isEmpty ? .on : .off
        micSubmenu.addItem(defaultItem)
        let devices = AudioDevice.all()
        if !devices.isEmpty { micSubmenu.addItem(.separator()) }
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid as NSString
            item.state = device.uid == currentMicUID ? .on : .off
            micSubmenu.addItem(item)
        }
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micItem.submenu = micSubmenu
        menu.addItem(micItem)

        let pushShortcut = ShortcutBinding.loadFromDefaults()
        let pushItem = NSMenuItem(title: "Push to talk  \(pushShortcut.displayString)", action: nil, keyEquivalent: "")
        pushItem.isEnabled = false
        menu.addItem(pushItem)

        let freeShortcut = ShortcutBinding.loadHandsFreeFromDefaults()
        let freeItem = NSMenuItem(title: "Hands-free  \(freeShortcut.displayString)", action: nil, keyEquivalent: "")
        freeItem.isEnabled = false
        menu.addItem(freeItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = orc.updaterController
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Yap", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }


    @objc private func pasteLastTranscript() {
        guard let record = orchestrator?.activityLog.records.first else { return }
        Typist.paste(record.text)
    }

    @objc private func selectMic(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: AppPreferenceKey.selectedMicrophoneID)
    }

    @objc private func selectOverlay(_ sender: NSMenuItem) {
        let notchOn = (sender.representedObject as? Bool) ?? false
        UserDefaults.standard.set(notchOn, forKey: AppPreferenceKey.notchMode)
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = TranscriptionEngine(rawValue: raw),
              let orc = orchestrator else { return }
        if engine.requiresModelDownload && !orc.isEngineReady(engine) {
            orc.openSettings()
            return
        }
        UserDefaults.standard.set(raw, forKey: AppPreferenceKey.transcriptionEngine)
    }

    @objc private func openSettings() {
        orchestrator?.openSettings()
    }

    @objc private func quit() {
        orchestrator?.quit()
    }
}
