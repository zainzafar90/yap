import Foundation
import Speech
import AVFoundation
import Observation

@Observable @MainActor
final class DictationEngine: VoiceEngine {
    var isActive:     Bool   = false
    var signalLevel:  Float  = 0.0
    var liveText:     String = ""
    var isRefining:   Bool   = false
    var deviceUID:    String? = nil
    var vocabulary:   [String] = []
    var onComplete:   ((String) -> Void)?

    private var speechRecognizer:   SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let pipeline = AudioPipeline()

    private var finalizeTimeoutTask:     Task<Void, Never>?
    private var hasDeliveredFinalResult = false

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    deinit {
        pipeline.stop()
    }

    func requestAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            DispatchQueue.global().async {
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func beginCapture() {
        guard !isActive else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        cleanupSessionState()
        liveText   = ""
        signalLevel = 0
        hasDeliveredFinalResult = false

        do {
            try startSpeechRecognition(recognizer: recognizer)
            isActive = true
        } catch {
            print("DictationEngine: Failed to start: \(error)")
            cleanupSessionState()
        }
    }

    func endCapture() {
        guard isActive else { return }

        stopAudioCapture()
        isActive = false

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                self?.forceFinalizeIfNeeded()
            }
        }
    }

    private func cleanupSessionState() {
        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask   = nil
        recognitionRequest = nil
    }

    private func stopAudioCapture() {
        pipeline.stop()
        recognitionRequest?.endAudio()
    }

    private func forceFinalizeIfNeeded() {
        guard !hasDeliveredFinalResult else { return }
        finishRecognition(with: liveText)
    }

    private func finishRecognition(with text: String) {
        guard !hasDeliveredFinalResult else { return }
        hasDeliveredFinalResult = true

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask   = nil
        recognitionRequest = nil

        onComplete?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func startSpeechRecognition(recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask   = nil
        recognitionRequest = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if !vocabulary.isEmpty {
            request.contextualStrings = vocabulary
        }
        recognitionRequest = request

        pipeline.stop()
        pipeline.onChunk = { [weak self, weak request] chunk in
            request?.appendAudioSampleBuffer(chunk.sampleBuffer)
            let normalized = DictationEngine.normalizedLevel(from: chunk.monoSamples)
            Task { @MainActor [weak self] in
                self?.signalLevel = normalized
            }
        }
        try pipeline.start(deviceUID: deviceUID)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.liveText = text
                    if result.isFinal {
                        self.finishRecognition(with: text)
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 216 && nsError.code != 1110) {
                    print("DictationEngine: Recognition error: \(error)")
                }
                Task { @MainActor in
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.finishRecognition(with: "")
                        return
                    }
                    self.finishRecognition(with: self.liveText)
                }
            }
        }
    }
}
