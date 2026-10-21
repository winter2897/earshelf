import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var sourceURL: String
    var slug: String
    var title: String
    var author: String
    var narrator: String
    var genre: String
    var hasCover = false
    var addedAt = Date()
    var lastPlayedAt: Date?
    var currentIndex = 0          // tập đang nghe
    var currentTime: Double = 0   // giây trong tập đang nghe
    @Relationship(deleteRule: .cascade, inverse: \Episode.book) var episodes: [Episode] = []

    init(sourceURL: String, slug: String, title: String, author: String, narrator: String, genre: String) {
        self.sourceURL = sourceURL
        self.slug = slug
        self.title = title
        self.author = author
        self.narrator = narrator
        self.genre = genre
    }

    var sorted: [Episode] { episodes.sorted { $0.index < $1.index } }
    var current: Episode? { episodes.first { $0.index == currentIndex } }
    var downloadedCount: Int { episodes.filter(\.isDownloaded).count }
    // Đường dẫn tính lại mỗi lần vì thư mục Documents đổi sau mỗi lần cài lại app.
    var folder: URL { URL.documentsDirectory.appending(path: "Books/\(slug)") }
    var coverFile: URL { folder.appending(path: "cover.jpg") }
    var byline: String { narrator.isEmpty ? author : narrator }
}

@Model
final class Episode {
    var index: Int
    var title: String
    var remoteURL: String
    var isDownloaded = false
    var book: Book?

    init(index: Int, title: String, remoteURL: String) {
        self.index = index
        self.title = title
        self.remoteURL = remoteURL
    }

    var fileURL: URL? { book.map { $0.folder.appending(path: "\(index).mp3") } }
    var remote: URL? {
        URL(string: remoteURL) ?? remoteURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }
    // ponytail: tập chưa tải thì phát online, đỡ phải làm luồng riêng cho chế độ stream
    var playURL: URL? { isDownloaded ? fileURL : remote }
}

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}
