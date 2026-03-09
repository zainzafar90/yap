import Foundation

enum TranscriptionEngine: String, CaseIterable, Identifiable, Sendable {
    case dictation
    case whisper
    case parakeet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Direct Dictation"
        case .whisper:   return "Whisper (OpenAI)"
        case .parakeet:  return "Parakeet v3 (NVIDIA)"
        }
    }

    var description: String {
        switch self {
        case .dictation: return "Apple's speech engine. No download, just works."
        case .whisper:   return "OpenAI's model running on your Mac. Needs a one-time download."
        case .parakeet:  return "NVIDIA's top-scoring model. Blazing fast, English only."
        }
    }

    var requiresModelDownload: Bool {
        switch self {
        case .dictation:           return false
        case .whisper, .parakeet:  return true
        }
    }
}

enum RecordingMode: String, CaseIterable, Identifiable, Sendable {
    case holdToTalk
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk: return "Hold to Talk"
        case .toggle:     return "Press to Toggle"
        }
    }

    var description: String {
        switch self {
        case .holdToTalk: return "Hold to talk. Let go and it stops."
        case .toggle:     return "Press once to start. Press again to stop."
        }
    }
}

enum EnhancementMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case appleIntelligence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:               return "Off"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }
}

/// Migration alias — old code used HotkeyMode, new code uses RecordingMode
typealias HotkeyMode = RecordingMode

enum AppPreferenceKey {
    static let transcriptionEngine     = "transcriptionEngine"
    static let enhancementMode         = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let recordingMode           = "hotkeyMode"      // legacy key — kept for UserDefaults compat
    static let hotkeyMode              = recordingMode     // migration alias for old code
    static let shortcutBinding         = "hotkeyShortcut"  // legacy key — kept for UserDefaults compat
    static let hotkeyShortcut          = shortcutBinding   // migration alias for old code
    static let handsFreeBinding        = "handsFreeBinding"
    static let whisperModelVariant     = "whisperModelVariant"
    static let notchMode               = "notchMode"
    static let selectedMicrophoneID    = "selectedMicrophoneID"
    static let appendTrailingSpace     = "appendTrailingSpace"
    static let launchAtLogin           = "launchAtLogin"
    static let hasCompletedOnboarding  = "hasCompletedOnboarding"

    static let defaultEnhancementPrompt = """
        You are Yap, a speech-to-text assistant. Clean up raw transcription: \
        fix punctuation, capitalization, and formatting. Don't change the \
        meaning or wording. Return only the cleaned text.
        """
}
