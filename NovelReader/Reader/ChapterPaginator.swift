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
    /// 本页文本在**章节全文**中的区间（听书高亮定位用）
    let rangeInChapter: NSRange
    let attributedText: NSAttributedString

    static func == (lhs: ReaderPage, rhs: ReaderPage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 分页输入：只带标题与正文，方便在后台线程并行处理
struct ChapterInput {
    let title: String
    let content: String
}

private struct PageEntry {
    let range: NSRange
    let text: NSAttributedString
}

private struct ChapterPagination {
    let chapterIndex: Int
    let chapterTitle: String
    let entries: [PageEntry]
}

/// 基于 TextKit 的分页器：把整章富文本按页面尺寸切成 NSRange，再由阅读器截取渲染。
///
/// 关键约束：分页用的 NSTextContainer 尺寸必须与渲染端 UITextView 的 textContainer 尺寸完全一致
/// （左右边距、上下页眉页脚都已在外面扣除），否则会出现截断或大片空白。
enum ChapterPaginator {
    /// 返回每一页对应的字符范围（纯字符坐标，不混用字形坐标）
    static func pageRanges(for attributed: NSAttributedString, pageSize: CGSize) -> [NSRange] {
        let length = attributed.length
        guard length > 0, pageSize.width > 0, pageSize.height > 0 else {
            return [NSRange(location: 0, length: max(length, 0))]
        }

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        // 先强制生成字形，保证后续 numberOfGlyphs / glyphRange(for:) 有效
        layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)

        var ranges: [NSRange] = []
        var charLocation = 0

        while charLocation < length {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            container.maximumNumberOfLines = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length == 0 { break }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let start = max(charRange.location, charLocation)
            var span = charRange.length
            if start > charRange.location {
                span -= (start - charRange.location)
            }
            if span <= 0 { break }

            let range = NSRange(location: start, length: min(span, length - start))
            ranges.append(range)
            let next = NSMaxRange(range)
            if next <= charLocation { break }   // 兜底：防止死循环
            charLocation = next
        }

        return ranges.isEmpty ? [NSRange(location: 0, length: length)] : ranges
    }

    /// 单章分页（可在后台线程执行）。
    /// 必须标 fileprivate：它的返回类型 ChapterPagination 是文件内私有类型，
    /// 否则 Swift 会报 "method must be declared fileprivate because its result uses a private type"。
    fileprivate static func paginateChapter(
        index: Int,
        title: String,
        content: String,
        attributes: [NSAttributedString.Key: Any],
        indent: CGFloat,
        pageSize: CGSize
    ) -> ChapterPagination {
        let body = NSMutableAttributedString(string: content, attributes: attributes)
        // 段首缩进两个字符，模拟中文排版
        let indentStyle = NSMutableParagraphStyle()
        if let base = attributes[.paragraphStyle] as? NSParagraphStyle {
            indentStyle.setParagraphStyle(base)
        }
        indentStyle.firstLineHeadIndent = indent
        body.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: body.length))

        let ranges = pageRanges(for: body, pageSize: pageSize)
        let entries = ranges.map { range in
            PageEntry(
                range: range,
                text: NSAttributedString(attributedString: body.attributedSubstring(from: range))
            )
        }
        return ChapterPagination(chapterIndex: index, chapterTitle: title, entries: entries)
    }

    /// 全书分页：按章节并发计算，避免大部头图书阻塞主线程
    static func buildPages(
        chapters: [ChapterInput],
        attributes: [NSAttributedString.Key: Any],
        indent: CGFloat,
        pageSize: CGSize
    ) async -> [ReaderPage] {
        let batches = await withTaskGroup(of: ChapterPagination.self) { group -> [ChapterPagination] in
            for (index, chapter) in chapters.enumerated() {
                let title = chapter.title
                let content = chapter.content
                let attributesCopy = attributes
                let indentValue = indent
                let size = pageSize
                group.addTask {
                    ChapterPaginator.paginateChapter(
                        index: index,
                        title: title,
                        content: content,
                        attributes: attributesCopy,
                        indent: indentValue,
                        pageSize: size
                    )
                }
            }
            var collected: [ChapterPagination] = []
            for await batch in group {
                collected.append(batch)
            }
            return collected
        }

        let sorted = batches.sorted { $0.chapterIndex < $1.chapterIndex }
        var pages: [ReaderPage] = []
        for batch in sorted {
            for (pageIndex, entry) in batch.entries.enumerated() {
                pages.append(
                    ReaderPage(
                        id: UUID(),
                        chapterIndex: batch.chapterIndex,
                        chapterTitle: batch.chapterTitle,
                        pageIndexInChapter: pageIndex,
                        pagesInChapter: batch.entries.count,
                        globalIndex: pages.count,
                        totalPages: 0, // 稍后回填
                        rangeInChapter: entry.range,
                        attributedText: entry.text
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
                rangeInChapter: page.rangeInChapter,
                attributedText: page.attributedText
            )
        }
    }
}
