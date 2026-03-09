import Foundation
import Observation

@Observable @MainActor
final class OverlayDriver {
    var isActive:    Bool    = false
    var signalLevel: Float   = 0
    var liveText:    String  = ""
    var isRefining:  Bool    = false
    var isVisible:   Bool    = false

    var onStop:   (() -> Void)?
    var onCancel: (() -> Void)?

    private var syncTask: Task<Void, Never>?

    func attach(to engine: any VoiceEngine) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.isActive    = engine.isActive
                self.signalLevel = engine.signalLevel
                self.liveText    = engine.liveText
                self.isRefining  = engine.isRefining
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func reset() {
        syncTask?.cancel()
        syncTask    = nil
        isActive    = false
        signalLevel = 0
        liveText    = ""
        isRefining  = false
        isVisible   = false
        onStop      = nil
        onCancel    = nil
    }
}
