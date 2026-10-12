import Foundation

/// TXT 小说解析器：负责编码探测、章节切分与正文清洗。
enum NovelParser {
    /// 常见的中文小说章节标题形态
    private static let chapterPatterns: [NSRegularExpression] = {
        let patterns = [
            #"^\s{0,4}(第\s*[0-9０-９零一二三四五六七八九十百千万两]+\s*[章节回节卷篇折出集部幕])([\s\S]{0,60})"#,
            #"^\s{0,4}(Chapter|CHAPTER|chapter)\s*[0-9IVXivx]+([\s\S]{0,60})"#,
            #"^\s{0,4}(序章|序言|楔子|引子|后记|尾声|番外|终章|结语)([\s\S]{0,60})"#,
            #"^\s{0,4}([0-9]{1,4})\s*[、.．]\s*\S{1,40}\s*$"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
    }()

    /// 中文小说常见编码，按优先级尝试
    private static let encodings: [String.Encoding] = [
        .utf8,
        .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
        .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
        .unicode
    ]

    // MARK: - 公开方法

    /// 从文件 URL 解析出一本书（文件名作为书名兜底）
    static func parse(fileURL: URL) throws -> Book {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard let text = decode(data) else {
            throw NovelParserError.encodingNotSupported
        }

        let filename = fileURL.deletingPathExtension().lastPathComponent
        return makeBook(from: text, fallbackTitle: filename)
    }

    /// 从纯文本解析
    static func parse(text: String, fallbackTitle: String) -> Book {
        makeBook(from: text, fallbackTitle: fallbackTitle)
    }

    // MARK: - 内部实现

    private static func decode(_ data: Data) -> String? {
        // 先按 BOM 精确判定（Windows 导出的 txt 常带 BOM）
        if let bomText = decodeByBOM(data) { return bomText }

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                // UTF-8 误判检测：GB18030 文本用 UTF-8 解码会得到大量替换字符
                let broken = text.contains("\u{FFFD}")
                if encoding == .utf8 && broken { continue }
                if !broken || encoding != .utf8 { return text }
            }
        }
        return nil
    }

    private static func decodeByBOM(_ data: Data) -> String? {
        // 至少要 3 个字节才能判 UTF-8 BOM（判 UTF-16 只需 2 个，这里统一按最长的取）
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data.prefix(3))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBE || bytes[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes[0] == 0xFF, bytes[1] == 0xFE {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if bytes[0] == 0xFE, bytes[1] == 0xFF {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        return nil
    }

    private static func makeBook(from rawText: String, fallbackTitle: String) -> Book {
        let text = normalize(rawText)
        let ranges = chapterRanges(in: text)

        var chapters: [Chapter] = []

        if ranges.isEmpty {
            // 无章节标记：按 3000 字自动分卷，保证超长文本也能正常分页
            chapters = autoSplit(text, size: 3000)
        } else {
            for (index, match) in ranges.enumerated() {
                let start = match.range.lowerBound
                let end = index + 1 < ranges.count ? ranges[index + 1].range.lowerBound : text.count
                let block = slice(text, from: start, to: end)
                let title = extractTitle(from: block)
                let body = extractBody(from: block)
                guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                chapters.append(Chapter(title: title, content: body))
            }
        }

        let titleLine = extractBookTitle(from: text) ?? fallbackTitle

        return Book(
            title: fallbackTitle.isEmpty ? titleLine : fallbackTitle,
            author: extractAuthor(from: text) ?? "佚名",
            intro: makeIntro(from: chapters),
            category: "本地导入",
            coverTheme: CoverTheme.allCases.randomElement() ?? .indigo,
            chapters: chapters
        )
    }

    /// 统一换行、去掉页眉页脚常见的广告行、压缩多余空行
    private static func normalize(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let adPattern = try? NSRegularExpression(
            pattern: #"(?m)^\s*(本书由|更多精彩|请记住本站|手机阅读|免费小说|www\.|http://|https://).{0,80}$"#,
            options: []
        )
        if let regex = adPattern {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                result = (result as NSString).replacingCharacters(in: match.range, with: "")
            }
        }

        // 三个以上连续换行压缩为两个
        let blankPattern = try? NSRegularExpression(pattern: #"\n{3,}"#, options: [])
        if let regex = blankPattern {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\n\n")
        }
        return result
    }

    private static func chapterRanges(in text: String) -> [NSTextCheckingResult] {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var results: [NSTextCheckingResult] = []
        for regex in chapterPatterns {
            results.append(contentsOf: regex.matches(in: text, options: [], range: full))
        }
        return results.sorted { $0.range.location < $1.range.location }
            .filterDistinctByLocation()
    }

    private static func slice(_ text: String, from start: Int, to end: Int) -> String {
        let ns = text as NSString
        let location = max(0, min(start, ns.length))
        let length = max(0, min(end, ns.length) - location)
        return ns.substring(with: NSRange(location: location, length: length))
    }

    private static func extractTitle(from block: String) -> String {
        guard let line = block.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return "第一章"
        }
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "开篇" : String(cleaned.prefix(40))
    }

    private static func extractBody(from block: String) -> String {
        var body = block
        if let range = block.range(of: "\n") {
            body = String(block[range.upperBound...])
        }
        // 每段左侧多余空格去掉，段内保留；map 里显式转 String，避免 Substring 类型不匹配
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var trimmed = String(line)
            while trimmed.hasPrefix(" ") || trimmed.hasPrefix("\u{3000}") {
                trimmed.removeFirst()
            }
            return trimmed
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func autoSplit(_ text: String, size: Int) -> [Chapter] {
        guard !text.isEmpty else { return [Chapter(title: "开篇", content: "（空文件）")] }
        var chapters: [Chapter] = []
        var index = 0
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            let piece = String(text[start..<end])
            index += 1
            chapters.append(Chapter(title: "第 \(index) 部分", content: piece))
            start = end
        }
        return chapters
    }

    private static func extractBookTitle(from text: String) -> String? {
        let ns = text as NSString
        let pattern = #"(?m)^\s*(书名|标题|Title)\s*[:：]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAuthor(from text: String) -> String? {
        let ns = text as NSString
        let pattern = #"(?m)^\s*(作者|Author)\s*[:：]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeIntro(from chapters: [Chapter]) -> String {
        guard let first = chapters.first else { return "" }
        return String(first.content.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum NovelParserError: LocalizedError {
    case encodingNotSupported

    var errorDescription: String? {
        switch self {
        case .encodingNotSupported: return "无法识别该文件的文字编码，请尝试转换为 UTF-8 后重新导入。"
        }
    }
}

private extension Array where Element == NSTextCheckingResult {
    /// 多个正则可能命中同一行，按起点去重
    func filterDistinctByLocation() -> [Element] {
        var seen = Set<Int>()
        return filter { seen.insert($0.range.location).inserted }
    }
}
