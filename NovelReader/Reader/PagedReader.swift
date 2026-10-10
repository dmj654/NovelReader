import SwiftUI
import UIKit

/// UIPageViewController 的 SwiftUI 封装，用于仿真翻页（.pageCurl）。
struct PagedReader: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let backgroundColor: UIColor
    @Binding var currentIndex: Int
    /// 听书跟读：返回某页需要高亮的页内区间（nil = 不高亮）
    var highlightFor: (Int) -> NSRange? = { _ in nil }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options: [UIPageViewController.OptionsKey: Any] = [
            .spineLocation: UIPageViewController.SpineLocation.min.rawValue,
            .interPageSpacing: 0
        ]
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
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

        init(_ parent: PagedReader) {
            self.parent = parent
        }

        func invalidateCacheIfNeeded() {
            if cachedCount != parent.pages.count {
                cache.removeAll()
                cachedCount = parent.pages.count
            }
        }

        /// 把最新的高亮区间写回缓存中的每一页
        func refreshHighlights() {
            for (index, host) in cache {
                let page = parent.pages.indices.contains(index) ? parent.pages[index] : nil
                host.rootView = ReaderPageContainer(
                    page: page,
                    backgroundColor: parent.backgroundColor,
                    highlightRange: parent.highlightFor(index)
                )
            }
        }

        func controller(at index: Int) -> UIViewController {
            if let cached = cache[index] { return cached }
            guard parent.pages.indices.contains(index) else {
                return UIHostingController(rootView: ReaderPageContainer(page: nil, backgroundColor: parent.backgroundColor))
            }
            let host = UIHostingController(
                rootView: ReaderPageContainer(
                    page: parent.pages[index],
                    backgroundColor: parent.backgroundColor,
                    highlightRange: parent.highlightFor(index)
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

/// 页面容器：正文 + 页眉章节名 + 页脚页码
struct ReaderPageContainer: View {
    let page: ReaderPage?
    let backgroundColor: UIColor
    var highlightRange: NSRange? = nil

    var body: some View {
        Color(uiColor: backgroundColor)
            .overlay(alignment: .top) {
                if let page {
                    VStack(spacing: 0) {
                        HStack {
                            Text(page.chapterTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        .accessibilityHidden(true)

                        ReaderPageView(
                            attributedText: page.attributedText,
                            backgroundColor: backgroundColor,
                            highlightRange: highlightRange
                        )
                        .padding(.horizontal, 24)

                        Spacer(minLength: 0)

                        HStack {
                            Spacer(minLength: 8)
                            Text("\(page.globalIndex + 1) / \(page.totalPages)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("第 \(page.globalIndex + 1) 页，共 \(page.totalPages) 页")
                }
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
