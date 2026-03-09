import Foundation
import WhisperKit
import Observation


enum WhisperModelVariant: String, CaseIterable, Identifiable {
    case tiny, base, small, medium, largev3turbo
    var id: String { rawValue }

    var whisperKitVariant: String {
        switch self {
        case .tiny:        return "tiny"
        case .base:        return "base"
        case .small:       return "small"
        case .medium:      return "medium"
        case .largev3turbo: return "large-v3-turbo"
        }
    }

    var title: String {
        switch self {
        case .tiny:        return "Tiny"
        case .base:        return "Base"
        case .small:       return "Small"
        case .medium:      return "Medium"
        case .largev3turbo: return "Large v3 Turbo"
        }
    }

    var sizeDescription: String {
        switch self {
        case .tiny:        return "~80 MB"
        case .base:        return "~150 MB"
        case .small:       return "~500 MB"
        case .medium:      return "~1.5 GB"
        case .largev3turbo: return "~3.2 GB"
        }
    }

    var qualityDescription: String {
        switch self {
        case .tiny:        return "Fast and light. Good enough for quick notes."
        case .base:        return "The sweet spot — accurate without being slow."
        case .small:       return "Noticeably sharper. Worth the extra space."
        case .medium:      return "Strong accuracy across languages. Solid all-rounder."
        case .largev3turbo: return "Best Whisper gets — fast and accurate."
        }
    }
}


@Observable @MainActor
final class WhisperCatalog {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
    }

    var state: ModelState = .notDownloaded
    private(set) var diskSizeLabel: String = ""

    var selectedVariant: WhisperModelVariant {
        didSet {
            guard oldValue != selectedVariant else { return }
            UserDefaults.standard.set(selectedVariant.rawValue, forKey: AppPreferenceKey.whisperModelVariant)
            whisperKit = nil
            checkExistingModel()
        }
    }

    static var modelsRootDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("net.zainzafar.yap/WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var modelDirectory: URL {
        let dir = Self.modelsRootDirectory.appendingPathComponent(selectedVariant.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var whisperKit:   WhisperKit?
    private var loadTask:     Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    init() {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.whisperModelVariant)
        self.selectedVariant = WhisperModelVariant(rawValue: raw ?? "") ?? .tiny
        checkExistingModel()
    }

    var isLoaded: Bool {
        if case .ready = state { return true }
        return false
    }

    var loadedKit: WhisperKit? { whisperKit }

    func checkExistingModel() {
        let fm = FileManager.default

        if let storedPath = UserDefaults.standard.string(forKey: modelPathKey),
           fm.fileExists(atPath: storedPath) {
            state = .downloaded
            refreshDiskLabel()
            return
        }

        let modelDir = modelDirectory
        if let contents = try? fm.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil),
           contents.contains(where: { $0.hasDirectoryPath && $0.lastPathComponent.lowercased().contains("whisper") }) {
            state = .downloaded
            refreshDiskLabel()
        } else {
            let hubDir = modelDir.appendingPathComponent("huggingface")
            if fm.fileExists(atPath: hubDir.path) {
                state = .downloaded
                refreshDiskLabel()
            } else {
                state = .notDownloaded
                diskSizeLabel = ""
            }
        }
    }

    func downloadModel() async {
        guard case .notDownloaded = state else { return }
        state = .downloading(progress: 0)

        let task = Task {
            do {
                let modelFolder = try await WhisperKit.download(
                    variant: selectedVariant.whisperKitVariant,
                    downloadBase: modelDirectory,
                    progressCallback: { @Sendable [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, !Task.isCancelled else { return }
                            self.state = .downloading(progress: progress.fractionCompleted)
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(modelFolder.path, forKey: modelPathKey)
                state = .downloaded
                refreshDiskLabel()
            } catch {
                guard !Task.isCancelled else { return }
                state = .error("Download failed: \(error.localizedDescription)")
            }
        }
        downloadTask = task
        await task.value
        downloadTask = nil
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: modelDirectory)
        UserDefaults.standard.removeObject(forKey: modelPathKey)
        state = .notDownloaded
        diskSizeLabel = ""
    }

    func loadModel() async throws {
        if whisperKit != nil { return }

        if let existing = loadTask {
            await existing.value
            if whisperKit != nil { return }
        }

        state = .loading

        let modelPath: String? = UserDefaults.standard.string(forKey: modelPathKey)
        let variant = selectedVariant.whisperKitVariant
        let dir = modelDirectory

        var loadError: (any Error)?
        let task = Task<Void, Never> { [weak self] in
            do {
                let config = WhisperKitConfig(
                    model: variant,
                    downloadBase: dir,
                    modelFolder: modelPath,
                    verbose: false,
                    logLevel: .none,
                    prewarm: true,
                    load: true,
                    download: modelPath == nil
                )
                let kit = try await WhisperKit(config)
                await MainActor.run { self?.whisperKit = kit }
            } catch {
                await MainActor.run { loadError = error }
            }
        }
        loadTask = task
        await task.value
        loadTask = nil

        if let error = loadError { throw error }
        state = .ready
        refreshDiskLabel()
    }

    func deleteModel() {
        whisperKit = nil
        try? FileManager.default.removeItem(at: modelDirectory)
        UserDefaults.standard.removeObject(forKey: modelPathKey)
        state = .notDownloaded
        diskSizeLabel = ""
    }

    func unloadModelFromMemory() {
        loadTask?.cancel()
        loadTask = nil
        whisperKit = nil
        switch state {
        case .ready, .loading: state = .downloaded
        default: break
        }
    }

    func refreshDiskLabel() {
        let dir = modelDirectory
        Task.detached(priority: .utility) {
            let sizeString: String
            if let size = try? FileManager.default.allocatedSizeOfDirectory(at: dir), size > 0 {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB]
                formatter.countStyle = .file
                sizeString = formatter.string(fromByteCount: Int64(size))
            } else {
                sizeString = ""
            }
            await MainActor.run { [sizeString] in
                self.diskSizeLabel = sizeString
            }
        }
    }

    private var modelPathKey: String { "whisperModelPath_\(selectedVariant.rawValue)" }
}


extension FileManager {
    nonisolated func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var total: UInt64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let fileURL = enumerator?.nextObject() as? URL {
            let rv = try fileURL.resourceValues(forKeys: keys)
            total += UInt64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        return total
    }
}
