import SwiftUI
import Combine
import UIKit

/// 导入结果：成功与否 + 可直接展示给用户的一句话说明
struct LibraryImportOutcome {
    let success: Bool
    let message: String
    let bookID: UUID?
}

/// 书架数据中枢：书籍与阅读进度的持久化、增删改、txt 导入、书源管理。
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var progress: [UUID: ReadingProgress] = [:]
    @Published private(set) var sources: [BookSource] = []
    @Published var lastError: String?

    private let fileManager = FileManager.default
    private let booksURL: URL
    private let progressURL: URL
    private let sourcesURL: URL

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.booksURL = documents.appendingPathComponent("shelf.json", isDirectory: false)
        self.progressURL = documents.appendingPathComponent("progress.json", isDirectory: false)
        self.sourcesURL = documents.appendingPathComponent("sources.json", isDirectory: false)
    }

    // MARK: - 读写

    func load() {
        if books.isEmpty {
            books = Self.decode([Book].self, from: booksURL) ?? SampleLibrary.books
        }
        progress = Self.decode([UUID: ReadingProgress].self, from: progressURL) ?? [:]
        sources = Self.decode([BookSource].self, from: sourcesURL) ?? SampleLibrary.bookSources
        migrateLegacySampleComic()
    }

    /// 旧版示例漫画用的是外网占位图，改成 App 本地绘制的页面，保证离线可看
    private func migrateLegacySampleComic() {
        for index in books.indices {
            guard books[index].isComic, let pages = books[index].pageImages else { continue }
            guard pages.joined().contains("picsum.photos") else { continue }
            let converted = pages.enumerated().map { chapterOffset, list in
                list.enumerated().map { pageOffset, _ in
                    "art://\(chapterOffset * 4 + pageOffset + 1)"
                }
            }
            books[index].pageImages = converted
        }
    }

    func save() {
        Self.encode(books, to: booksURL)
        Self.encode(progress, to: progressURL)
        Self.encode(sources, to: sourcesURL)
    }

    // MARK: - 书籍操作

    func add(_ book: Book) {
        guard !books.contains(where: { $0.title == book.title && $0.author == book.author }) else { return }
        books.insert(book, at: 0)
        save()
    }

    func remove(_ book: Book) {
        books.removeAll { $0.id == book.id }
        progress.removeValue(forKey: book.id)
        save()
    }

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        save()
    }

    func book(withID id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    func markFinished(_ book: Book, finished: Bool) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].isFinished = finished
        save()
    }

    // MARK: - 进度

    func progress(for bookID: UUID) -> ReadingProgress {
        progress[bookID] ?? .zero
    }

    func saveProgress(_ value: ReadingProgress, for bookID: UUID) {
        progress[bookID] = value
        save()
    }

    // MARK: - 导入

    /// 导入本地 txt 文件（异步解析，不卡界面；无论成败都返回一句可展示的说明）
    @discardableResult
    func importBook(from url: URL) async -> LibraryImportOutcome {
        let accessed = url.startAccessingSecurityScopedResource()
        let parsed = await Task.detached(priority: .userInitiated) { () -> Result<Book, Error> in
            do {
                return .success(try NovelParser.parse(fileURL: url))
            } catch {
                return .failure(error)
            }
        }.value
        if accessed { url.stopAccessingSecurityScopedResource() }

        switch parsed {
        case .failure(let error):
            let message = "导入失败：\(error.localizedDescription)"
            await MainActor.run { self.lastError = message }
            return LibraryImportOutcome(success: false, message: message, bookID: nil)
        case .success(let book):
            return await MainActor.run {
                guard !book.chapters.isEmpty else {
                    let message = "文件里没有读到正文内容，换一个文件试试。"
                    self.lastError = message
                    return LibraryImportOutcome(success: false, message: message, bookID: nil)
                }
                guard !self.books.contains(where: { $0.title == book.title && $0.author == book.author }) else {
                    return LibraryImportOutcome(
                        success: false,
                        message: "《\(book.title)》已经在书架里了。",
                        bookID: nil
                    )
                }
                self.add(book)
                return LibraryImportOutcome(
                    success: true,
                    message: "已导入《\(book.title)》，共 \(book.chapters.count) 章。",
                    bookID: book.id
                )
            }
        }
    }

    /// 从「文件」App 或其他 App 分享进来的文件（自动复制到沙盒后再解析）
    @discardableResult
    func handleIncomingFile(_ url: URL) async -> LibraryImportOutcome {
        guard url.isFileURL else {
            return LibraryImportOutcome(success: false, message: "不支持的链接类型。", bookID: nil)
        }
        return await importBook(from: url)
    }

    /// 从本地图片生成一本漫画（图片会复制到沙盒并压缩，之后离线可读）
    @discardableResult
    func importComic(title: String, imageURLs: [URL]) async -> LibraryImportOutcome {
        guard !imageURLs.isEmpty else {
            return LibraryImportOutcome(success: false, message: "没有选中任何图片。", bookID: nil)
        }

        let folderName = UUID().uuidString
        let stored = await Task.detached(priority: .userInitiated) { () -> [String] in
            let manager = FileManager.default
            guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
            let folder = documents.appendingPathComponent("Comics", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)

            var paths: [String] = []
            var index = 0
            for url in imageURLs {
                let accessed = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
                guard let data, let image = UIImage(data: data) else { continue }
                index += 1
                let name = String(format: "%03d.jpg", index)
                let destination = folder.appendingPathComponent(name, isDirectory: false)
                let scaled = image.resized(maxDimension: 1600)
                if let jpeg = scaled.jpegData(compressionQuality: 0.85) {
                    try? jpeg.write(to: destination)
                    paths.append("local://Comics/\(folderName)/\(name)")
                }
            }
            return paths
        }.value

        return await MainActor.run {
            guard !stored.isEmpty else {
                let message = "这些图片没能读取成功，请确认它们是常见的 JPG / PNG 格式。"
                self.lastError = message
                return LibraryImportOutcome(success: false, message: message, bookID: nil)
            }
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = Book(
                title: name.isEmpty ? "我的漫画" : name,
                author: "本地导入",
                intro: "共 \(stored.count) 页，来自本地图片。",
                category: "漫画",
                coverTheme: CoverTheme.allCases.randomElement() ?? .teal,
                chapters: [Chapter(title: "第 1 话", content: "")],
                kind: .comic,
                pageImages: [stored]
            )
            self.add(book)
            return LibraryImportOutcome(
                success: true,
                message: "已导入《\(book.title)》，共 \(stored.count) 页。",
                bookID: book.id
            )
        }
    }

    /// 从 .json 文件导入书源
    func importSourcesFile(from url: URL) async -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        let text = await Task.detached(priority: .userInitiated) { () -> String? in
            if let data = try? Data(contentsOf: url) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }.value
        if accessed { url.stopAccessingSecurityScopedResource() }

        guard let text, !text.isEmpty else {
            return "没能读取这个文件，确认它是 UTF-8 编码的 .json 文件。"
        }
        return await MainActor.run {
            do {
                let count = try self.importSourcesJSON(text)
                return "成功导入 \(count) 个书源。"
            } catch {
                return error.localizedDescription
            }
        }
    }

    // MARK: - 书源

    func source(withID id: String?) -> BookSource? {
        guard let id else { return nil }
        return sources.first { $0.id == id }
    }

    func enabledSources(isComic: Bool) -> [BookSource] {
        sources
            .filter { $0.isEnabled && $0.isComic == isComic }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func upsertSource(_ source: BookSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
        sources.sort { $0.sortOrder < $1.sortOrder }
        save()
    }

    func removeSource(_ source: BookSource) {
        sources.removeAll { $0.id == source.id }
        save()
    }

    func toggleSource(_ source: BookSource, enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].isEnabled = enabled
        save()
    }

    /// 拖拽排序
    func moveSources(fromOffsets: IndexSet, toOffset: Int) {
        var ordered = sources.sorted { $0.sortOrder < $1.sortOrder }
        ordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        sources = ordered.enumerated().map { index, source in
            var updated = source
            updated.sortOrder = index
            return updated
        }
        save()
    }

    /// 从剪贴板/文本导入书源 JSON（支持单个对象或数组），返回导入条数
    @discardableResult
    func importSourcesJSON(_ text: String) throws -> Int {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        var imported: [BookSource] = []
        if let list = try? decoder.decode([BookSource].self, from: data) {
            imported = list
        } else if let single = try? decoder.decode(BookSource.self, from: data) {
            imported = [single]
        }
        guard !imported.isEmpty else {
            throw NSError(
                domain: "BookSource",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "没有识别到有效的书源，请检查 JSON 格式。"]
            )
        }
        for var source in imported {
            if sources.contains(where: { $0.id == source.id }) {
                source.sortOrder = (sources.map(\.sortOrder).max() ?? 0) + 1
                upsertSource(source)
            } else {
                source.sortOrder = (sources.map(\.sortOrder).max() ?? 0) + 1
                upsertSource(source)
            }
        }
        return imported.count
    }

    /// 导出全部书源为 JSON 文本
    func exportSourcesJSON() -> String {
        let ordered = sources.sorted { $0.sortOrder < $1.sortOrder }
        guard let data = try? JSONEncoder().encode(ordered) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// 把搜索结果加入书架：先解析目录页得到章节链接，解析失败则按单章加入
    func addBook(from result: SourceEngine.SearchResult, source: BookSource) async -> Bool {
        do {
            let html = try await SourceEngine.fetchHTML(urlString: result.link)
            let tocPattern = source.rules.tocPattern ?? source.rules.listPattern
            let toc = SourceEngine.extractLinks(
                html: html,
                pattern: tocPattern,
                titleGroup: source.rules.titleGroup,
                linkGroup: source.rules.linkGroup,
                baseURL: source.baseURL
            )
            let isComic = source.isComic
            let links = toc.map(\.link)
            let titles = toc.map(\.title)

            var chapters: [Chapter] = []
            var pageImages: [[String]]? = nil

            if isComic {
                pageImages = links.map { _ in [] }
                chapters = titles.enumerated().map { index, title in
                    Chapter(title: title.isEmpty ? "第 \(index + 1) 话" : title, content: "")
                }
            } else {
                chapters = titles.enumerated().map { index, title in
                    Chapter(title: title.isEmpty ? "第 \(index + 1) 章" : title, content: "")
                }
            }

            if chapters.isEmpty {
                chapters = [Chapter(title: result.title, content: "")]
            }

            let book = Book(
                title: result.title,
                author: source.name,
                intro: "来自书源：\(source.name)",
                category: isComic ? "漫画" : "网络书",
                coverTheme: CoverTheme.allCases.randomElement() ?? .teal,
                chapters: chapters,
                kind: isComic ? .comic : .novel,
                sourceID: source.id,
                chapterLinks: links.isEmpty ? [result.link] : links,
                pageImages: pageImages
            )
            add(book)
            return true
        } catch {
            await MainActor.run {
                lastError = "加入书架失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - 私有

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension UIImage {
    /// 等比缩放，限制最长边，避免原图过大撑爆沙盒
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        return UIGraphicsImageRenderer(size: target).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
