import SwiftUI
import AppKit

struct AboutPane: View {
    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "v\(version) (\(build))"
    }()

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 4) {
                Text("Yap")
                    .font(.title2.bold())

                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Built for people who think faster than they type.")
                .font(.body)
                .foregroundStyle(.tertiary)

            Link("by @zainzafar90", destination: URL(string: "https://github.com/zainzafar90")!)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
