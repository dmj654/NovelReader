import UIKit

/// 一页渲染所需的最小数据单元
struct ReaderPage: Identifiable, Hashable {
    let id: UUID
    let chapterIndex: Int
    let chapterTitle: String
    let pageIndexInChapter: Int
    let pagesInChapter: Int
    let globalIndex: Int
    let totalPages: Int
    let attributedText: NSAttributedString

    static func == (lhs: ReaderPage, rhs: ReaderPage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 基于 TextKit 的分页器：把整章富文本按页面尺寸切成 NSRange，再由阅读器截取渲染。
enum ChapterPaginator {
    /// 返回每一页对应的字符范围
    static func pageRanges(for attributed: NSAttributedString, pageSize: CGSize) -> [NSRange] {
        guard attributed.length > 0, pageSize.width > 0, pageSize.height > 0 else {
            return [NSRange(location: 0, length: max(attributed.length, 0))]
        }

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        var ranges: [NSRange] = []
        var previousEnd = 0

        while previousEnd < layoutManager.numberOfGlyphs {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            container.maximumNumberOfLines = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let safeRange = NSRange(
                location: max(previousEnd, charRange.location),
                length: max(0, charRange.length)
            )
            ranges.append(safeRange)
            previousEnd = NSMaxRange(safeRange)

            // 兜底：极端情况下字符区间不推进会死循环
            if safeRange.length == 0 { break }
        }

        return ranges.isEmpty ? [NSRange(location: 0, length: attributed.length)] : ranges
    }

    /// 生成全书页面数组（章节顺序展开）
    static func buildPages(
        book: Book,
        settings: ReadingSettingsStore,
        pageSize: CGSize
    ) -> [ReaderPage] {
        let attributes = settings.bodyAttributes()
        var pages: [ReaderPage] = []

        for (chapterIndex, chapter) in book.chapters.enumerated() {
            let body = NSMutableAttributedString(string: chapter.content, attributes: attributes)
            // 首行缩进两个字符，模拟中文排版
            let indentStyle = NSMutableParagraphStyle()
            if let base = attributes[.paragraphStyle] as? NSParagraphStyle {
                indentStyle.setParagraphStyle(base)
            }
            indentStyle.firstLineHeadIndent = settings.fontSize * 2
            body.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: body.length))

            let ranges = pageRanges(for: body, pageSize: pageSize)
            for (pageIndex, range) in ranges.enumerated() {
                let slice = NSAttributedString(attributedString: body.attributedSubstring(from: range))
                pages.append(
                    ReaderPage(
                        id: UUID(),
                        chapterIndex: chapterIndex,
                        chapterTitle: chapter.title,
                        pageIndexInChapter: pageIndex,
                        pagesInChapter: ranges.count,
                        globalIndex: pages.count,
                        totalPages: 0, // 稍后回填
                        attributedText: slice
                    )
                )
            }
        }

        let total = max(pages.count, 1)
        return pages.enumerated().map { index, page in
            ReaderPage(
                id: page.id,
                chapterIndex: page.chapterIndex,
                chapterTitle: page.chapterTitle,
                pageIndexInChapter: page.pageIndexInChapter,
                pagesInChapter: page.pagesInChapter,
                globalIndex: index,
                totalPages: total,
                attributedText: page.attributedText
            )
        }
    }
}
