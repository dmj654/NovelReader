import SwiftUI
import Combine
import UIKit

/// 阅读器状态机：分页计算、页码定位、进度持久化、屏幕常亮与亮度。
@MainActor
final class ReaderViewModel: ObservableObject {
    let bookID: UUID
    let library: LibraryStore
    let settings: ReadingSettingsStore

    @Published private(set) var book: Book
    @Published var pages: [ReaderPage] = []
    @Published var currentIndex: Int = 0
    @Published var isChromeVisible: Bool = false
    @Published var activeChapterIndex: Int = 0

    private var pageSize: CGSize = .zero
    private var layoutSignature: String = ""
    private var isRestoring = false

    var currentPage: ReaderPage? {
        pages.indices.contains(currentIndex) ? pages[currentIndex] : nil
    }

    var progress: ReadingProgress {
        ReadingProgress(
            chapterIndex: currentPage?.chapterIndex ?? 0,
            pageIndex: currentPage?.pageIndexInChapter ?? 0,
            globalPageIndex: currentIndex,
            totalPages: max(pages.count, 1),
            updatedAt: Date()
        )
    }

    var percentText: String {
        guard !pages.isEmpty else { return "0%" }
        return String(format: "%.0f%%", Double(currentIndex + 1) / Double(pages.count) * 100)
    }

    init(book: Book, library: LibraryStore, settings: ReadingSettingsStore) {
        self.bookID = book.id
        self.book = book
        self.library = library
        self.settings = settings
        self.activeChapterIndex = library.progress(for: book.id).chapterIndex
    }

    // MARK: - 生命周期

    func onAppear() {
        applyScreenPolicy()
    }

    func onDisappear() {
        persist()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func applyScreenPolicy() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
        let clamped = min(max(settings.brightness, 0.4), 1.0)
        UIScreen.main.brightness = clamped
    }

    // MARK: - 分页

    /// 页面尺寸变化时重新分页；排版参数变化会强制重排并尽量保持阅读位置
    func updatePageSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let signature = settings.layoutSignature
        let sizeChanged = !size.width.isEqual(to: pageSize.width) || !size.height.isEqual(to: pageSize.height)
        let layoutChanged = signature != layoutSignature

        guard pages.isEmpty || sizeChanged || layoutChanged else { return }

        let previousChapter = currentPage?.chapterIndex ?? library.progress(for: bookID).chapterIndex
        let previousPageInChapter = currentPage?.pageIndexInChapter ?? library.progress(for: bookID).pageIndex

        pageSize = size
        layoutSignature = signature
        pages = ChapterPaginator.buildPages(book: book, settings: settings, pageSize: size)

        if isRestoring {
            restore(toChapter: previousChapter, pageInChapter: previousPageInChapter)
        } else {
            let saved = library.progress(for: bookID)
            restore(toChapter: saved.chapterIndex, pageInChapter: saved.pageIndex)
            isRestoring = true
        }
    }

    func invalidateLayout() {
        guard pageSize != .zero else { return }
        let chapter = currentPage?.chapterIndex ?? 0
        let pageInChapter = currentPage?.pageIndexInChapter ?? 0
        pages = ChapterPaginator.buildPages(book: book, settings: settings, pageSize: pageSize)
        restore(toChapter: chapter, pageInChapter: pageInChapter)
    }

    // MARK: - 定位

    func restore(toChapter chapterIndex: Int, pageInChapter: Int) {
        guard let target = pages.first(where: { $0.chapterIndex == chapterIndex && $0.pageIndexInChapter == pageInChapter })
                ?? pages.first(where: { $0.chapterIndex == chapterIndex })
                ?? pages.first else { return }
        currentIndex = target.globalIndex
        activeChapterIndex = target.chapterIndex
    }

    func jump(toChapter chapterIndex: Int) {
        guard let target = pages.first(where: { $0.chapterIndex == chapterIndex }) else { return }
        currentIndex = target.globalIndex
        activeChapterIndex = chapterIndex
        persist()
    }

    func jump(toGlobal index: Int) {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        activeChapterIndex = pages[index].chapterIndex
    }

    func goToNextChapter() {
        let next = activeChapterIndex + 1
        guard next < book.chapters.count else { return }
        jump(toChapter: next)
    }

    func goToPreviousChapter() {
        let previous = activeChapterIndex - 1
        guard previous >= 0 else { return }
        jump(toChapter: previous)
    }

    // MARK: - 网络章节（书源书按需抓取）

    var isNetworkBook: Bool { book.sourceID != nil }

    /// 确保某章正文可用：网络书按需抓取，成功后更新书库并重排版
    @discardableResult
    func ensureChapterContent(_ index: Int) async -> String? {
        guard book.chapters.indices.contains(index) else { return nil }
        let existing = book.chapters[index].content
        if !existing.isEmpty { return existing }

        guard let sourceID = book.sourceID,
              let links = book.chapterLinks,
              links.indices.contains(index),
              let source = library.source(withID: sourceID) else { return nil }

        do {
            let text = try await SourceEngine.fetchChapterText(source: source, link: links[index])
            applyChapterContent(text, to: index)
            return text
        } catch {
            library.lastError = "章节加载失败：\(error.localizedDescription)"
            return nil
        }
    }

    func applyChapterContent(_ text: String, to index: Int) {
        guard var updated = library.book(withID: bookID),
              updated.chapters.indices.contains(index) else { return }
        updated.chapters[index].content = text
        library.update(updated)
        book = updated
        invalidateLayout()
    }

    func persist() {
        library.saveProgress(progress, for: bookID)
    }

    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isChromeVisible.toggle()
        }
    }
}
