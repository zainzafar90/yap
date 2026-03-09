import Foundation
import AVFoundation
import Accelerate
import WhisperKit
import Observation

private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class WhisperAudioBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.zainzafar.yap.whisper.buffer")
    private var samples:    [Float] = []
    private var sampleRate: Double  = 16000

    static let maxSeconds: Double = 300
    private static let initialCapacity = 48000 * 60

    func reset() {
        queue.sync {
            samples = []
            samples.reserveCapacity(Self.initialCapacity)
        }
    }

    func append(chunk: AudioPipeline.AudioChunk) {
        let maxSamples = Int(chunk.sampleRate * Self.maxSeconds)
        queue.sync {
            sampleRate = chunk.sampleRate
            guard samples.count < maxSamples else { return }
            let remaining = maxSamples - samples.count
            samples.append(contentsOf: chunk.monoSamples.prefix(remaining))
        }
    }

    func extract() -> (audio: [Float], sampleRate: Double) {
        queue.sync {
            let audio = samples; let rate = sampleRate
            samples = []
            return (audio, rate)
        }
    }
}

@Observable @MainActor
final class WhisperEngine: VoiceEngine {
    var isActive:    Bool   = false
    var signalLevel: Float  = 0.0
    var liveText:    String = ""
    var isRefining:  Bool   = false
    var deviceUID:   String? = nil
    var vocabulary:  [String] = []
    var onComplete:  ((String) -> Void)?

    private let pipeline    = AudioPipeline()
    private let catalog:    WhisperCatalog
    private let audioBuffer = WhisperAudioBuffer()
    private var transcriptionTask: Task<Void, Never>?

    init(catalog: WhisperCatalog) {
        self.catalog = catalog
    }

    func requestAccess() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    func beginCapture() {
        guard !isActive else { return }
        transcriptionTask?.cancel()
        transcriptionTask = nil

        audioBuffer.reset()
        liveText    = ""
        signalLevel = 0

        do {
            pipeline.stop()
            let buffer = audioBuffer
            pipeline.onChunk = { chunk in
                buffer.append(chunk: chunk)
                let normalized = WhisperEngine.normalizedLevel(from: chunk.monoSamples)
                Task { @MainActor [weak self] in
                    self?.signalLevel = normalized
                }
            }
            try pipeline.start(deviceUID: deviceUID)
            isActive = true
        } catch {
            print("WhisperEngine: Failed to start: \(error)")
            pipeline.stop()
            isActive = false
        }
    }

    func endCapture() {
        guard isActive else { return }

        pipeline.stop()
        isActive = false

        let (capturedAudio, sampleRate) = audioBuffer.extract()
        guard !capturedAudio.isEmpty else { onComplete?(""); return }

        isRefining = true
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            await self?.transcribeAudio(capturedAudio, inputSampleRate: sampleRate)
        }
    }

    private func transcribeAudio(_ samples: [Float], inputSampleRate: Double) async {
        defer { isRefining = false }
        guard !Task.isCancelled else { return }
        do {
            try await catalog.loadModel()
            guard !Task.isCancelled else { return }
            guard let kit = catalog.loadedKit else { onComplete?(""); return }

            let words = vocabulary
            let wrappedKit = UnsafeSendable(kit)
            let text = try await Task.detached(priority: .userInitiated) {
                let kit = wrappedKit.value
                let targetSampleRate = Double(WhisperKit.sampleRate)

                let audioForWhisper: [Float]
                if abs(inputSampleRate - targetSampleRate) > 1.0 {
                    audioForWhisper = Self.resample(samples, from: inputSampleRate, to: targetSampleRate)
                } else {
                    audioForWhisper = samples
                }

                var decodeOptions = DecodingOptions()
                if !words.isEmpty, let tokenizer = kit.tokenizer {
                    let prompt = words.joined(separator: ", ")
                    decodeOptions.promptTokens = tokenizer.encode(text: prompt)
                }

                let results: [TranscriptionResult] = try await kit.transcribe(audioArray: audioForWhisper, decodeOptions: decodeOptions)
                return results.compactMap { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }.value

            guard !Task.isCancelled else { return }
            liveText = text
            onComplete?(text)
        } catch {
            guard !Task.isCancelled else { return }
            print("WhisperEngine: Transcription failed: \(error)")
            onComplete?("")
        }
    }

    private nonisolated static func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = targetSampleRate / sourceSampleRate
        let outputLength = Int(Double(samples.count) * ratio)
        guard outputLength > 0 else { return [] }
        var output = [Float](repeating: 0, count: outputLength)
        var control = (0..<outputLength).map { Float(Double($0) / ratio) }
        vDSP_vlint(samples, &control, 1, &output, 1, vDSP_Length(outputLength), vDSP_Length(samples.count))
        return output
    }
}
