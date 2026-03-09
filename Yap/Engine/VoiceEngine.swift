import Foundation

/// Implemented by all transcription engines. All conformers must be
/// @Observable @MainActor so the Overlay can observe their properties.
@MainActor
protocol VoiceEngine: AnyObject {
    /// True while audio is being captured
    var isActive: Bool { get }

    /// Normalized audio level 0.0–1.0 for waveform visualization
    var signalLevel: Float { get }

    /// Running transcription text (updates in real-time for streaming engines)
    var liveText: String { get }

    /// True while Apple Intelligence enhancement is running post-transcription
    var isRefining: Bool { get }

    /// UID of the microphone to use (nil = system default)
    var deviceUID: String? { get set }

    /// Custom vocabulary injected as hints to improve accuracy
    var vocabulary: [String] { get set }

    /// Called when transcription (and optional enhancement) is complete
    var onComplete: ((String) -> Void)? { get set }

    func requestAccess() async
    func beginCapture()
    func endCapture()
}

/// Shared audio level calculation used by all engines
extension VoiceEngine {
    static func normalizedLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        for s in samples { rms += s * s }
        return min(sqrt(rms / Float(samples.count)) * 20, 1.0)
    }
}
