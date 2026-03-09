import AVFoundation

struct AudioDevice: Identifiable, Equatable {
    let uid: String
    let name: String

    var id: String { uid }

    static func all() -> [AudioDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
        .map { AudioDevice(uid: $0.uniqueID, name: $0.localizedName) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isValid(uid: String) -> Bool {
        all().contains { $0.uid == uid }
    }
}
