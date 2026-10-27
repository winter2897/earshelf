import Foundation
import SwiftData
import UIKit
import WebKit

// radiotruyen.online mã hoá danh sách tập (AES) rồi giải mã bằng JS đã bị làm rối.
// Thay vì dò key, ta cho trang tự chạy trong WKWebView ẩn và chặn hàm jPlayerPlaylist
// để lấy danh sách [{title, mp3}] đã giải mã. Web có đổi key thì cách này vẫn chạy.

struct ScrapedBook {
    var title = "", author = "", narrator = "", genre = "", cover = ""
    var episodes: [(title: String, mp3: String)] = []
}

enum ScrapeError: LocalizedError {
    case badLink, timeout, empty
    var errorDescription: String? {
        switch self {
        case .badLink: "Link không hợp lệ — cần link truyện trên radiotruyen.online"
        case .timeout: "Trang tải quá lâu, thử lại nhé"
        case .empty: "Không tìm thấy danh sách tập trên trang này"
        }
    }
}

@MainActor
final class RadioTruyenScraper: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var cont: CheckedContinuation<ScrapedBook, Error>?
    private var result = ScrapedBook()

    func scrape(_ url: URL) async throws -> ScrapedBook {
        let config = WKWebViewConfiguration()
        let ucc = config.userContentController
        ucc.addUserScript(WKUserScript(source: Self.hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(self, name: "st")
        if let rules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "block", encodedContentRuleList: Self.blockRules) {
            ucc.add(rules)
        }
        config.mediaTypesRequiringUserActionForPlayback = .all
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: config)
        wv.navigationDelegate = self
        webView = wv
        wv.load(URLRequest(url: url))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(40))
            self?.finish(.failure(ScrapeError.timeout))
        }
        return try await withCheckedThrowingContinuation { cont = $0 }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let m = body["meta"] as? [String: String] {
            result.title = m["title"] ?? ""
            result.author = m["author"] ?? ""
            result.narrator = m["narrator"] ?? ""
            result.genre = m["genre"] ?? ""
            result.cover = m["cover"] ?? ""
        }
        if let list = body["playlist"] as? [[String: String]] {
            result.episodes = list.compactMap { e in e["mp3"].flatMap { $0.isEmpty ? nil : (e["title"] ?? "", $0) } }
            finish(result.episodes.isEmpty ? .failure(ScrapeError.empty) : .success(result))
        }
    }

    func webView(_ wv: WKWebView, didFail _: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    private func finish(_ r: Result<ScrapedBook, Error>) {
        guard let c = cont else { return }
        cont = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
        c.resume(with: r)
    }

    // Chạy trước mọi script của trang: thay jPlayerPlaylist bằng bản giả gửi danh sách về app,
    // tắt randomewave (thư viện dò devtools, nó xoá player nếu nghi ngờ).
    private static let hook = #"""
    (function(){
      function post(m){ window.webkit.messageHandlers.st.postMessage(m); }
      function PL(css, list){ post({playlist: (list||[]).map(function(i){ return {title: String(i.title||''), mp3: String(i.mp3||'')}; })}); }
      ['select','play','pause','next','previous','add','remove','shuffle','option'].forEach(function(k){ PL.prototype[k] = function(){}; });
      PL.prototype.setPlaylist = function(l){ PL(null, l); };
      Object.defineProperty(window, 'jPlayerPlaylist', {get: function(){ return PL; }, set: function(){}});
      var rw = {addListener: function(){}, launch: function(){}, stop: function(){}};
      Object.defineProperty(window, 'randomewave', {get: function(){ return rw; }, set: function(){}});
      document.addEventListener('DOMContentLoaded', function(){
        var ld = {};
        document.querySelectorAll('script[type="application/ld+json"]').forEach(function(s){
          try { var j = JSON.parse(s.textContent); if (j['@type'] === 'AudioBook') ld = j; } catch(e) {}
        });
        var h1 = document.querySelector('h1');
        var img = document.querySelector('#title-truyen img');
        var crumbs = document.querySelectorAll('.breadcrumb li a');
        var nar = (ld.description || '').match(/giọng đọc\s+(.+?)\s*$/);
        post({meta: {
          title: h1 ? h1.textContent.trim() : String(ld.name || ''),
          author: typeof ld.author === 'string' ? ld.author : String((ld.author && ld.author.name) || ''),
          narrator: nar ? nar[1] : '',
          genre: crumbs.length > 2 ? crumbs[crumbs.length - 1].textContent.trim().replace(/^Truyện\s+/i, '') : '',
          cover: (img && img.getAttribute('src')) || String(ld.image || '')
        }});
      });
    })();
    """#

    // Chặn quảng cáo/ảnh/font cho trang tải nhanh — ta chỉ cần HTML + JS.
    private static let blockRules = """
    [
      {"trigger":{"url-filter":".*","resource-type":["image","style-sheet","font","media"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"googlesyndication"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"googletagmanager"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"google-analytics"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"doubleclick"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"adtrafficquality"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"facebook"},"action":{"type":"block"}}
    ]
    """
}

@MainActor
enum Library {
    /// Lấy danh sách tập từ link. Truyện đã có thì chỉ thêm tập mới (truyện đang ra).
    static func importBook(from link: String, context: ModelContext) async throws -> Book {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.host?.contains("radiotruyen") == true, url.pathExtension == "html" else {
            throw ScrapeError.badLink
        }
        let key = url.absoluteString
        let existing = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.sourceURL == key })).first
        let s = try await RadioTruyenScraper().scrape(url)
        let slug = url.deletingPathExtension().lastPathComponent
        let book = existing ?? Book(sourceURL: key, slug: slug, title: s.title.isEmpty ? slug : s.title,
                                    author: s.author, narrator: s.narrator, genre: s.genre)
        if existing == nil { context.insert(book) }

        let have = Set(book.episodes.map(\.remoteURL))
        for (i, e) in s.episodes.enumerated() where !have.contains(e.mp3) {
            var title = e.title
            if title.hasPrefix(book.title + " - ") { title.removeFirst(book.title.count + 3) }
            book.episodes.append(Episode(index: i, title: title.isEmpty ? "Tập \(i + 1)" : title, remoteURL: e.mp3))
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: book.folder, withIntermediateDirectories: true)
        var folder = book.folder.deletingLastPathComponent()  // Books/ — không cho backup iCloud, vài GB mp3
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? folder.setResourceValues(rv)
        if UIImage(contentsOfFile: book.coverFile.path) == nil, let c = URL(string: s.cover),
           let (data, _) = try? await URLSession.shared.data(from: c), UIImage(data: data) != nil {
            try? data.write(to: book.coverFile)
        }
        book.hasCover = UIImage(contentsOfFile: book.coverFile.path) != nil
        try context.save()
        return book
    }

    static func delete(_ book: Book, context: ModelContext) {
        Downloader.shared.cancel(book)
        if Player.shared.book === book { Player.shared.close() }
        try? FileManager.default.removeItem(at: book.folder)
        context.delete(book)
        try? context.save()
    }
}
