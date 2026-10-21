import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]
    @State private var genre: String?
    @State private var showAdd = false
    @State private var path: [Book] = []

    private var listening: [Book] {
        books.filter { $0.lastPlayedAt != nil }.sorted { $0.lastPlayedAt! > $1.lastPlayedAt! }
    }
    private var genres: [String] { Array(Set(books.map(\.genre).filter { !$0.isEmpty })).sorted() }
    private var shown: [Book] { genre.map { g in books.filter { $0.genre == g } } ?? books }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    title
                    if !genres.isEmpty { chips }
                    if !listening.isEmpty {
                        section("Đang nghe dở")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) { ForEach(listening) { ContinueCard(book: $0) } }
                                .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                        .scrollTargetBehavior(.viewAligned)
                    }
                    section("Thư viện")
                    if books.isEmpty { empty }
                    LazyVStack(spacing: 12) {
                        ForEach(shown) { b in NavigationLink(value: b) { BookRow(book: b) }.buttonStyle(.plain) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .statusBarBlur()
            .background(AppBackground())
            .navigationDestination(for: Book.self) { BookView(book: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { AddLinkSheet { path.append($0) } }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(listenedText, systemImage: "headphones")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary, Color.brand)
                .padding(.horizontal, 18).frame(height: 52)
                .background(Color.card, in: Capsule())
            Spacer()
            CircleIcon(systemName: "plus") { showAdd = true }
        }
        .padding(.top, 8)
    }

    private var listenedText: String {
        let m = Int(Player.listenedSeconds / 60)
        return m < 60 ? "\(m) phút" : "\(m / 60) giờ"
    }

    private var title: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Hôm nay\nnghe gì nhỉ?")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white, LinearGradient(colors: [.brand, .purple], startPoint: .top, endPoint: .bottom))
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("Tất cả", selected: genre == nil) { genre = nil }
                ForEach(genres, id: \.self) { g in chip(g.capitalized, selected: genre == g) { genre = g } }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(selected ? Color.onInk : .primary)
                .padding(.horizontal, 18).frame(height: 44)
                .background(selected ? Color.ink : Color.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.system(.title3, design: .rounded, weight: .semibold))
    }

    private var empty: some View {
        Button { showAdd = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "link.badge.plus").font(.system(size: 36)).foregroundStyle(Color.brand)
                Text("Dán link truyện từ radiotruyen.online để bắt đầu").multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(32)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ContinueCard: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Cover(book: book, corner: 24)
            HStack(alignment: .firstTextBaseline) {
                Text(book.title).font(.system(.title3, design: .rounded, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(book.byline).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 10) {
                Label("\(book.current?.title ?? "")", systemImage: "clock")
                    .lineLimit(1).frame(maxWidth: .infinity).inkCapsule(filled: false)
                Button {
                    Player.shared.open(book)
                    Player.shared.isPresented = true
                } label: {
                    Label("Nghe tiếp", systemImage: "play").frame(maxWidth: .infinity).inkCapsule()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

private struct BookRow: View {
    let book: Book
    var body: some View {
        let dl = Downloader.shared
        let active = book.episodes.filter { dl.progress[$0.remoteURL] != nil }.count
        HStack(spacing: 14) {
            Cover(book: book, corner: 14).frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.system(.headline, design: .rounded)).lineLimit(1)
                Text([book.author, book.narrator].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(active > 0 ? "Đang tải · còn \(active) tập" : "Đã tải \(book.downloadedCount)/\(book.episodes.count) tập")
                    .font(.caption).foregroundStyle(active > 0 ? Color.brand : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AddLinkSheet: View {
    var onDone: (Book) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Thêm truyện").font(.system(.title2, design: .rounded, weight: .bold))
            Text("Dán link truyện trên radiotruyen.online, app sẽ lấy danh sách tập để anh chọn tải.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("https://radiotruyen.online/…", text: $link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                PasteButton(payloadType: String.self) { link = $0.first ?? link }
                    .labelStyle(.iconOnly).buttonBorderShape(.capsule).tint(.brand)
            }
            .padding(.leading, 18).padding(.trailing, 6).frame(height: 56)
            .background(Color.card, in: Capsule())
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            Button { Task { await fetch() } } label: {
                Group { if loading { ProgressView().tint(.onInk) } else { Text("Lấy danh sách tập") } }
                    .frame(maxWidth: .infinity).inkCapsule()
            }
            .buttonStyle(.plain)
            .disabled(loading || link.isEmpty)
            Spacer()
        }
        .padding(24)
        .padding(.top, 8)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgTop)
    }

    private func fetch() async {
        loading = true
        error = nil
        do {
            let book = try await Library.importBook(from: link, context: context)
            dismiss()
            onDone(book)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
