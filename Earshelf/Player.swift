import AVFoundation
import MediaPlayer
import UIKit

@MainActor @Observable
final class Player {
    static let shared = Player()
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    static let sleepOptions = [10, 30, 60, 120]  // phút
    /// Nghe liên tục quá 2h15p kể từ lần chạm cuối (phát/dừng/tua/chuyển tập) thì tự dừng.
    static let maxContinuous: TimeInterval = 2 * 3600 + 15 * 60

    private(set) var book: Book?
    private(set) var isPlaying = false
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    private(set) var sleepAt: Date?
    private(set) var sleepAtEpisodeEnd = false
    private(set) var error: String?
    var isPresented = false
    var rate: Float = UserDefaults.standard.object(forKey: "rate") as? Float ?? 1 {
        didSet {
            UserDefaults.standard.set(rate, forKey: "rate")
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
            updateNowPlaying()
        }
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var stopAt: Date?
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var statusObs: NSKeyValueObservation?
    @ObservationIgnored private var itemObs: NSKeyValueObservation?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        player.defaultRate = rate
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        statusObs = player.observe(\.timeControlStatus) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, self.isPlaying != playing else { return }
                self.isPlaying = playing
                if !playing { self.save() }  // vd. bị cuộc gọi chen ngang
                self.updateNowPlaying()
            }
        }
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, (n.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.episodeEnded()
            }
        }
        setupRemoteCommands()
    }

    // MARK: thao tác của người dùng — đều tính lại mốc 2h15p

    func open(_ book: Book, play autoplay: Bool = true) {
        if self.book !== book {
            save()
            self.book = book
            load(book.currentIndex, at: book.currentTime)
        }
        if autoplay { play() }
    }

    func playEpisode(_ index: Int, of book: Book) {
        if self.book === book, index == book.currentIndex, player.currentItem != nil { play(); return }
        save()
        self.book = book
        load(index, at: index == book.currentIndex ? book.currentTime : 0)
        play()
    }

    func play() {
        guard book != nil else { return }
        touched()
        try? AVAudioSession.sharedInstance().setActive(true)
        player.volume = 1
        player.play()
        book?.lastPlayedAt = Date()
    }

    func pause() {
        touched()
        player.pause()
        save()
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to t: Double) {
        touched()
        time = t
        book?.currentTime = t
        if pendingSeek != nil { pendingSeek = t } else { player.seek(to: CMTime(seconds: t, preferredTimescale: 600)) }
        updateNowPlaying()
    }

    func skip(_ d: Double) { seek(to: max(0, duration > 0 ? min(time + d, duration - 1) : time + d)) }

    func next() { if let book, let i = neighbour(+1) { playEpisode(i, of: book) } }

    func previous() {
        if time > 5 { seek(to: 0) } else if let book, let i = neighbour(-1) { playEpisode(i, of: book) }
    }

    func setSleep(minutes: Int?) {
        sleepAt = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        sleepAtEpisodeEnd = false
        player.volume = 1
    }

    func setSleepAtEpisodeEnd() {
        sleepAt = nil
        sleepAtEpisodeEnd = true
    }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        book = nil
        isPresented = false
        updateNowPlaying()
    }

    func save() {
        guard let book else { return }
        if pendingSeek == nil { book.currentTime = time }
        try? book.modelContext?.save()
        lastSave = Date()
    }

    // MARK: nội bộ

    private func touched() { stopAt = Date().addingTimeInterval(Self.maxContinuous) }

    private func neighbour(_ step: Int) -> Int? {
        guard let book else { return nil }
        let idx = book.sorted.map(\.index)
        guard let pos = idx.firstIndex(of: book.currentIndex), idx.indices.contains(pos + step) else { return nil }
        return idx[pos + step]
    }

    private func load(_ index: Int, at t: Double) {
        guard let book, let ep = book.episodes.first(where: { $0.index == index }), let url = ep.playURL else { return }
        book.currentIndex = index
        book.currentTime = t
        time = t
        duration = 0
        error = nil
        let item = AVPlayerItem(url: url)
        let local = ep.isDownloaded
        pendingSeek = t > 0 ? t : nil
        itemObs = item.observe(\.status) { [weak self] item, _ in
            let status = item.status, d = item.duration.seconds
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                if status == .failed {
                    self.error = local ? "Không phát được file này" : "Không phát online được (mất mạng hoặc máy chủ truyện đang lỗi) — thử lại sau"
                    self.pendingSeek = nil
                    return
                }
                guard status == .readyToPlay else { return }
                if d.isFinite { self.duration = d }
                if let s = self.pendingSeek {
                    await self.player.seek(to: CMTime(seconds: s, preferredTimescale: 600))
                    self.pendingSeek = nil
                }
                self.updateNowPlaying()
            }
        }
        player.replaceCurrentItem(with: item)
        updateNowPlaying(artwork: true)
    }

    private func tick(_ t: Double) {
        guard pendingSeek == nil, let book else { return }
        time = t
        book.currentTime = t
        let now = Date()
        defer { lastTick = isPlaying ? now : nil }
        guard isPlaying else { return }
        if let last = lastTick { UserDefaults.standard.set(Self.listenedSeconds + min(now.timeIntervalSince(last), 2), forKey: "listened") }

        if let deadline = [sleepAt, stopAt].compactMap({ $0 }).min() {
            let left = deadline.timeIntervalSince(now)
            if left <= 0 { stop(); return }
            player.volume = left < 10 ? Float(left / 10) : 1  // nhỏ dần 10s cuối cho đỡ giật mình
        }
        if now.timeIntervalSince(lastSave) > 5 { save() }
    }

    static var listenedSeconds: Double { UserDefaults.standard.double(forKey: "listened") }

    /// Dừng do hẹn giờ / quá 2h15p — không tính là người dùng chạm.
    private func stop() {
        player.pause()
        player.volume = 1
        sleepAt = nil
        sleepAtEpisodeEnd = false
        save()
    }

    private func episodeEnded() {
        guard let i = neighbour(+1) else { save(); return }  // hết truyện
        load(i, at: 0)
        if sleepAtEpisodeEnd { sleepAtEpisodeEnd = false; save() } else { player.play() }
    }

    private func updateNowPlaying(artwork: Bool = false) {
        let center = MPNowPlayingInfoCenter.default()
        guard let book, let ep = book.current else { center.nowPlayingInfo = nil; return }
        var info = center.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = ep.title
        info[MPMediaItemPropertyAlbumTitle] = book.title
        info[MPMediaItemPropertyArtist] = book.byline
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
        if artwork {
            if let img = UIImage(contentsOfFile: book.coverFile.path) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            } else {
                info[MPMediaItemPropertyArtwork] = nil
            }
        }
        center.nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        func on(_ cmd: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
            cmd.isEnabled = true
            cmd.addTarget { e in MainActor.assumeIsolated { action(e) }; return .success }
        }
        on(c.playCommand) { [weak self] _ in self?.play() }
        on(c.pauseCommand) { [weak self] _ in self?.pause() }
        on(c.togglePlayPauseCommand) { [weak self] _ in self?.toggle() }
        c.skipBackwardCommand.preferredIntervals = [5]
        c.skipForwardCommand.preferredIntervals = [10]
        on(c.skipBackwardCommand) { [weak self] _ in self?.skip(-5) }
        on(c.skipForwardCommand) { [weak self] _ in self?.skip(10) }
        on(c.changePlaybackPositionCommand) { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
        }
    }
}
