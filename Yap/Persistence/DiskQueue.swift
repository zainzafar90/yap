import Foundation

actor DiskQueue<T: Encodable> {
    private let url: URL
    private var pendingTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    /// Schedules a write. Cancels any pending write and waits 150ms before
    /// committing, so rapid successive calls collapse into a single write.
    func enqueue(_ value: T) {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self.write(value)
        }
    }

    private func write(_ value: T) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("DiskQueue: write failed for \(url.lastPathComponent): \(error)")
        }
    }
}
