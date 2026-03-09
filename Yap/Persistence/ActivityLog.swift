import Foundation
import Observation

struct ActivityRecord: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let engine: String
    let wasEnhanced: Bool

    init(text: String, engine: TranscriptionEngine, wasEnhanced: Bool) {
        self.id          = UUID()
        self.text        = text
        self.timestamp   = Date()
        self.engine      = engine.rawValue
        self.wasEnhanced = wasEnhanced
    }
}

@Observable @MainActor
final class ActivityLog {
    private(set) var records: [ActivityRecord] = []

    private static let maxRecords = 50
    private let queue: DiskQueue<[ActivityRecord]>

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("net.zainzafar.yap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        queue = DiskQueue(url: Self.fileURL)
        loadFromDisk()
    }

    func append(_ record: ActivityRecord) {
        guard !record.text.isEmpty else { return }
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        persist()
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        records.removeAll()
        persist()
    }

    private func persist() {
        let snapshot = records
        Task { await queue.enqueue(snapshot) }
    }

    private func loadFromDisk() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            records = try JSONDecoder().decode([ActivityRecord].self, from: data)
        } catch {
            print("ActivityLog: failed to load: \(error)")
            records = []
        }
    }
}


extension Date {
    var relativeString: String {
        let now = Date()
        let diff = now.timeIntervalSince(self)

        if diff < 60 { return "Just now" }
        if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins) min ago"
        }
        if diff < 86400 {
            let hrs = Int(diff / 3600)
            return "\(hrs) hr ago"
        }
        if diff < 172_800 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
