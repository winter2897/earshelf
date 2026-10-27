import Foundation
import SwiftData

/// Tải mp3 bằng background URLSession: thoát app / khoá máy vẫn tải tiếp.
@MainActor @Observable
final class Downloader: NSObject {
    static let shared = Downloader()

    var progress: [String: Double] = [:]  // remoteURL -> 0...1; có key = đang chờ hoặc đang tải
    var failed: Set<String> = []
    @ObservationIgnored var context: ModelContext!
    @ObservationIgnored var backgroundCompletion: (() -> Void)?
    @ObservationIgnored private var session: URLSession!

    override init() {
        super.init()
        let c = URLSessionConfiguration.background(withIdentifier: "com.haiquan.earshelf.downloads")
        c.sessionSendsLaunchEvents = true
        c.isDiscretionary = false
        c.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: c, delegate: self, delegateQueue: .main)
    }

    /// Gọi lúc mở app: nhận lại các tập đang tải dở từ lần trước.
    func restore() {
        session.getAllTasks { tasks in
            let keys = tasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription)
            Task { @MainActor in for k in keys where self.progress[k] == nil { self.progress[k] = 0 } }
        }
    }

    func download(_ episodes: [Episode]) {
        for e in episodes.sorted(by: { $0.index < $1.index }) where !e.isDownloaded && progress[e.remoteURL] == nil {
            guard let url = e.remote else { continue }
            failed.remove(e.remoteURL)
            progress[e.remoteURL] = 0
            let t = session.downloadTask(with: url)
            t.taskDescription = e.remoteURL
            t.resume()
        }
    }

    func cancel(_ book: Book) {
        let keys = Set(book.episodes.map(\.remoteURL))
        session.getAllTasks { tasks in tasks.filter { keys.contains($0.taskDescription ?? "") }.forEach { $0.cancel() } }
    }

    func deleteFile(_ e: Episode) {
        if let f = e.fileURL { try? FileManager.default.removeItem(at: f) }
        e.isDownloaded = false
        try? context.save()
    }

    /// Ước lượng dung lượng = kích thước 1 tập × số tập (các tập cùng bộ thường dài ngang nhau).
    func estimateBytes(_ episodes: [Episode]) async -> Int64? {
        guard let url = episodes.first?.remote else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        guard let (_, resp) = try? await URLSession.shared.data(for: req), resp.expectedContentLength > 0 else { return nil }
        return resp.expectedContentLength * Int64(episodes.count)
    }

    static var freeBytes: Int64 {
        (try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func episode(_ remote: String) -> Episode? {
        try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.remoteURL == remote })).first
    }
}

extension Downloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64,
                                totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        guard let key = t.taskDescription, e > 0 else { return }
        let v = Double(w) / Double(e)
        MainActor.assumeIsolated {
            if let old = progress[key], v - old < 0.01 { return }  // đỡ vẽ lại UI liên tục
            progress[key] = v
        }
    }

    // Phải chuyển file ngay trong hàm này, trả về là hệ thống xoá file tạm.
    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        MainActor.assumeIsolated {
            guard let key = t.taskDescription, let ep = episode(key), let dest = ep.fileURL else { return }
            if let http = t.response as? HTTPURLResponse, http.statusCode != 200 { failed.insert(key); return }
            let fm = FileManager.default
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            do {
                try fm.moveItem(at: loc, to: dest)
                ep.isDownloaded = true
                try? context.save()
            } catch { failed.insert(key) }
        }
    }

    nonisolated func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let key = t.taskDescription else { return }
            progress[key] = nil
            if let error, (error as NSError).code != NSURLErrorCancelled { failed.insert(key) }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession s: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletion?()
            backgroundCompletion = nil
        }
    }
}
