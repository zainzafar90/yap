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
    private let toast = YapToast()

    private lazy var windowCoordinator = WindowCoordinator(orchestrator: self)
    private lazy var menuController    = MenuBarController(orchestrator: self)

    private var activeEngine:          (any VoiceEngine)?
    private var activeTranscription:   TranscriptionEngine = .dictation
    private var activeEnhancementMode: EnhancementMode     = .off
    private var isSessionActive        = false

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

        // If Whisper/Parakeet is selected but kit/manager not yet in memory, fall back to Dictation this session and warm up in background
        let effectiveEngine: any VoiceEngine
        if engine == .whisper && !whisperCatalog.isKitLoaded {
            Task { _ = try? await self.whisperCatalog.resolveKit() }
            toast.show(
                "Your selected model is loading in the background. Fallback to Dictation for this session.")
            effectiveEngine = dictationEngine
        } else if engine == .parakeet && !fluidCatalog.isManagerLoaded {
            Task { _ = try? await self.fluidCatalog.resolveManager() }
            toast.show(
                "Your selected model is loading in the background. Fallback to Dictation for this session.")
            effectiveEngine = dictationEngine
        } else {
            effectiveEngine = voiceEngine
        }

        effectiveEngine.vocabulary = words
        effectiveEngine.deviceUID  = micUID
        effectiveEngine.onComplete = { [weak self] text in
            self?.processCompletion(text)
        }

        activeEngine = effectiveEngine
        driver.onStop   = { [weak self] in self?.endCapture() }
        driver.onCancel = { [weak self] in self?.cancelCapture() }
        driver.attach(to: effectiveEngine)

        overlay.show(driver: driver, notchMode: notchModeEnabled)
        effectiveEngine.beginCapture()
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
    }

    private func processCompletion(_ rawText: String) {
        let engine  = activeTranscription
        let enhance = activeEnhancementMode

        guard !rawText.isEmpty else {
            overlay.hide(driver: driver)
            isSessionActive = false
            activeEngine    = nil
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
            switch whisperCatalog.status {
            case .live, .fetching: return true
            default: return false
            }
        case .parakeet:
            switch fluidCatalog.status {
            case .live, .fetching: return true
            default: return false
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
