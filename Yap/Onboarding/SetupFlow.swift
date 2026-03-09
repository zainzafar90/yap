import SwiftUI
import AppKit

struct SetupFlow: View {
    @State private var currentStep = 0
    @State private var shortcut = ShortcutBinding.default
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var recordedModifiersUnion: ShortcutBinding.Modifiers = []
    @AppStorage(AppPreferenceKey.transcriptionEngine)  private var engineRaw        = TranscriptionEngine.dictation.rawValue
    @AppStorage(AppPreferenceKey.whisperModelVariant)  private var whisperVariantRaw = WhisperModelVariant.tiny.rawValue
    @AppStorage(AppPreferenceKey.notchMode)            private var notchMode         = false

    var onComplete: () -> Void

    private let totalSteps = 5

    private var stepIcon: String {
        switch currentStep {
        case 0: "waveform.circle.fill"
        case 1: "keyboard"
        case 2: "brain.head.profile"
        case 3: "macwindow"
        case 4: "checkmark.circle.fill"
        default: "circle"
        }
    }

    private var stepIconColor: Color {
        switch currentStep {
        case 0: .accentColor
        case 4: .green
        default: .secondary
        }
    }

    private var stepIconSize: CGFloat {
        switch currentStep {
        case 0: 72
        case 4: 64
        default: 48
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Spacer()
                Image(systemName: stepIcon)
                    .font(.system(size: stepIconSize))
                    .foregroundStyle(stepIconColor)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                Spacer()
            }
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            .background(.quaternary.opacity(0.3))

            VStack(spacing: 0) {
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: shortcutStep
                    case 2: engineStep
                    case 3: overlayStep
                    case 4: doneStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: currentStep)

                Divider()

                HStack {
                    HStack(spacing: 6) {
                        ForEach(0..<totalSteps, id: \.self) { step in
                            Circle()
                                .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }

                    Spacer()

                    if currentStep > 0 && currentStep < totalSteps - 1 {
                        Button("Back") {
                            stopRecording()
                            currentStep -= 1
                        }
                        .controlSize(.regular)
                    }

                    if currentStep < totalSteps - 1 {
                        Button("Continue") {
                            stopRecording()
                            if currentStep == 1 { shortcut.saveToDefaults() }
                            currentStep += 1
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get Started") {
                            shortcut.saveToDefaults()
                            UserDefaults.standard.set(true, forKey: AppPreferenceKey.hasCompletedOnboarding)
                            onComplete()
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 620, height: 440)
        .onDisappear { stopRecording() }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("Talk. It writes for you.")
                .font(.title.bold())
            Text("Yap turns your voice into text — on-device, private, instant. No subscription. No cloud.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            Text("Set your shortcut")
                .font(.title2.bold())

            Text("This is your push-to-talk shortcut. Hold it down to record, release to stop. Set up hands-free in Preferences.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        ForEach(shortcut.displayTokens, id: \.self) { token in
                            SetupKeyCapView(token)
                        }
                    }
                    Button(isRecording ? "Press keys\u{2026}" : "Change") {
                        if isRecording { stopRecording() } else { startRecording() }
                    }
                    .controlSize(.small)
                    Button("Reset") { shortcut = .default; stopRecording() }
                        .controlSize(.small)
                }

                if isRecording {
                    Text("Hold any modifier (\u{2318} \u{2325} \u{2303} \u{21E7} fn) then release, or add a key. Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()

            Text("Choose your engine")
                .font(.title2.bold())

            Text("Direct Dictation works immediately. AI engines are more accurate but need a one-time download.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(TranscriptionEngine.allCases) { engine in
                    let isSelected = engineRaw == engine.rawValue
                    Button {
                        engineRaw = engine.rawValue
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: engineIcon(engine))
                                .frame(width: 20)
                                .foregroundStyle(isSelected ? .white : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(engine.description)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .opacity(0.8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .white : .primary)
                }
            }

            if engineRaw == TranscriptionEngine.whisper.rawValue {
                whisperVariantPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .animation(.easeInOut(duration: 0.2), value: engineRaw)
    }

    private var whisperVariantPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model size")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 4) {
                ForEach(WhisperModelVariant.allCases) { variant in
                    let isSelected = whisperVariantRaw == variant.rawValue
                    Button {
                        whisperVariantRaw = variant.rawValue
                    } label: {
                        VStack(spacing: 1) {
                            Text(variant.title)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(variant.sizeDescription)
                                .font(.system(size: 8))
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .white : .primary)
                }
            }

            Text(WhisperModelVariant(rawValue: whisperVariantRaw)?.qualityDescription ?? "")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var overlayStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            Text("Pick your overlay")
                .font(.title2.bold())

            Text("Yap shows a small UI while you speak. Choose what fits your setup.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                overlayOption(
                    title: "Pill",
                    description: "Floats at the bottom of the screen. Springs in, fades out.",
                    icon: "capsule.fill",
                    isSelected: !notchMode
                ) {
                    notchMode = false
                }

                overlayOption(
                    title: "Notch",
                    description: "Extends from the MacBook notch. Best if you have one.",
                    icon: "macwindow",
                    isSelected: notchMode
                ) {
                    notchMode = true
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func overlayOption(title: String, description: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("You're all set")
                .font(.title2.bold())

            let shortcutDisplay = shortcut.displayString
            let overlayDisplay = notchMode ? "notch" : "pill"

            Text("Hold **\(shortcutDisplay)** to talk, release to stop. The **\(overlayDisplay)** overlay will appear while you speak. Yap lives in your menu bar — tweak anything in Preferences.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func engineIcon(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .dictation: return "mic.fill"
        case .whisper:   return "waveform"
        case .parakeet:  return "bird"
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        recordedModifiersUnion = []

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if !isRecording { return event }

            if event.type == .flagsChanged {
                let modifiers = ShortcutBinding.Modifiers(from: event.modifierFlags)
                if !modifiers.isEmpty {
                    recordedModifiersUnion.formUnion(modifiers)
                    return nil
                }
                if !recordedModifiersUnion.isEmpty {
                    shortcut = ShortcutBinding(modifiers: recordedModifiersUnion, keyCode: nil)
                    stopRecording()
                    return nil
                }
                return nil
            }

            if event.keyCode == 53 { stopRecording(); return nil }

            let modifiers = ShortcutBinding.Modifiers(from: event.modifierFlags)
            guard !modifiers.isEmpty else { NSSound.beep(); return nil }

            shortcut = ShortcutBinding(modifiers: modifiers, keyCode: Int(event.keyCode))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        recordedModifiersUnion = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct SetupKeyCapView: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 14, weight: .medium))
            .frame(minWidth: 26, minHeight: 24)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
    }
}
