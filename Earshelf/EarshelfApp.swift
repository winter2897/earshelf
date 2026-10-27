import SwiftData
import SwiftUI

@main
struct EarshelfApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var phase
    private let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Book.self, Episode.self)
        Downloader.shared.context = container.mainContext
        Downloader.shared.restore()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.brand)
                .fontDesign(.rounded)
        }
        .modelContainer(container)
        .onChange(of: phase) { if $1 != .active { Player.shared.save() } }
    }
}

struct RootView: View {
    var body: some View {
        @Bindable var p = Player.shared
        HomeView()
            .safeAreaInset(edge: .bottom) { MiniPlayer() }
            .fullScreenCover(isPresented: $p.isPresented) { PlayerView() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    // iOS đánh thức app khi tải nền xong — giữ completion để báo lại khi đã xử lý file.
    func application(_ app: UIApplication, handleEventsForBackgroundURLSession id: String, completionHandler: @escaping () -> Void) {
        Downloader.shared.backgroundCompletion = completionHandler
    }
}
