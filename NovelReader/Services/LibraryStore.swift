import SwiftUI
import Combine

/// 书架数据中枢：书籍与阅读进度的持久化、增删改、txt 导入。
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var progress: [UUID: ReadingProgress] = [:]
    @Published var lastError: String?

    private let fileManager = FileManager.default
    private let booksURL: URL
    private let progressURL: URL

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.booksURL = documents.appendingPathComponent("shelf.json", isDirectory: false)
        self.progressURL = documents.appendingPathComponent("progress.json", isDirectory: false)
    }

    // MARK: - 读写

    func load() {
        if books.isEmpty {
            books = Self.decode([Book].self, from: booksURL) ?? SampleLibrary.books
        }
        progress = Self.decode([UUID: ReadingProgress].self, from: progressURL) ?? [:]
    }

    func save() {
        Self.encode(books, to: booksURL)
        Self.encode(progress, to: progressURL)
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
