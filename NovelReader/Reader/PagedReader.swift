import SwiftUI
import UIKit

/// UIPageViewController 的 SwiftUI 封装：仿真翻页（.pageCurl）或左右滑动（.scroll）。
struct PagedReader: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let backgroundColor: UIColor
    let transitionStyle: UIPageViewController.TransitionStyle
    /// 正文区高度：与分页时使用的高度一致，保证渲染不截断、不留大片空白
    let bodyHeight: CGFloat
    /// 正文左右边距：同样要与分页端一致
    let horizontalPadding: CGFloat
    @Binding var currentIndex: Int
    /// 听书跟读：返回某页需要高亮的页内区间（nil = 不高亮）
    var highlightFor: (Int) -> NSRange? = { _ in nil }
    /// 正文区实测尺寸回调：渲染端量到容器真实宽高后回传，分页端按这个尺寸算，
    /// 从机制上保证"分页用的高度 == 渲染可用的高度"，杜绝底部截断或大片空白。
    /// （v1.1 踩过的坑：在 .task 里读 safeAreaInsets 时布局尚未完成，拿到 0，高度算错一截）
    var onBodySize: ((CGSize) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options: [UIPageViewController.OptionsKey: Any] = [
            .spineLocation: UIPageViewController.SpineLocation.min.rawValue,
            .interPageSpacing: transitionStyle == .scroll ? 8 : 0
        ]
        let controller = UIPageViewController(
            transitionStyle: transitionStyle,
            navigationOrientation: .horizontal,
            options: options
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = backgroundColor
        // 不拦截系统边缘返回手势
        controller.modalPresentationStyle = .fullScreen
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.invalidateCacheIfNeeded()
        // 听书高亮变化时刷新缓存页
        context.coordinator.refreshHighlights()

        let target = min(max(currentIndex, 0), max(pages.count - 1, 0))
        guard pages.indices.contains(target) else { return }

        let viewController = context.coordinator.controller(at: target)
        if let visible = controller.viewControllers?.first, visible === viewController {
            return
        }
        controller.setViewControllers([viewController], direction: .forward, animated: false)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReader
        private var cache: [Int: UIHostingController<ReaderPageContainer>] = [:]
        private var cachedCount: Int = -1
        private var cachedBodyHeight: CGFloat = -1

        init(_ parent: PagedReader) {
            self.parent = parent
        }

        func invalidateCacheIfNeeded() {
            if cachedCount != parent.pages.count || cachedBodyHeight != parent.bodyHeight {
                cache.removeAll()
                cachedCount = parent.pages.count
                cachedBodyHeight = parent.bodyHeight
            }
        }

        /// 把最新的高亮区间写回缓存中的每一页
        func refreshHighlights() {
            for (index, host) in cache {
                let page = parent.pages.indices.contains(index) ? parent.pages[index] : nil
                host.rootView = ReaderPageContainer(
                    page: page,
                    backgroundColor: parent.backgroundColor,
                    bodyHeight: parent.bodyHeight,
                    horizontalPadding: parent.horizontalPadding,
                    highlightRange: parent.highlightFor(index),
                    onBodySize: parent.onBodySize
                )
            }
        }

        func controller(at index: Int) -> UIViewController {
            if let cached = cache[index] { return cached }
            guard parent.pages.indices.contains(index) else {
                return UIHostingController(
                    rootView: ReaderPageContainer(
                        page: nil,
                        backgroundColor: parent.backgroundColor,
                        bodyHeight: parent.bodyHeight,
                        horizontalPadding: parent.horizontalPadding,
                        onBodySize: parent.onBodySize
                    )
                )
            }
            let host = UIHostingController(
                rootView: ReaderPageContainer(
                    page: parent.pages[index],
                    backgroundColor: parent.backgroundColor,
                    bodyHeight: parent.bodyHeight,
                    horizontalPadding: parent.horizontalPadding,
                    highlightRange: parent.highlightFor(index),
                    onBodySize: parent.onBodySize
                )
            )
            host.view.backgroundColor = parent.backgroundColor
            cache[index] = host
            return host
        }

        func index(of controller: UIViewController) -> Int? {
            cache.first { $0.value === controller }?.key
        }

        // MARK: Data Source

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = index(of: viewController), index > 0 else { return nil }
            return controller(at: index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = index(of: viewController), index < parent.pages.count - 1 else { return nil }
            return controller(at: index + 1)
        }

        // MARK: Delegate

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let visible = pageViewController.viewControllers?.first,
                  let index = index(of: visible) else { return }
            DispatchQueue.main.async {
                self.parent.currentIndex = index
            }
        }
    }
}

/// 页面容器：页眉章节名 + 固定高度正文 + 页脚页码（高度与分页端完全对齐）
struct ReaderPageContainer: View {
    let page: ReaderPage?
    let backgroundColor: UIColor
    let bodyHeight: CGFloat
    let horizontalPadding: CGFloat
    var highlightRange: NSRange? = nil
    /// 渲染端实测尺寸回调（见 PagedReader.onBodySize）
    var onBodySize: ((CGSize) -> Void)? = nil

    var body: some View {
        // 用 GeometryReader 量到"这一页真实被分到的高度"，减去页眉页脚后回传给分页端。
        // 这是分页与渲染唯一的尺寸来源，两边不可能再对不上。
        GeometryReader { geo in
            Color(uiColor: backgroundColor)
                .overlay(alignment: .top) {
                    if let page {
                        VStack(spacing: 0) {
                            pageHeader(page)
                                .frame(height: ReaderLayout.headerHeight)

                            ReaderPageView(
                                attributedText: page.attributedText,
                                backgroundColor: backgroundColor,
                                highlightRange: highlightRange
                            )
                            // 左右边距必须和分页时扣掉的宽度完全一致，否则行宽不同、页面底部会留白
                            .padding(.horizontal, horizontalPadding)
                            .frame(height: max(bodyHeight, 1))
                            .clipped()

                            Spacer(minLength: 0)

                            pageFooter(page)
                                .frame(height: ReaderLayout.footerHeight)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("第 \(page.globalIndex + 1) 页，共 \(page.totalPages) 页")
                    }
                }
                .onAppear { report(geo.size) }
                .onChange(of: geo.size) { _, new in report(new) }
        }
    }

    /// 把"容器真实高度 − 页眉 − 页脚"回传给分页端
    private func report(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let bodyHeight = max(size.height - ReaderLayout.headerHeight - ReaderLayout.footerHeight, 1)
        onBodySize?(CGSize(width: max(size.width - horizontalPadding * 2, 1), height: bodyHeight))
    }

    private func pageHeader(_ page: ReaderPage) -> some View {
        HStack {
            Text(page.chapterTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, horizontalPadding)
        .accessibilityHidden(true)
    }

    private func pageFooter(_ page: ReaderPage) -> some View {
        HStack(spacing: 12) {
            Text("\(page.pageIndexInChapter + 1) / \(page.pagesInChapter)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            ReaderStatusText()
            Spacer(minLength: 8)
            Text("\(page.globalIndex + 1) / \(page.totalPages)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, horizontalPadding)
        .accessibilityHidden(true)
    }
}

/// 页脚的时间与电量（每 30 秒刷新一次）
private struct ReaderStatusText: View {
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(statusText)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .onReceive(timer) { value in now = value }
            .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    private var statusText: String {
        let time = now.formatted(.dateTime.hour().minute())
        let level = UIDevice.current.batteryLevel
        if level < 0 { return time }
        return time + "  \(Int(round(level * 100)))%"
    }
}
