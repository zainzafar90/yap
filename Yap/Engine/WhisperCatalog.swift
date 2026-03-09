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
        case .largev3turbo: return "large-v3_turbo"
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
    enum WhisperStatus: Equatable {
        case absent                   // not downloaded
        case fetching(Double)         // downloading, 0–1
        case live                     // on disk; kit lazily initialised
        case broken(String)           // error message
    }

    var status: WhisperStatus = .absent
    private(set) var storageLabel: String = ""

    var selectedVariant: WhisperModelVariant {
        didSet {
            guard oldValue != selectedVariant else { return }
            UserDefaults.standard.set(selectedVariant.rawValue, forKey: AppPreferenceKey.whisperModelVariant)
            kit = nil
            probe()
        }
    }

    static var storeRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("net.zainzafar.yap/WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var variantStore: URL {
        let dir = Self.storeRoot.appendingPathComponent(selectedVariant.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private(set) var fetchingVariant: WhisperModelVariant? = nil

    private var kit:      WhisperKit?
    private var initTask: Task<Void, any Error>?
    private var fetchTask: Task<Void, Never>?

    init() {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.whisperModelVariant)
        self.selectedVariant = WhisperModelVariant(rawValue: raw ?? "") ?? .tiny
        probe()
    }

    var isKitLoaded: Bool { kit != nil }

    func probe() {
        let fm    = FileManager.default
        let dir   = variantStore
        let found: Bool = {
            if let saved = UserDefaults.standard.string(forKey: storedPathKey), fm.fileExists(atPath: saved) { return true }
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            if entries.contains(where: { $0.hasDirectoryPath && $0.lastPathComponent.lowercased().contains("whisper") }) { return true }
            return fm.fileExists(atPath: dir.appendingPathComponent("huggingface").path)
        }()
        if found { status = .live; refreshStorageLabel() } else { status = .absent; storageLabel = "" }
    }

    func fetch() async {
        guard case .absent = status else { return }
        fetchingVariant = selectedVariant
        status = .fetching(0)

        let task = Task {
            do {
                let modelFolder = try await WhisperKit.download(
                    variant: selectedVariant.whisperKitVariant,
                    downloadBase: variantStore,
                    progressCallback: { @Sendable [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, !Task.isCancelled else { return }
                            self.status = .fetching(progress.fractionCompleted)
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(modelFolder.path, forKey: storedPathKey)
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
        fetchingVariant = nil
    }

    func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        fetchingVariant = nil
        try? FileManager.default.removeItem(at: variantStore)
        UserDefaults.standard.removeObject(forKey: storedPathKey)
        status = .absent
        storageLabel = ""
    }

    func resolveKit() async throws -> WhisperKit {
        if let existing = kit { return existing }
        if let existing = initTask {
            try await existing.value
            if let k = kit { return k }
        }

        let modelPath = UserDefaults.standard.string(forKey: storedPathKey)
        let variantName = selectedVariant.whisperKitVariant
        let variantDir = variantStore
        let task = Task<Void, any Error> { @MainActor [weak self] in
            guard let self else { return }
            let config = WhisperKitConfig(
                model: variantName,
                downloadBase: variantDir,
                modelFolder: modelPath,
                verbose: false, logLevel: .none,
                prewarm: true, load: true,
                download: modelPath == nil
            )
            self.kit = try await WhisperKit(config)
        }
        initTask = task
        do {
            try await task.value
            initTask = nil
            guard let k = kit else { throw WhisperCatalogError.kitUnavailable }
            status = .live
            refreshStorageLabel()
            return k
        } catch {
            initTask = nil
            status = .broken(error.localizedDescription)
            throw error
        }
    }

    func remove() {
        kit = nil
        try? FileManager.default.removeItem(at: variantStore)
        UserDefaults.standard.removeObject(forKey: storedPathKey)
        status = .absent
        storageLabel = ""
    }

    func refreshStorageLabel() {
        let dir = variantStore
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

    private var storedPathKey: String { "whisperModelPath_\(selectedVariant.rawValue)" }
}

private enum WhisperCatalogError: Error {
    case kitUnavailable
}


extension FileManager {
    nonisolated func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var tally: UInt64 = 0
        guard let seq = enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        for case let entry as URL in seq {
            let rv = try entry.resourceValues(forKeys: Set(keys))
            tally += UInt64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        return tally
    }
}
