import Foundation
import FluidAudio
import Observation

private enum FluidError: Error {
    case managerUnavailable
}

@Observable @MainActor
final class FluidCatalog {
    enum FluidStatus: Equatable {
        case absent
        case fetching(Double)
        case live
        case broken(String)
    }

    var status: FluidStatus = .absent
    var storageLabel: String = ""

    private(set) var manager: AsrManager?

    private var initTask:  Task<Void, any Error>?
    private var fetchTask: Task<Void, Never>?

    init() {
        probe()
    }

    var isManagerLoaded: Bool { manager != nil }

    func probe() {
        let exists = AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        status = exists ? .live : .absent
        if exists { refreshStorageLabel() } else { storageLabel = "" }
    }

    func fetch() async {
        guard case .absent = status else { return }
        status = .fetching(0)

        let task = Task {
            do {
                try await AsrModels.download(version: .v3, progressHandler: { [weak self] p in
                    Task { @MainActor [weak self] in
                        guard case .fetching = self?.status else { return }
                        self?.status = .fetching(p.fractionCompleted)
                    }
                })
                guard !Task.isCancelled else { return }
                status = .live
                refreshStorageLabel()
            } catch {
                guard !Task.isCancelled else { return }
                status = .broken("Download failed: \(error.localizedDescription)")
            }
        }
        fetchTask = task
        await task.value
        fetchTask = nil
    }

    func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: .v3))
        status = .absent
        storageLabel = ""
    }

    func resolveManager() async throws -> AsrManager {
        if let existing = manager { return existing }
        if let existing = initTask {
            try await existing.value
            if let m = manager { return m }
        }

        let task = Task<Void, any Error> {
            let dir = AsrModels.defaultCacheDirectory(for: .v3)
            let models = try await AsrModels.load(from: dir, version: .v3)
            let m = AsrManager(config: .default)
            try await m.initialize(models: models)
            await MainActor.run { self.manager = m }
        }
        initTask = task

        do {
            try await task.value
            initTask = nil
            status = .live
            refreshStorageLabel()
            guard let m = manager else { throw FluidError.managerUnavailable }
            return m
        } catch {
            initTask = nil
            status = .broken(error.localizedDescription)
            throw error
        }
    }

    func remove() {
        manager = nil
        try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: .v3))
        status = .absent
        storageLabel = ""
    }

    func refreshStorageLabel() {
        let dir = AsrModels.defaultCacheDirectory(for: .v3)
        Task.detached(priority: .utility) {
            let bytes = (try? FileManager.default.allocatedSizeOfDirectory(at: dir)) ?? 0
            let label = bytes > 0 ? Self.formatByteCount(bytes) : ""
            await MainActor.run { self.storageLabel = label }
        }
    }

    private nonisolated static func formatByteCount(_ bytes: UInt64) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: Int64(bytes))
    }
}
