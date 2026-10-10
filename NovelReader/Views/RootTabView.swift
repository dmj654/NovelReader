import SwiftUI

/// 根导航采用 Tab Bar（3 个标签），不使用 hamburger 菜单。
struct RootTabView: View {
    @State private var selection: Tab = .shelf

    enum Tab: Hashable {
        case shelf, explore, me
    }

    var body: some View {
        // 使用 tabItem + tag 写法而非 iOS 18 的 Tab(_:systemImage:value:)，
        // 保证最低部署系统为 iOS 17.0，覆盖 iPhone 8 之后的绝大多数设备。
        TabView(selection: $selection) {
            ShelfView()
                .tabItem {
                    Label("书架", systemImage: "books.vertical.fill")
                }
                .tag(Tab.shelf)
                .accessibilityLabel("书架")

            ExploreView()
                .tabItem {
                    Label("发现", systemImage: "sparkle.magnifyingglass")
                }
                .tag(Tab.explore)
                .accessibilityLabel("发现")

            MeView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(Tab.me)
                .accessibilityLabel("我的")
        }
        .tint(.accentColor)
    }
}
