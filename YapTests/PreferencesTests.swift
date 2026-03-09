import XCTest
@testable import Yap

final class PreferencesTests: XCTestCase {

    func testTranscriptionEngineAllCases() {
        let cases = TranscriptionEngine.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.dictation))
        XCTAssertTrue(cases.contains(.whisper))
        XCTAssertTrue(cases.contains(.parakeet))
    }

    func testTranscriptionEngineRawValues() {
        XCTAssertEqual(TranscriptionEngine.dictation.rawValue, "dictation")
        XCTAssertEqual(TranscriptionEngine.whisper.rawValue, "whisper")
        XCTAssertEqual(TranscriptionEngine.parakeet.rawValue, "parakeet")
    }

    func testTranscriptionEngineRequiresModelDownload() {
        XCTAssertFalse(TranscriptionEngine.dictation.requiresModelDownload)
        XCTAssertTrue(TranscriptionEngine.whisper.requiresModelDownload)
        XCTAssertTrue(TranscriptionEngine.parakeet.requiresModelDownload)
    }

    func testTranscriptionEngineTitlesAreNonEmpty() {
        for engine in TranscriptionEngine.allCases {
            XCTAssertFalse(engine.title.isEmpty, "\(engine) has empty title")
            XCTAssertFalse(engine.description.isEmpty, "\(engine) has empty description")
        }
    }

    func testTranscriptionEngineIdentifiable() {
        for engine in TranscriptionEngine.allCases {
            XCTAssertEqual(engine.id, engine.rawValue)
        }
    }

    func testTranscriptionEngineRoundTripFromRawValue() {
        for engine in TranscriptionEngine.allCases {
            XCTAssertEqual(TranscriptionEngine(rawValue: engine.rawValue), engine)
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(TranscriptionEngine(rawValue: "invalid"))
        XCTAssertNil(RecordingMode(rawValue: "invalid"))
        XCTAssertNil(EnhancementMode(rawValue: "invalid"))
    }

    func testRecordingModeAllCases() {
        let cases = RecordingMode.allCases
        XCTAssertEqual(cases.count, 2)
        XCTAssertTrue(cases.contains(.holdToTalk))
        XCTAssertTrue(cases.contains(.toggle))
    }

    func testRecordingModeRawValues() {
        XCTAssertEqual(RecordingMode.holdToTalk.rawValue, "holdToTalk")
        XCTAssertEqual(RecordingMode.toggle.rawValue, "toggle")
    }

    func testRecordingModeTitlesAreNonEmpty() {
        for mode in RecordingMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.description.isEmpty)
        }
    }

    func testRecordingModeIdentifiable() {
        for mode in RecordingMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testEnhancementModeAllCases() {
        let cases = EnhancementMode.allCases
        XCTAssertEqual(cases.count, 2)
        XCTAssertTrue(cases.contains(.off))
        XCTAssertTrue(cases.contains(.appleIntelligence))
    }

    func testEnhancementModeRawValues() {
        XCTAssertEqual(EnhancementMode.off.rawValue, "off")
        XCTAssertEqual(EnhancementMode.appleIntelligence.rawValue, "appleIntelligence")
    }

    func testEnhancementModeTitlesAreNonEmpty() {
        for mode in EnhancementMode.allCases {
            XCTAssertFalse(mode.title.isEmpty, "\(mode) has empty title")
        }
    }

    func testEnhancementModeIdentifiable() {
        for mode in EnhancementMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testPreferenceKeysAreUnique() {
        let keys = [
            AppPreferenceKey.transcriptionEngine,
            AppPreferenceKey.enhancementMode,
            AppPreferenceKey.enhancementSystemPrompt,
            AppPreferenceKey.recordingMode,
            AppPreferenceKey.shortcutBinding,
            AppPreferenceKey.whisperModelVariant,
            AppPreferenceKey.notchMode,
            AppPreferenceKey.selectedMicrophoneID,
            AppPreferenceKey.appendTrailingSpace,
            AppPreferenceKey.launchAtLogin,
        ]
        XCTAssertEqual(keys.count, Set(keys).count, "Preference keys must be unique")
    }

    func testDefaultEnhancementPromptIsNonEmpty() {
        XCTAssertFalse(AppPreferenceKey.defaultEnhancementPrompt.isEmpty)
        XCTAssertTrue(AppPreferenceKey.defaultEnhancementPrompt.contains("Yap"))
    }

    func testHotkeyModeIsAliasForRecordingMode() {
        XCTAssertEqual(HotkeyMode.holdToTalk.rawValue, RecordingMode.holdToTalk.rawValue)
        XCTAssertEqual(HotkeyMode.toggle.rawValue, RecordingMode.toggle.rawValue)
    }
}
