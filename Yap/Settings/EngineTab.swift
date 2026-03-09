import SwiftUI
import AppKit
import AVFoundation
import FluidAudio

struct EngineTab: View {
    var whisperCatalog: WhisperCatalog
    var fluidCatalog:   FluidCatalog

    @AppStorage(AppPreferenceKey.transcriptionEngine)    private var engineRaw          = TranscriptionEngine.dictation.rawValue
    @AppStorage(AppPreferenceKey.selectedMicrophoneID)   private var selectedMicrophoneID = ""
    @AppStorage(AppPreferenceKey.enhancementMode)        private var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) private var systemPrompt      = AppPreferenceKey.defaultEnhancementPrompt

    @State private var availableDevices: [AudioDevice] = []
    @State private var deviceObserver = AudioDeviceWatcher()
    @State private var storageVersion: Int = 0

    // Shortcut state (moved from PreferencesTab)
    private enum ShortcutTarget { case push, free }
    @State private var pushShortcut = ShortcutBinding.loadFromDefaults()
    @State private var freeShortcut = ShortcutBinding.loadHandsFreeFromDefaults()
    @State private var recordingFor: ShortcutTarget?
    @State private var monitor: Any?
    @State private var recordedModifiersUnion: ShortcutBinding.Modifiers = []

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .dictation
    }

    private var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) { return TextRefiner.isAvailable }
        return false
    }

    private var isWhisperBusy: Bool {
        switch whisperCatalog.status {
        case .fetching: return true
        default: return false
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding(
            get: {
                guard !selectedMicrophoneID.isEmpty else { return "" }
                return availableDevices.contains(where: { $0.uid == selectedMicrophoneID }) ? selectedMicrophoneID : ""
            },
            set: { selectedMicrophoneID = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                settingsSection("Microphone") {
                    Picker("Microphone", selection: microphoneSelection) {
                        Text("System Default").tag("")
                        ForEach(availableDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                }

                Divider()

                settingsSection("Keyboard Shortcut") {
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

                settingsSection("Model Storage") {
                    storageSection
                }

                Divider()

                settingsSection("Speech Models") {
                    VStack(spacing: 0) {
                        ForEach(Array(TranscriptionEngine.allCases.enumerated()), id: \.element) { index, engine in
                            engineRow(engine)
                            if index < TranscriptionEngine.allCases.count - 1 {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .background(.quaternary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                }

                Divider()

                settingsSection("Apple Intelligence") {
                    Toggle(isOn: Binding(
                        get: { enhancementModeRaw == EnhancementMode.appleIntelligence.rawValue },
                        set: { enhancementModeRaw = ($0 ? EnhancementMode.appleIntelligence : EnhancementMode.off).rawValue }
                    )) {
                        Text("Clean up before pasting")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(selectedEngine != .dictation)

                    if selectedEngine != .dictation {
                        Text("Whisper and Parakeet already produce clean output — no styling needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !appleIntelligenceAvailable {
                        Text("Apple Intelligence isn't available on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if enhancementModeRaw == EnhancementMode.appleIntelligence.rawValue, selectedEngine == .dictation {
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 120)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.quaternary.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )

                        HStack {
                            Text("Guides Apple Intelligence on tone, format, and style.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("Reset") {
                                systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
                            }
                            .controlSize(.small)
                            .disabled(systemPrompt == AppPreferenceKey.defaultEnhancementPrompt)
                        }
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .onAppear {
            pushShortcut = ShortcutBinding.loadFromDefaults()
            freeShortcut = ShortcutBinding.loadHandsFreeFromDefaults()
            refreshDevices()
            deviceObserver.onChange = { refreshDevices() }
            deviceObserver.start()
        }
        .onDisappear {
            stopRecording()
            deviceObserver.stop()
        }
    }


    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let _ = storageVersion
            let totalBytes = whisperTotalBytes + parakeetTotalBytes
            if totalBytes > 0 {
                Text("On disk: \(formatBytes(totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let unusedVariants = unusedWhisperVariants
            let parakeetUnused: Bool = {
                guard selectedEngine != .parakeet else { return false }
                if case .fetching = fluidCatalog.status { return true }
                if case .live = fluidCatalog.status { return parakeetTotalBytes > 50_000_000 }
                return false
            }()

            if !unusedVariants.isEmpty || parakeetUnused {
                let unusedNames: [String] =
                    unusedVariants.map(\.title) + (parakeetUnused ? ["Parakeet"] : [])
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Some models might be taking up space without being used")
                            .font(.system(size: 12, weight: .medium))
                        Text(unusedNames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            if totalBytes == 0 {
                Text("No models downloaded")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var unusedWhisperVariants: [WhisperModelVariant] {
        WhisperModelVariant.allCases.filter { variant in
            guard variant != whisperCatalog.selectedVariant else { return false }
            guard variant != whisperCatalog.fetchingVariant  else { return false }
            let dir = WhisperCatalog.storeRoot.appendingPathComponent(variant.rawValue, isDirectory: true)
            let fm = FileManager.default
            if let stored = UserDefaults.standard.string(forKey: "whisperModelPath_\(variant.rawValue)"),
               fm.fileExists(atPath: stored) { return true }
            if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
               contents.contains(where: { $0.hasDirectoryPath && $0.lastPathComponent.lowercased().contains("whisper") }) { return true }
            return false
        }
    }

    private var whisperTotalBytes: UInt64 {
        (try? FileManager.default.allocatedSizeOfDirectory(at: WhisperCatalog.storeRoot)) ?? 0
    }

    private var parakeetTotalBytes: UInt64 {
        (try? FileManager.default.allocatedSizeOfDirectory(at: AsrModels.defaultCacheDirectory(for: .v3))) ?? 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func removeWhisperVariant(_ variant: WhisperModelVariant) {
        let dir = WhisperCatalog.storeRoot.appendingPathComponent(variant.rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        UserDefaults.standard.removeObject(forKey: "whisperModelPath_\(variant.rawValue)")
    }


    // MARK: - Engine Rows

    @ViewBuilder
    private func engineRow(_ engine: TranscriptionEngine) -> some View {
        let isSelected = engine == selectedEngine
        let isLive: Bool = {
            switch engine {
            case .dictation: return true
            case .whisper: if case .live = whisperCatalog.status { return true }; return false
            case .parakeet: if case .live = fluidCatalog.status { return true }; return false
            }
        }()

        Button {
            engineRaw = engine.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(
                            isSelected
                                ? Color.accentColor
                                : (isLive ? Color.secondary : Color.secondary.opacity(0.4)))
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(engine.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isSelected || isLive ? .primary : .secondary)

                            if !engine.requiresModelDownload {
                                Text("Built-in")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }

                        Text(engine.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if engine == .whisper {
                    let showStatus = isSelected || !isLive
                    if showStatus {
                        VStack(alignment: .leading, spacing: 8) {
                            if isSelected { whisperVariantPicker }
                            whisperStatusRow
                        }
                        .padding(.leading, 36)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                    }
                }

                if engine == .parakeet {
                    let showStatus = isSelected || !isLive
                    if showStatus {
                        parakeetStatusRow
                            .padding(.leading, 36)
                            .padding(.trailing, 12)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }


    private var whisperVariantPicker: some View {
        HStack(spacing: 4) {
            ForEach(WhisperModelVariant.allCases) { variant in
                let isSelected = whisperCatalog.selectedVariant == variant
                Button {
                    whisperCatalog.selectedVariant = variant
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
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .white : .primary)
                .disabled(isWhisperBusy)
            }
        }
    }


    @ViewBuilder
    private var whisperStatusRow: some View {
        switch whisperCatalog.status {
        case .absent:
            HStack(spacing: 8) {
                Text("Not downloaded · \(whisperCatalog.selectedVariant.sizeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    Task { await whisperCatalog.fetch() }
                }
                .controlSize(.small)
            }

        case .fetching(let progress):
            HStack(spacing: 8) {
                ProgressView(value: max(0, progress))
                    .frame(maxWidth: 120)
                Text("\(Int(max(0, progress) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .destructive) {
                    whisperCatalog.cancelFetch()
                }
                .controlSize(.small)
            }

        case .live:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Ready")
                if !whisperCatalog.storageLabel.isEmpty {
                    Text("· \(whisperCatalog.storageLabel)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    whisperCatalog.remove()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .broken(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") {
                    whisperCatalog.remove()
                    Task { await whisperCatalog.fetch() }
                }
                .controlSize(.small)
            }
        }
    }


    @ViewBuilder
    private var parakeetStatusRow: some View {
        switch fluidCatalog.status {
        case .absent:
            HStack(spacing: 8) {
                Text("Not downloaded · ~600 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    Task { await fluidCatalog.fetch() }
                }
                .controlSize(.small)
            }

        case .fetching(let progress):
            HStack(spacing: 8) {
                if progress < 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: progress)
                        .frame(maxWidth: 120)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel", role: .destructive) {
                    fluidCatalog.cancelFetch()
                }
                .controlSize(.small)
            }

        case .live:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Ready")
                if !fluidCatalog.storageLabel.isEmpty {
                    Text("· \(fluidCatalog.storageLabel)")
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    fluidCatalog.remove()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .broken(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") {
                    fluidCatalog.remove()
                    Task { await fluidCatalog.fetch() }
                }
                .controlSize(.small)
            }
        }
    }


    // MARK: - Microphone

    private func refreshDevices() {
        availableDevices = AudioDevice.all()
        guard !selectedMicrophoneID.isEmpty else { return }
        if !AudioDevice.isValid(uid: selectedMicrophoneID) {
            selectedMicrophoneID = ""
        }
    }


    // MARK: - Shortcut Recording

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


