import Foundation
import Accelerate

@MainActor
protocol VoiceEngine: AnyObject {
    var isActive:    Bool              { get }
    var signalLevel: Float             { get }
    var liveText:    String            { get }
    var isRefining:  Bool              { get }
    var deviceUID:   String?           { get set }
    var vocabulary:  [String]          { get set }
    var onComplete:  ((String) -> Void)? { get set }

    func requestAccess() async
    func beginCapture()
    func endCapture()
}

extension VoiceEngine {
    static func normalizedLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return min(rms * 20, 1.0)
    }
}
