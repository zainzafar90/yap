import Foundation
import FluidAudio
import Observation

@Observable @MainActor
final class FluidCatalog {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
    }

    var parakeetState: ModelState = .notDownloaded
    var parakeetDiskLabel: String = ""

    private(set) var parakeetManager: AsrManager?

    private var parakeetLoadTask:     Task<Void, any Error>?
    private var parakeetDownloadTask: Task<Void, Never>?

    init() {
        checkExisting()
    }

    var isParakeetLoaded: Bool {
        if case .ready = parakeetState { return true }
        return false
    }

    func checkExisting() {
        let parakeetDir = AsrModels.defaultCacheDirectory(for: .v3)
        if AsrModels.modelsExist(at: parakeetDir, version: .v3) {
            parakeetState = .downloaded
            refreshParakeetDiskLabel()
        } else {
            parakeetState = .notDownloaded
            parakeetDiskLabel = ""
        }
    }

    func downloadParakeet() async {
        guard case .notDownloaded = parakeetState else { return }
        parakeetState = .downloading(progress: -1)

        let task = Task {
            do {
                try await AsrModels.download(version: .v3)
                guard !Task.isCancelled else { return }
                parakeetState = .downloaded
                refreshParakeetDiskLabel()
            } catch {
                guard !Task.isCancelled else { return }
                parakeetState = .error("Download failed: \(error.localizedDescription)")
            }
        }
        parakeetDownloadTask = task
        await task.value
        parakeetDownloadTask = nil
    }

    func cancelParakeetDownload() {
        parakeetDownloadTask?.cancel()
        parakeetDownloadTask = nil
        try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: .v3))
        parakeetState = .notDownloaded
        parakeetDiskLabel = ""
    }

    func loadParakeet() async throws {
        if parakeetManager != nil { parakeetState = .ready; return }

        if let existing = parakeetLoadTask {
            try await existing.value
            return
        }

        parakeetState = .loading

        let task = Task<Void, any Error> {
            let dir = AsrModels.defaultCacheDirectory(for: .v3)
            let models = try await AsrModels.load(from: dir, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            await MainActor.run { self.parakeetManager = manager }
        }
        parakeetLoadTask = task

        do {
            try await task.value
            parakeetLoadTask = nil
            parakeetState = .ready
            refreshParakeetDiskLabel()
        } catch {
            parakeetLoadTask = nil
            throw error
        }
    }

    func unloadParakeet() {
        parakeetLoadTask?.cancel()
        parakeetLoadTask = nil
        parakeetManager = nil
        switch parakeetState {
        case .ready, .loading: parakeetState = .downloaded
        default: break
        }
    }

    func deleteParakeet() {
        parakeetManager = nil
        try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: .v3))
        parakeetState = .notDownloaded
        parakeetDiskLabel = ""
    }

    func refreshParakeetDiskLabel() {
        let dir = AsrModels.defaultCacheDirectory(for: .v3)
        Task.detached(priority: .utility) {
            let label = Self.diskLabel(for: dir)
            await MainActor.run { self.parakeetDiskLabel = label }
        }
    }

    private nonisolated static func diskLabel(for dir: URL) -> String {
        guard let size = try? FileManager.default.allocatedSizeOfDirectory(at: dir), size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}
