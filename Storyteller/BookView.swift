import SwiftData
import SwiftUI

struct BookView: View {
    let book: Book
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selecting = false
    @State private var selected: Set<Int> = []
    @State private var estimate: Int64?
    @State private var refreshing = false
    @State private var confirmDelete = false
    @State private var confirmCleanup = false
    private let dl = Downloader.shared
    private let player = Player.shared

    private var episodes: [Episode] { book.sorted }
    private var selectedEpisodes: [Episode] { episodes.filter { selected.contains($0.index) } }
    /// Tập đã tải và nằm trước tập đang nghe = đã nghe xong.
    private var listenedFiles: [Episode] { episodes.filter { $0.isDownloaded && $0.index < book.currentIndex } }

    var body: some View {
        List {
            header.listRowSeparator(.hidden).listRowBackground(Color.clear)
            ForEach(episodes) { e in
                row(e)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.track.opacity(0.5))
                    .swipeActions {
                        if e.isDownloaded { Button("Xoá file", role: .destructive) { dl.deleteFile(e) } }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .statusBarBlur()
        .background(CoverBackdrop(book: book))
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .task(id: selected) {
            estimate = nil
            estimate = await dl.estimateBytes(selectedEpisodes)
        }
        .confirmationDialog(cleanupTitle, isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Xoá \(listenedFiles.count) tập", role: .destructive) { listenedFiles.forEach(dl.deleteFile) }
        }
        .confirmationDialog("Xoá truyện và toàn bộ file đã tải?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                dismiss()
                Task {  // đợi màn hình đóng hẳn rồi mới xoá, tránh view đọc model đã xoá
                    try? await Task.sleep(for: .milliseconds(500))
                    Library.delete(book, context: context)
                }
            }
        }
    }

    private var cleanupTitle: String {
        let bytes = listenedFiles.compactMap { $0.fileURL }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +)
        return "Xoá file \(listenedFiles.count) tập đã nghe xong, giải phóng \(Int64(bytes).bytesText)?"
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                CircleIcon(systemName: "arrow.left") { dismiss() }
                Spacer()
                Menu {
                    Button { Task { await refresh() } } label: { Label("Cập nhật tập mới", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { confirmCleanup = true } label: {
                        Label("Xoá các tập đã nghe xong", systemImage: "checkmark.circle.badge.xmark")
                    }
                    .disabled(listenedFiles.isEmpty)
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Xoá truyện", systemImage: "trash") }
                } label: {
                    Image(systemName: refreshing ? "hourglass" : "ellipsis")
                        .font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                        .frame(width: 52, height: 52).background(Color.card, in: Circle())
                }
            }
            Cover(book: book, corner: 26).frame(width: 190)
            VStack(spacing: 4) {
                Text(book.title).font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                Text([book.author, book.narrator].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            downloadStatus
            HStack(spacing: 10) {
                Button {
                    player.open(book)
                    player.isPresented = true
                } label: {
                    Label(book.lastPlayedAt == nil ? "Bắt đầu nghe" : "Nghe tiếp", systemImage: "play")
                        .frame(maxWidth: .infinity).inkCapsule()
                }
                Button {
                    withAnimation { selecting.toggle(); selected = [] }
                } label: {
                    Label(selecting ? "Xong" : "Chọn tập tải", systemImage: selecting ? "checkmark" : "arrow.down.circle")
                        .frame(maxWidth: .infinity).inkCapsule(filled: false)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var downloadStatus: some View {
        let total = episodes.count
        let done = book.downloadedCount
        let active = episodes.filter { dl.progress[$0.remoteURL] != nil }
        let current = active.first { (dl.progress[$0.remoteURL] ?? 0) > 0 } ?? active.first
        let partial = active.reduce(0) { $0 + (dl.progress[$1.remoteURL] ?? 0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Đã tải \(done)/\(total) tập").font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                if !active.isEmpty {
                    Button("Huỷ tải") { dl.cancel(book) }.font(.subheadline).tint(.red)
                }
            }
            ProgressView(value: total == 0 ? 0 : (Double(done) + partial) / Double(total)).tint(.brand)
            if let current {
                Text("Đang tải \(current.title) — \(Int((dl.progress[current.remoteURL] ?? 0) * 100))%" + (active.count > 1 ? " · còn \(active.count - 1) tập chờ" : ""))
                    .font(.caption).foregroundStyle(Color.brand)
            }
            let failed = episodes.filter { dl.failed.contains($0.remoteURL) }
            if !failed.isEmpty {
                Button("\(failed.count) tập lỗi — tải lại") { dl.download(failed) }.font(.caption).tint(.red)
            }
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: rows

    private func row(_ e: Episode) -> some View {
        let isCurrent = player.book === book && book.currentIndex == e.index
        let listened = e.index < book.currentIndex
        return HStack(spacing: 14) {
            if selecting {
                Image(systemName: selected.contains(e.index) ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(Color.brand)
                    .opacity(e.isDownloaded || dl.progress[e.remoteURL] != nil ? 0 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.system(.body, design: .rounded, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.brand : listened ? .secondary : .primary)
                if book.currentIndex == e.index, book.currentTime > 0 {
                    Text("Đang nghe dở · \(formatTime(book.currentTime))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            state(e)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                guard !e.isDownloaded else { return }
                if selected.contains(e.index) { selected.remove(e.index) } else { selected.insert(e.index) }
            } else {
                player.playEpisode(e.index, of: book)
                player.isPresented = true
            }
        }
    }

    @ViewBuilder private func state(_ e: Episode) -> some View {
        if e.isDownloaded {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
        } else if let p = dl.progress[e.remoteURL] {
            ZStack {
                Circle().stroke(Color.track, lineWidth: 3)
                Circle().trim(from: 0, to: p).stroke(Color.brand, style: .init(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(p * 100))").font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .frame(width: 26, height: 26)
        } else if dl.failed.contains(e.remoteURL) {
            Button { dl.download([e]) } label: { Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(.red) }
                .buttonStyle(.borderless)
        } else if !selecting {
            Button { dl.download([e]) } label: { Image(systemName: "arrow.down.circle").foregroundStyle(.secondary) }
                .buttonStyle(.borderless)
        }
    }

    // MARK: chọn tập tải

    private var selectionBar: some View {
        let free = Downloader.freeBytes
        let tooBig = (estimate ?? 0) > free
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                quick("10 tập tiếp") { nextUndownloaded(10) }
                quick("Tất cả") { Set(episodes.filter { !$0.isDownloaded }.map(\.index)) }
                quick("Bỏ chọn") { [] }
            }
            Text(tooBig ? "Không đủ chỗ: cần ≈\((estimate ?? 0).bytesText), máy còn \(free.bytesText)"
                 : "\(selected.count) tập\(estimate.map { " · ≈ \($0.bytesText)" } ?? "") · máy còn \(free.bytesText)")
                .font(.caption).foregroundStyle(tooBig ? .red : .secondary)
            Button {
                dl.download(selectedEpisodes)
                withAnimation { selecting = false; selected = [] }
            } label: {
                Label("Tải \(selected.count) tập", systemImage: "arrow.down").frame(maxWidth: .infinity).inkCapsule()
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || tooBig)
            .opacity(selected.isEmpty || tooBig ? 0.4 : 1)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func quick(_ title: String, _ pick: @escaping () -> Set<Int>) -> some View {
        Button(title) { selected = pick() }
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .padding(.horizontal, 14).frame(height: 36)
            .background(Color.card, in: Capsule())
            .buttonStyle(.plain)
    }

    /// N tập chưa tải kể từ tập đang nghe trở đi.
    private func nextUndownloaded(_ n: Int) -> Set<Int> {
        Set(episodes.filter { $0.index >= book.currentIndex && !$0.isDownloaded && dl.progress[$0.remoteURL] == nil }.prefix(n).map(\.index))
    }

    private func refresh() async {
        refreshing = true
        _ = try? await Library.importBook(from: book.sourceURL, context: context)
        refreshing = false
    }
}
