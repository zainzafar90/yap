import Foundation
import Observation

@Observable @MainActor
final class WordBank {
    private(set) var words: [String] = []

    private let queue: DiskQueue<[String]>

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("net.zainzafar.yap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_words.json")
    }

    init() {
        queue = DiskQueue(url: Self.fileURL)
        loadFromDisk()
    }

    var asPromptString: String {
        words.joined(separator: ", ")
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let alreadyExists = words.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        guard !alreadyExists else { return }
        words.append(trimmed)
        persist()
    }

    func remove(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        persist()
    }

    func remove(_ word: String) {
        words.removeAll { $0.localizedCaseInsensitiveCompare(word) == .orderedSame }
        persist()
    }

    func removeAll() {
        words.removeAll()
        persist()
    }

    private func persist() {
        let snapshot = words
        Task { await queue.enqueue(snapshot) }
    }

    private func loadFromDisk() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            words = try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("WordBank: failed to load: \(error)")
            words = []
        }
    }
}
