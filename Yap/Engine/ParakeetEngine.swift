import Foundation
import AVFoundation
import Accelerate
import Observation
import FluidAudio

private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class ParakeetAudioBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "net.zainzafar.yap.parakeet.buffer")
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
final class ParakeetEngine: VoiceEngine {
    var isActive:    Bool   = false
    var signalLevel: Float  = 0.0
    var liveText:    String = ""
    var isRefining:  Bool   = false
    var deviceUID:   String? = nil
    var vocabulary:  [String] = []
    var onComplete:  ((String) -> Void)?

    private let pipeline     = AudioPipeline()
    private let catalog:     FluidCatalog
    private let audioBuffer  = ParakeetAudioBuffer()
    private var transcriptionTask: Task<Void, Never>?

    init(catalog: FluidCatalog) {
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
                let normalized = ParakeetEngine.normalizedLevel(from: chunk.monoSamples)
                Task { @MainActor [weak self] in
                    self?.signalLevel = normalized
                }
            }
            try pipeline.start(deviceUID: deviceUID)
            isActive = true
        } catch {
            print("ParakeetEngine: Failed to start: \(error)")
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
            await self?.transcribeAudio(capturedAudio, sampleRate: sampleRate)
        }
    }

    private func transcribeAudio(_ samples: [Float], sampleRate: Double) async {
        defer { isRefining = false }
        guard !Task.isCancelled else { return }
        do {
            try await catalog.loadParakeet()
            guard !Task.isCancelled else { return }
            guard let manager = catalog.parakeetManager else { onComplete?(""); return }

            let tempURL = try writeWAVFile(samples: samples, sampleRate: sampleRate)
            let wrappedManager = UnsafeSendable(manager)
            let text = try await Task.detached(priority: .userInitiated) {
                let m = wrappedManager.value
                defer { try? FileManager.default.removeItem(at: tempURL) }
                let result = try await m.transcribe(tempURL, source: .system)
                return result.text
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.value

            guard !Task.isCancelled else { return }
            liveText = text
            onComplete?(text)
        } catch {
            guard !Task.isCancelled else { return }
            print("ParakeetEngine: Transcription failed: \(error)")
            onComplete?("")
        }
    }

    private func writeWAVFile(samples: [Float], sampleRate: Double) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yap_parakeet_\(UUID().uuidString).wav")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CaptureError.emptyAudio
        }

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { src in
            channelData.update(from: src.baseAddress!, count: samples.count)
        }

        let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try file.write(from: buffer)

        return tempURL
    }
}

private enum CaptureError: Error {
    case emptyAudio
}
