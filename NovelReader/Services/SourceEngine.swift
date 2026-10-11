import Foundation

/// 书源引擎：网络请求 + 正则提取。全部 async/await，不依赖第三方库。
enum SourceEngine {
    struct SearchResult: Identifiable, Hashable {
        let title: String
        let link: String
        var id: String { link }
    }

    enum SourceError: LocalizedError {
        case badURL
        case badRule
        case httpStatus(Int)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .badURL: return "链接格式不正确。"
            case .badRule: return "书源规则不是合法的正则表达式。"
            case .httpStatus(let code): return "站点返回了异常状态码 \(code)。"
            case .emptyResult: return "没有解析到内容，请检查规则或换一章试试。"
            }
        }
    }

    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    // MARK: - 网络

    static func fetchHTML(urlString: String, referer: String? = nil) async throws -> String {
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw SourceError.badURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.httpStatus(http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8), !text.contains("\u{FFFD}") {
            return text
        }
        if let text = String(data: data, encoding: gb18030) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        throw SourceError.badURL
    }

    // MARK: - 搜索

    static func searchURL(source: BookSource, query: String, page: Int) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return source.searchTemplate
            .replacingOccurrences(of: "{query}", with: encoded)
            .replacingOccurrences(of: "{page}", with: String(page))
    }

    static func search(source: BookSource, query: String, page: Int = 1) async throws -> [SearchResult] {
        let html = try await fetchHTML(urlString: searchURL(source: source, query: query, page: page), referer: source.baseURL)
        let results = extractLinks(
            html: html,
            pattern: source.rules.listPattern,
            titleGroup: source.rules.titleGroup,
            linkGroup: source.rules.linkGroup,
            baseURL: source.baseURL
        )
        guard !results.isEmpty else { throw SourceError.emptyResult }
        return results
    }

    /// 可用性校验：能发通请求并解析出至少一条结果（或页面非空）即视为可用
    static func checkAvailability(_ source: BookSource) async -> Bool {
        do {
            _ = try await search(source: source, query: "我", page: 1)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 提取

    /// 从 HTML 里按正则提取「标题 + 链接」列表
    static func extractLinks(
        html: String,
        pattern: String,
        titleGroup: Int,
        linkGroup: Int,
        baseURL: String
    ) -> [SearchResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var results: [SearchResult] = []
        for match in matches {
            func group(_ index: Int) -> String? {
                guard index > 0, index <= match.numberOfRanges,
                      match.range(at: index).location != NSNotFound else { return nil }
                let raw = ns.substring(with: match.range(at: index))
                let cleaned = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
            guard let title = group(titleGroup), let link = group(linkGroup) else { continue }
            let absolute = absoluteURL(link, baseURL: baseURL)
            guard !seen.contains(absolute) else { continue }
            seen.insert(absolute)
            results.append(SearchResult(title: title, link: absolute))
        }
        return results
    }

    /// 小说正文：优先 contentPattern 捕获组，否则整页去标签
    static func fetchChapterText(source: BookSource, link: String) async throws -> String {
        let html = try await fetchHTML(urlString: link, referer: source.baseURL)
        var text = ""
        if let pattern = source.rules.contentPattern, !pattern.isEmpty,
           let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let ns = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            if let first = matches.first, first.numberOfRanges > 1 {
                text = ns.substring(with: first.range(at: 1))
            }
        }
        if text.isEmpty { text = html }
        let cleaned = stripTags(text)
        guard !cleaned.isEmpty else { throw SourceError.emptyResult }
        return cleaned
    }

    /// 漫画：章节页里的图片 URL 列表
    static func fetchImageURLs(source: BookSource, link: String) async throws -> [String] {
        let html = try await fetchHTML(urlString: link, referer: source.baseURL)
        let pattern = source.rules.imagePattern ?? #"<img[^>]+src=\"([^\"]+\.(?:jpg|jpeg|png|webp|gif))[^\"]*\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            throw SourceError.badRule
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var urls: [String] = []
        for match in matches {
            let groupIndex = match.numberOfRanges > 1 ? 1 : 0
            guard match.range(at: groupIndex).location != NSNotFound else { continue }
            let raw = ns.substring(with: match.range(at: groupIndex))
            let absolute = absoluteURL(decodeEntities(raw), baseURL: source.baseURL)
            urls.append(absolute)
        }
        guard !urls.isEmpty else { throw SourceError.emptyResult }
        return urls
    }

    // MARK: - 诊断

    /// 把各类错误翻译成一句"人能看懂、知道下一步做什么"的话
    static func readableMessage(_ error: Error) -> String {
        if let sourceError = error as? SourceError {
            switch sourceError {
            case .badURL: return "地址格式不对，检查书源的站点地址与搜索地址是否以 http(s):// 开头。"
            case .badRule: return "书源规则不是合法正则表达式，去书源管理里改一下。"
            case .httpStatus(let code): return "站点返回状态码 \(code)。可能被反爬或被重定向，换一个书源试试。"
            case .emptyResult: return "页面能打开，但正则没匹配到内容——需要在书源管理里调整『结果列表正则』的捕获组。"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "连接超时。这个站点在当前网络下可能访问不了。"
            case .notConnectedToInternet: return "手机当前没有联网。"
            case .cannotFindHost, .cannotConnectToHost: return "连不上这个站点，检查站点地址是否正确。"
            case .badServerResponse: return "站点返回了异常响应。"
            case .cancelled: return "请求被取消。"
            default: return "网络错误：\(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    /// 校验书源并返回可读结论
    static func diagnose(_ source: BookSource) async -> String {
        do {
            let found = try await search(source: source, query: "的", page: 1)
            return found.isEmpty ? "能连上，但没解析到结果，检查正则捕获组。" : "可用，解析到 \(found.count) 条结果。"
        } catch {
            return readableMessage(error)
        }
    }

    // MARK: - 工具

    static func absoluteURL(_ link: String, baseURL: String) -> String {
        if link.hasPrefix("http://") || link.hasPrefix("https://") { return link }
        if let base = URL(string: baseURL), let url = URL(string: link, relativeTo: base) {
            return url.absoluteString
        }
        return link
    }

    static func stripTags(_ html: String) -> String {
        var text = html
        let tagRegex = try? NSRegularExpression(pattern: #"<(script|style)[\s\S]*?</\1>"#, options: [.caseInsensitive])
        if let regex = tagRegex {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        let brRegex = try? NSRegularExpression(pattern: #"<br\s*/?>|</p>|</div>"#, options: [.caseInsensitive])
        if let regex = brRegex {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
        }
        let strip = try? NSRegularExpression(pattern: #"<[^>]+>"#)
        if let regex = strip {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        let cleaned = decodeEntities(text)
        let blankRegex = try? NSRegularExpression(pattern: #"\n{3,}"#)
        if let regex = blankRegex {
            let range = NSRange(location: 0, length: (cleaned as NSString).length)
            return regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ input: String) -> String {
        var text = input
        let map: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in map {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        // 数字实体 &#123; 与 &#x1F600;
        let numeric = try? NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#)
        if let regex = numeric {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let isHex = ns.substring(with: match.range(at: 1)).lowercased() == "x"
                let digits = ns.substring(with: match.range(at: 2))
                let radix = isHex ? 16 : 10
                if let value = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(value) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }
        return text
    }
}
