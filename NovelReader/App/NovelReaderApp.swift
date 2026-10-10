import SwiftUI

@main
struct NovelReaderApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings = ReadingSettingsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(library)
                .environmentObject(settings)
                .task { library.load() }
                // 放在 View 层监听（Scene 层的 onChange 签名在各 Xcode 版本不一致，View 层最稳）
                .onChange(of: scenePhase) { _, phase in
                    // App 进入后台或中断时立即落盘，避免进度丢失
                    if phase != .active {
                        library.save()
                    }
                }
        }
    }
}
