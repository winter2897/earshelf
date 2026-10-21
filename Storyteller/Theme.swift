import SwiftUI

private func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
}

extension Color {
    static let brand = Color(red: 0.49, green: 0.23, blue: 0.93)
    static let card = dyn(0xFFFFFF, 0x1E1D27)
    static let ink = dyn(0x121216, 0xF4F2FA)        // nền nút chính (đen ở light, trắng ở dark)
    static let onInk = dyn(0xFFFFFF, 0x121216)
    static let bgTop = dyn(0xEEE9FB, 0x1B1729)
    static let bgBottom = dyn(0xFAF9FD, 0x0E0E12)
    static let track = dyn(0xD9D6E0, 0x3A3846)
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [.bgTop, .bgBottom, .bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

struct CircleIcon: View {
    let systemName: String
    var size: CGFloat = 52
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(Color.card, in: Circle())
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct InkCapsule: ViewModifier {
    var filled = true
    func body(content: Content) -> some View {
        content
            .font(.system(.body, design: .rounded, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(filled ? Color.onInk : Color.primary)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(filled ? Color.ink : Color.card, in: Capsule())
            .overlay(Capsule().stroke(Color.track.opacity(filled ? 0 : 0.6)))
    }
}

extension View {
    /// Dải mờ dưới thanh trạng thái để nội dung cuộn không đè lên giờ/pin.
    func statusBarBlur() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(.ultraThinMaterial) }
    }

    func inkCapsule(filled: Bool = true) -> some View { modifier(InkCapsule(filled: filled)) }
}

/// Ảnh bìa đọc từ file trong máy, có cache vì màn trình phát vẽ lại mỗi giây.
struct Cover: View {
    let book: Book
    var corner: CGFloat = 20
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                let _ = book.hasCover  // đọc để view tự vẽ lại khi bìa vừa tải xong
                if let img = Self.image(for: book) {
                    // Bìa trên web là ảnh dọc: nền là chính ảnh phóng to + làm mờ, poster đầy đủ nằm giữa.
                    // overlay (không dùng ZStack) để ảnh scaledToFill không làm giãn khung
                    Color.clear
                        .overlay {
                            Image(uiImage: img).resizable().scaledToFill()
                                .blur(radius: corner * 1.2, opaque: true)
                                .overlay(Color.black.opacity(0.08))
                        }
                        .overlay {
                            Image(uiImage: img).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: corner * 0.45, style: .continuous))
                                .shadow(color: .black.opacity(0.35), radius: corner * 0.6, y: corner * 0.3)
                                .padding(corner * 0.7)
                        }
                } else {
                    LinearGradient(colors: [.brand.opacity(0.85), .brand.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text(book.title).font(.system(.title3, design: .serif, weight: .bold)).foregroundStyle(.white)
                            .multilineTextAlignment(.center).minimumScaleFactor(0.4).padding(8))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Ảnh nền scaledToFill tràn khỏi khung: clipShape chỉ cắt hình, không cắt vùng chạm → chặn để không che nút xung quanh.
            .allowsHitTesting(false)
    }

    static func image(for book: Book) -> UIImage? {
        let key = book.coverFile.path as NSString
        if let img = cache.object(forKey: key) { return img }
        guard let img = UIImage(contentsOfFile: book.coverFile.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

/// Nền màn trình phát: ảnh bìa phóng to, mờ, tan dần xuống nền app.
struct CoverBackdrop: View {
    let book: Book
    var body: some View {
        ZStack {
            AppBackground()
            if let img = Cover.image(for: book) {
                GeometryReader { g in
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height * 0.75)
                        .clipped()
                        .blur(radius: 60)
                        .opacity(0.55)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea()
            }
        }
    }
}

extension Int64 {
    var bytesText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
