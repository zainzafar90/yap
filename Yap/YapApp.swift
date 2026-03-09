import SwiftUI

@main
struct YapApp: App {
    @NSApplicationDelegateAdaptor(AppOrchestrator.self) var orchestrator

    var body: some Scene {
        Settings {
            SettingsRoot(
                whisperCatalog: orchestrator.whisperCatalog,
                fluidCatalog:   orchestrator.fluidCatalog,
                activityLog:    orchestrator.activityLog,
                wordBank:       orchestrator.wordBank
            )
            .frame(minWidth: 480, maxWidth: 520)
        }
    }
}
