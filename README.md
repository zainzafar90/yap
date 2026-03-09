# Yap

Talk. It writes for you.

Hold a hotkey, speak, Yap pastes the text into whatever you're typing in — instantly, entirely on your Mac.

## Hotkey

Two independent shortcuts — configure each to any key + modifier combo, or modifier-only:

- **Push to talk** — hold to record, release to send. Default is `⌥⌘`.
- **Hands-free** — double-tap to start, tap once more to stop. Useful when your hands are busy.

Both shortcuts are configured separately in Preferences.

## Engines

| Engine | Notes |
|---|---|
| **Direct Dictation** | Apple's built-in speech engine. No download required. |
| **Whisper** | OpenAI's model running locally. Tiny → Large v3 Turbo, pick your tradeoff. |
| **Parakeet v3** | NVIDIA's top-scoring model via FluidAudio. Blazing fast, English only. ~600 MB. |

Models download on demand from the Engine tab in Preferences. They unload from memory after 90 seconds of idle and can be deleted at any time.

## Overlay

A small indicator appears while you speak. Two styles:

- **Pill** — floats at the bottom of the screen. Springs in, fades out.
- **Notch** — extends from the MacBook notch. Best if you have one.

Both animate a live waveform driven by your mic level, and show a shimmer while the model is processing.

## Apple Intelligence

On macOS 26+, Yap can pass Dictation output through Foundation Models before pasting — cleaning up punctuation, grammar, and formatting on-device. The system prompt is editable and resettable. Doesn't apply to Whisper or Parakeet, which already output clean text.

## Vocabulary

Teach Yap words it keeps getting wrong — names, jargon, abbreviations. Add them in the Vocabulary tab and they'll be injected as hints to every supported engine.

## Requirements

- macOS 26.0+
- Microphone permission
- Accessibility permission (required for the global hotkey)
- Speech Recognition permission (Direct Dictation only)

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode 26+.

```bash
git clone <repo>
cd yap
xcodegen generate
open Yap.xcodeproj
```

SPM pulls WhisperKit and FluidAudio automatically on first build.

### Signing

Create `Local.xcconfig` in the repo root:

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Gitignored. XcodeGen picks it up — no manual edits to the project file needed.

### Re-running XcodeGen

Run `xcodegen generate` after adding or removing source files, or after pulling changes that touch `project.yml`. No need to close Xcode — it will reload automatically.


## Stack

| | |
|---|---|
| UI | SwiftUI + AppKit |
| State | `@Observable` (Swift Observation) |
| Hotkey | CGEvent tap |
| Audio capture | AVCaptureSession + vDSP |
| Dictation | SFSpeechRecognizer |
| Whisper | [WhisperKit](https://github.com/argmaxinc/WhisperKit) |
| Parakeet | [FluidAudio](https://github.com/FluidInference/FluidAudio) |
| Enhancement | Foundation Models |
| Login item | SMAppService |

## License

MIT
