import AppKit
import SwiftUI
import Sparkle

@MainActor
final class AppOrchestrator: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    let whisperCatalog = WhisperCatalog()
    let fluidCatalog   = FluidCatalog()
    let activityLog    = ActivityLog()
    let wordBank       = WordBank()

    private let dictationEngine = DictationEngine()
    private var whisperEngine:  WhisperEngine?
    private var parakeetEngine: ParakeetEngine?

    private let listener = ShortcutListener()
    private let overlay  = OverlayPanel()
    private let driver   = OverlayDriver()

    private lazy var windowCoordinator = WindowCoordinator(orchestrator: self)
    private lazy var menuController    = MenuBarController(orchestrator: self)

    private var activeEngine:          (any VoiceEngine)?
    private var activeTranscription:   TranscriptionEngine = .dictation
    private var activeEnhancementMode: EnhancementMode     = .off
    private var isSessionActive        = false
    private var idleUnloadTask:        Task<Void, Never>?
    private static let unloadDelay:    Duration = .seconds(90)

    private var preferenceObserver: NSObjectProtocol?


    private var transcriptionEngine: TranscriptionEngine {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.transcriptionEngine)
        return TranscriptionEngine(rawValue: raw ?? "") ?? .dictation
    }

    private var enhancementMode: EnhancementMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementMode)
        return EnhancementMode(rawValue: raw ?? "") ?? .off
    }

    private var notchModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.notchMode)
    }

    private var selectedMicUID: String? {
        let stored = UserDefaults.standard.string(forKey: AppPreferenceKey.selectedMicrophoneID) ?? ""
        guard !stored.isEmpty, AudioDevice.isValid(uid: stored) else { return nil }
        return stored
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKey.notchMode:           false,
            AppPreferenceKey.transcriptionEngine: TranscriptionEngine.dictation.rawValue,
            AppPreferenceKey.enhancementMode:     EnhancementMode.off.rawValue,
        ])
        NSApp.setActivationPolicy(.accessory)

        menuController.setup()

        Task {
            await dictationEngine.requestAccess()

            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                windowCoordinator.showOnboarding { [weak self] in
                    self?.finishSetup()
                }
            } else {
                finishSetup()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        listener.stop()
        if let obs = preferenceObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }


    private func finishSetup() {
        setupListener()
        if notchModeEnabled {
            overlay.showIdle(driver: driver)
        }
    }

    private func setupListener() {
        listener.shortcut          = ShortcutBinding.loadFromDefaults()
        listener.handsFreeShortcut = ShortcutBinding.loadHandsFreeFromDefaults()
        listener.onActivate   = { [weak self] in self?.beginCapture() }
        listener.onDeactivate = { [weak self] in self?.endCapture() }

        let started = listener.start()
        if !started {
            NSLog("[Yap] Accessibility not granted. Grant permission and relaunch.")
        }

        preferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newShortcut  = ShortcutBinding.loadFromDefaults()
                let newHandsFree = ShortcutBinding.loadHandsFreeFromDefaults()
                if self.listener.shortcut          != newShortcut  { self.listener.shortcut          = newShortcut }
                if self.listener.handsFreeShortcut != newHandsFree { self.listener.handsFreeShortcut = newHandsFree }
            }
        }
    }


    private func beginCapture() {
        guard !isSessionActive else { return }
        isSessionActive = true

        let engine  = transcriptionEngine
        let enhance = enhancementMode
        let words   = wordBank.words
        let micUID  = selectedMicUID

        activeTranscription   = engine
        activeEnhancementMode = enhance

        guard let voiceEngine = resolveEngine(engine) else {
            showHint("\(engine.title): Download model in Settings")
            isSessionActive = false
            return
        }

        voiceEngine.vocabulary = words
        voiceEngine.deviceUID  = micUID
        voiceEngine.onComplete = { [weak self] text in
            self?.processCompletion(text)
        }

        activeEngine = voiceEngine
        driver.onStop   = { [weak self] in self?.endCapture() }
        driver.onCancel = { [weak self] in self?.cancelCapture() }
        driver.attach(to: voiceEngine)

        overlay.show(driver: driver, notchMode: notchModeEnabled)
        voiceEngine.beginCapture()
    }

    private func endCapture() {
        listener.resetState()
        guard isSessionActive, let engine = activeEngine else { return }
        engine.endCapture()
    }

    private func cancelCapture() {
        guard isSessionActive, let engine = activeEngine else { return }
        engine.onComplete = nil
        engine.endCapture()
        listener.resetState()
        overlay.hide(driver: driver)
        isSessionActive = false
        activeEngine    = nil
        scheduleIdleUnload()
    }

    private func processCompletion(_ rawText: String) {
        let engine  = activeTranscription
        let enhance = activeEnhancementMode

        guard !rawText.isEmpty else {
            overlay.hide(driver: driver)
            isSessionActive = false
            activeEngine    = nil
            scheduleIdleUnload()
            return
        }

        if enhance == .appleIntelligence, engine == .dictation {
            driver.isRefining = true
            Task {
                defer {
                    self.driver.isRefining = false
                    self.overlay.hide(driver: self.driver)
                    self.isSessionActive = false
                    self.activeEngine    = nil
                    self.scheduleIdleUnload()
                }
                if #available(macOS 26.0, *), TextRefiner.isAvailable {
                    do {
                        var prompt = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementSystemPrompt)
                            ?? AppPreferenceKey.defaultEnhancementPrompt
                        let words = self.wordBank.words
                        if !words.isEmpty {
                            prompt += "\n\nIMPORTANT: Preserve exact spelling and casing: \(words.joined(separator: ", "))."
                        }
                        let refiner  = TextRefiner()
                        let enhanced = try await refiner.enhance(rawText, systemPrompt: prompt)
                        Typist.paste(enhanced)
                        self.activityLog.append(ActivityRecord(text: enhanced, engine: engine, wasEnhanced: true))
                        return
                    } catch {
                        print("[Yap] Enhancement failed: \(error)")
                    }
                }
                Typist.paste(rawText)
                self.activityLog.append(ActivityRecord(text: rawText, engine: engine, wasEnhanced: false))
            }
        } else {
            Typist.paste(rawText)
            activityLog.append(ActivityRecord(text: rawText, engine: engine, wasEnhanced: false))
            overlay.hide(driver: driver)
            isSessionActive = false
            activeEngine    = nil
            scheduleIdleUnload()
        }
    }


    private func resolveEngine(_ engine: TranscriptionEngine) -> (any VoiceEngine)? {
        switch engine {
        case .dictation:
            return dictationEngine

        case .whisper:
            guard isEngineReady(.whisper) else { return nil }
            let e = whisperEngine ?? WhisperEngine(catalog: whisperCatalog)
            whisperEngine = e
            return e

        case .parakeet:
            guard isEngineReady(.parakeet) else { return nil }
            let e = parakeetEngine ?? ParakeetEngine(catalog: fluidCatalog)
            parakeetEngine = e
            return e

        }
    }

    func isEngineReady(_ engine: TranscriptionEngine) -> Bool {
        switch engine {
        case .dictation: return true
        case .whisper:
            switch whisperCatalog.state {
            case .downloaded, .ready, .loading: return true
            default: return false
            }
        case .parakeet:
            switch fluidCatalog.parakeetState {
            case .downloaded, .ready, .loading: return true
            default: return false
            }
        }
    }


    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.unloadDelay) } catch { return }
            await MainActor.run {
                guard let self, !self.isSessionActive else { return }
                self.whisperCatalog.unloadModelFromMemory()
                self.fluidCatalog.unloadParakeet()
                self.whisperEngine  = nil
                self.parakeetEngine = nil
            }
        }
    }


    private func showHint(_ message: String) {
        driver.liveText = message
        overlay.show(driver: driver, notchMode: notchModeEnabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            self.overlay.hide(driver: self.driver)
        }
    }


    func openSettings() {
        windowCoordinator.openSettings()
    }

    func quit() {
        listener.stop()
        NSApp.terminate(nil)
    }
}
