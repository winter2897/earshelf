import SwiftUI

struct PlayerView: View {
    @State private var showEpisodes = false
    @State private var scrub: Double?
    @State private var showCustomSleep = false
    private let p = Player.shared

    var body: some View {
        if let book = p.book {
            VStack(spacing: 0) {
                HStack {
                    CircleIcon(systemName: "chevron.down") { p.isPresented = false }
                    Spacer()
                    CircleIcon(systemName: "list.bullet") { showEpisodes = true }
                }
                Cover(book: book, corner: 30)
                    .padding(.top, 24)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                VStack(spacing: 6) {
                    Text(book.current?.title ?? "").font(.system(.title3, design: .rounded, weight: .semibold)).lineLimit(1)
                    Text("\(book.title) · \(book.byline)").font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.top, 24)
                Spacer(minLength: 16)
                progress
                if let e = p.error { Text(e).font(.caption).foregroundStyle(.red).padding(.top, 6) }
                Spacer(minLength: 16)
                controls
                Spacer(minLength: 16)
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(CoverBackdrop(book: book))
            .sheet(isPresented: $showEpisodes) { NavigationStack { BookView(book: book) } }
            .onChange(of: book.currentIndex) { showEpisodes = false }
            .sheet(isPresented: $showCustomSleep) { CustomSleepSheet() }
        } else {
            AppBackground().onAppear { p.isPresented = false }
        }
    }

    private var progress: some View {
        let fraction = p.duration > 0 ? (scrub ?? p.time / p.duration) : 0
        return VStack(spacing: 10) {
            Waveform(progress: fraction)
                .frame(height: 48)
                .overlay {
                    GeometryReader { g in
                        Color.clear.contentShape(Rectangle()).gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { scrub = min(max($0.location.x / g.size.width, 0), 1) }
                                .onEnded { _ in
                                    if let s = scrub, p.duration > 0 { p.seek(to: s * p.duration) }
                                    scrub = nil
                                })
                    }
                }
            HStack {
                Text(formatTime(fraction * p.duration))
                Spacer()
                Text(formatTime(p.duration))
            }
            .font(.system(.footnote, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack {
            control("backward.end", 22) { p.previous() }
            Spacer()
            control("gobackward.5", 24) { p.skip(-5) }
            Spacer()
            Button { p.toggle() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28)).foregroundStyle(.primary)
                    .frame(width: 76, height: 76)
                    .background(Color.card, in: Circle())
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            Spacer()
            control("goforward.10", 24) { p.skip(10) }
            Spacer()
            control("forward.end", 22) { p.next() }
        }
    }

    private func control(_ icon: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .regular)).foregroundStyle(.primary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Tắt hẹn giờ") { p.setSleep(minutes: nil) }
                ForEach(Player.sleepOptions, id: \.self) { m in
                    Button(m < 60 ? "\(m) phút" : "\(m / 60) giờ") { p.setSleep(minutes: m) }
                }
                Button("Hết tập này") { p.setSleepAtEpisodeEnd() }
                Button("Tuỳ chỉnh…") { showCustomSleep = true }
            } label: {
                let on = p.sleepAt != nil || p.sleepAtEpisodeEnd
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                    if let s = p.sleepAt, s > .now {
                        Text(timerInterval: Date.now...s, countsDown: true).monospacedDigit()
                    } else {
                        Text(p.sleepAtEpisodeEnd ? "Hết tập" : "Hẹn giờ")
                    }
                }
                .inkCapsule(filled: on)
            }
            Spacer()
            Button {
                let i = Player.speeds.firstIndex(of: p.rate) ?? 1
                p.rate = Player.speeds[(i + 1) % Player.speeds.count]
            } label: {
                Text("\(p.rate.formatted())x tốc độ").inkCapsule(filled: false)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Sóng âm trang trí (không phân tích audio thật) — phần đã nghe tô màu.
struct Waveform: View {
    var progress: Double
    var body: some View {
        Canvas { ctx, size in
            let n = 56
            let step = size.width / CGFloat(n)
            for i in 0..<n {
                let h = (0.25 + 0.75 * abs(sin(Double(i) * 1.7) * cos(Double(i) * 0.43))) * size.height
                let rect = CGRect(x: CGFloat(i) * step + step * 0.3, y: (size.height - h) / 2, width: step * 0.4, height: h)
                let played = Double(i) / Double(n) < progress
                ctx.fill(Path(roundedRect: rect, cornerRadius: step * 0.2), with: .color(played ? .brand : .track))
            }
        }
    }
}

struct MiniPlayer: View {
    private let p = Player.shared
    var body: some View {
        if let book = p.book, !p.isPresented {
            HStack(spacing: 12) {
                Cover(book: book, corner: 12).frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).lineLimit(1)
                    Text(book.current?.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { p.toggle() } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20)).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.brand, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(8).padding(.leading, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.4)))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .padding(.horizontal, 16)
            .contentShape(Capsule())
            .onTapGesture { p.isPresented = true }
        }
    }
}

/// Hẹn giờ tuỳ chỉnh: chọn giờ + phút, nhớ lựa chọn lần trước.
private struct CustomSleepSheet: View {
    @AppStorage("customSleepHours") private var hours = 0
    @AppStorage("customSleepMinutes") private var minutes = 45
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Hẹn giờ tắt").font(.system(.title3, design: .rounded, weight: .bold))
            HStack(spacing: 0) {
                Picker("Giờ", selection: $hours) { ForEach(0..<6) { Text("\($0) giờ").tag($0) } }
                Picker("Phút", selection: $minutes) { ForEach(0..<60) { Text("\($0) phút").tag($0) } }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)
            Button {
                Player.shared.setSleep(minutes: hours * 60 + minutes)
                dismiss()
            } label: {
                Text("Bắt đầu").frame(maxWidth: .infinity).inkCapsule()
            }
            .buttonStyle(.plain)
            .disabled(hours * 60 + minutes == 0)
            .opacity(hours * 60 + minutes == 0 ? 0.4 : 1)
        }
        .padding(24)
        .presentationDetents([.height(340)])
        .presentationBackground(Color.bgTop)
    }
}
