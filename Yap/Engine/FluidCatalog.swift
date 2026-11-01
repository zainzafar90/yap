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
    /// Identifies the current `fetch()` so progress callbacks from a cancelled
    /// earlier run can't overwrite the state of a newer one.
    private var fetchRun = 0

    init() {
        probe()
        if case .absent = status,
           Self.canCompleteLegacyInstall(at: AsrModels.defaultCacheDirectory(for: .v3)) {
            Task { await fetch() }
        }
    }

    var isManagerLoaded: Bool { manager != nil }

    func probe() {
        let exists = AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        status = exists ? .live : .absent
        if exists { refreshStorageLabel() } else { storageLabel = "" }
    }

    func fetch() async {
        guard case .absent = status else { return }
        fetchRun += 1
        let run = fetchRun
        status = .fetching(0)

        let task = Task {
            do {
                try await AsrModels.download(version: .v3, progressHandler: { [weak self] p in
                    let isCompiling: Bool
                    if case .compiling = p.phase { isCompiling = true } else { isCompiling = false }
                    let next = Self.displayProgress(fraction: p.fractionCompleted, isCompiling: isCompiling)
                    Task { @MainActor [weak self] in
                        guard let self, self.fetchRun == run, case .fetching(let current) = self.status else { return }
                        self.status = .fetching(Self.merge(current: current, next: next))
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

    /// FluidAudio reports one 0–1 fraction per `loadModels` pass: 0–0.5 is the
    /// download, 0.5–1 is CoreML compilation. `AsrModels.download` runs several
    /// passes back to back, so the raw fraction jumps 100% → 50% repeatedly.
    /// Map it to what the user cares about instead: download bytes as 0–1,
    /// then an indeterminate "preparing" state (-1) once compilation starts.
    nonisolated static func displayProgress(fraction: Double, isCompiling: Bool) -> Double {
        isCompiling ? -1 : min(1, max(0, fraction / 0.5))
    }

    /// Never let the bar move backwards (callbacks can arrive out of order, and
    /// later passes re-report the download phase), and once preparing, stay there.
    nonisolated static func merge(current: Double, next: Double) -> Double {
        if current < 0 || next < 0 { return -1 }
        return max(current, next)
    }

    /// Files every compiled CoreML model folder in the Parakeet v3 repo contains.
    /// FluidAudio moves each file into place only once fully downloaded, so a
    /// folder holding all of them is complete.
    nonisolated static let modelFolderFiles = [
        "analytics/coremldata.bin", "coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin",
    ]

    /// Installs made before FluidAudio 0.16 lack `JointDecisionv3.mlmodelc` (~13 MB),
    /// which v3 now requires. Returns true only when everything else is already
    /// complete, so completing the install can never turn into a full ~600 MB
    /// download (e.g. after an interrupted first download).
    nonisolated static func canCompleteLegacyInstall(
        at dir: URL, fileManager: FileManager = .default
    ) -> Bool {
        func folderComplete(_ name: String) -> Bool {
            modelFolderFiles.allSatisfy {
                fileManager.fileExists(atPath: dir.appendingPathComponent(name).appendingPathComponent($0).path)
            }
        }
        let existing = ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc"]
        return fileManager.fileExists(atPath: dir.appendingPathComponent("parakeet_vocab.json").path)
            && existing.allSatisfy(folderComplete)
            && !folderComplete("JointDecisionv3.mlmodelc")
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
        // Loading while a download is still writing files would fail and mark
        // the engine broken; wait for the download instead.
        if let download = fetchTask {
            await download.value
            guard case .live = status else { throw FluidError.managerUnavailable }
        }
        if let existing = initTask {
            try await existing.value
            if let m = manager { return m }
        }

        let task = Task<Void, any Error> {
            let dir = AsrModels.defaultCacheDirectory(for: .v3)
            let models = try await AsrModels.load(from: dir, version: .v3)
            let m = AsrManager(config: .default)
            try await m.loadModels(models)
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
