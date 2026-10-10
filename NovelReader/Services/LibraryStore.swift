import SwiftUI
import Combine

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

    /// 导入本地 txt/epub(仅取 txt 部分暂不支持，返回失败) 文件
    func importBook(from url: URL) {
        do {
            let book = try NovelParser.parse(fileURL: url)
            guard !book.chapters.isEmpty else {
                lastError = "文件中没有可读内容。"
                return
            }
            add(book)
        } catch {
            lastError = error.localizedDescription
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
