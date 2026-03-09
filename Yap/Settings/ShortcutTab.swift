import SwiftUI
import AppKit
import ServiceManagement

private enum ShortcutTarget { case push, free }

struct PreferencesTab: View {
    @AppStorage(AppPreferenceKey.notchMode) private var notchMode = false

    @State private var pushShortcut = ShortcutBinding.loadFromDefaults()
    @State private var freeShortcut = ShortcutBinding.loadHandsFreeFromDefaults()
    @State private var recordingFor: ShortcutTarget?
    @State private var monitor: Any?
    @State private var recordedModifiersUnion: ShortcutBinding.Modifiers = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsSection("Shortcuts") {
                VStack(spacing: 0) {
                    shortcutRow(
                        title: "Push to talk",
                        description: "Hold to record, release to send",
                        shortcut: pushShortcut,
                        isRecording: recordingFor == .push
                    ) {
                        toggleRecording(for: .push)
                    }

                    Divider().padding(.leading, 12)

                    shortcutRow(
                        title: "Hands-free",
                        description: "Double-tap to start, tap once more to stop",
                        shortcut: freeShortcut,
                        isRecording: recordingFor == .free
                    ) {
                        toggleRecording(for: .free)
                    }
                }
                .background(.quaternary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )

                if recordingFor != nil {
                    Text("Hold any modifier (\u{2318} \u{2325} \u{2303} \u{21E7} fn) then add a key, or release modifiers alone. Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            settingsSection("Overlay") {
                HStack(spacing: 8) {
                    radioCard(
                        title: "Pill",
                        description: "Floats at the bottom of the screen. Springs in, fades out.",
                        isSelected: !notchMode
                    ) { notchMode = false }

                    radioCard(
                        title: "Notch",
                        description: "Extends from the MacBook notch. Best if you have one.",
                        isSelected: notchMode
                    ) { notchMode = true }
                }
            }

            Divider()

            settingsSection("General") {
                Toggle(isOn: launchAtLoginBinding) {
                    Text("Start with your Mac")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear {
            pushShortcut = ShortcutBinding.loadFromDefaults()
            freeShortcut = ShortcutBinding.loadHandsFreeFromDefaults()
        }
        .onDisappear { stopRecording() }
    }


    private func shortcutRow(
        title: String,
        description: String,
        shortcut: ShortcutBinding,
        isRecording: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onTap) {
                HStack(spacing: 6) {
                    Group {
                        if isRecording {
                            Text("Press keys\u{2026}")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 3) {
                                ForEach(shortcut.displayTokens, id: \.self) { token in
                                    KeyCapView(token)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 40, alignment: .leading)

                    Image(systemName: isRecording ? "xmark.circle.fill" : "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(isRecording ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: isRecording ? 1.5 : 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }


    private func radioCard(title: String, description: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }


    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else        { try SMAppService.mainApp.unregister() }
                } catch {
                    print("Launch at login toggle failed: \(error)")
                }
            }
        )
    }


    private func toggleRecording(for target: ShortcutTarget) {
        if recordingFor == target { stopRecording() } else { startRecording(for: target) }
    }

    private func startRecording(for target: ShortcutTarget) {
        stopRecording()
        recordingFor = target
        recordedModifiersUnion = []

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard self.recordingFor != nil else { return event }

            if event.type == .flagsChanged {
                let modifiers = ShortcutBinding.Modifiers(from: event.modifierFlags)
                if !modifiers.isEmpty {
                    self.recordedModifiersUnion.formUnion(modifiers)
                    return nil
                }
                if !self.recordedModifiersUnion.isEmpty {
                    self.commit(ShortcutBinding(modifiers: self.recordedModifiersUnion, keyCode: nil), for: target)
                    self.stopRecording()
                    return nil
                }
                return nil
            }

            if event.keyCode == 53 { self.stopRecording(); return nil }

            let modifiers = ShortcutBinding.Modifiers(from: event.modifierFlags)
            guard !modifiers.isEmpty else { NSSound.beep(); return nil }

            self.commit(ShortcutBinding(modifiers: modifiers, keyCode: Int(event.keyCode)), for: target)
            self.stopRecording()
            return nil
        }
    }

    private func commit(_ binding: ShortcutBinding, for target: ShortcutTarget) {
        switch target {
        case .push:
            pushShortcut = binding
            binding.saveToDefaults()
        case .free:
            freeShortcut = binding
            binding.saveHandsFreeToDefaults()
        }
    }

    private func stopRecording() {
        recordingFor = nil
        recordedModifiersUnion = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
