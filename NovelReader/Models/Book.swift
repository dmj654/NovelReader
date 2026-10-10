import Foundation

// MARK: - 章节

struct Chapter: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var content: String

    /// 章节正文字数（不含标题）
    var wordCount: Int { content.count }

    init(id: UUID = UUID(), title: String, content: String) {
        self.id = id
        self.title = title
        self.content = content
    }
}

// MARK: - 封面配色

/// 封面使用 Asset Catalog 中的语义色，方便自动适配深色模式，避免硬编码色值。
enum CoverTheme: String, Codable, CaseIterable, Identifiable {
    case indigo, teal, amber, rose, slate, moss

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .indigo: return "靛青"
        case .teal: return "松石"
        case .amber: return "琥珀"
        case .rose: return "胭脂"
        case .slate: return "石板"
        case .moss: return "苔绿"
        }
    }

    /// Asset Catalog 中的 Color Set 名称，需在工程内创建同名 Color Set。
    var assetName: String {
        switch self {
        case .indigo: return "CoverIndigo"
        case .teal: return "CoverTeal"
        case .amber: return "CoverAmber"
        case .rose: return "CoverRose"
        case .slate: return "CoverSlate"
        case .moss: return "CoverMoss"
        }
    }
}

// MARK: - 书籍

struct Book: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var author: String
    var intro: String
    var category: String
    var coverTheme: CoverTheme
    var chapters: [Chapter]
    var addedAt: Date
    /// 已完成阅读的标记（用于书架角标）
    var isFinished: Bool

    var wordCount: Int { chapters.reduce(0) { $0 + $1.wordCount } }

    var chapterCount: Int { chapters.count }

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        intro: String = "",
        category: String = "其他",
        coverTheme: CoverTheme = .indigo,
        chapters: [Chapter] = [],
        addedAt: Date = Date(),
        isFinished: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.intro = intro
        self.category = category
        self.coverTheme = coverTheme
        self.chapters = chapters
        self.addedAt = addedAt
        self.isFinished = isFinished
    }
}

// MARK: - 阅读进度

struct ReadingProgress: Codable, Hashable {
    var chapterIndex: Int
    /// 该章节内的页码（滚动模式同样使用分页结果换算，保证进度条一致）
    var pageIndex: Int
    /// 全局页码（用于进度条与百分比）
    var globalPageIndex: Int
    var totalPages: Int
    var updatedAt: Date

    static let zero = ReadingProgress(
        chapterIndex: 0,
        pageIndex: 0,
        globalPageIndex: 0,
        totalPages: 1,
        updatedAt: Date()
    )

    var percent: Double {
        guard totalPages > 1 else { return 0 }
        return Double(globalPageIndex + 1) / Double(totalPages)
    }

    var percentText: String {
        String(format: "%.0f%%", percent * 100)
    }
}
