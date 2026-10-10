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

// MARK: - 书籍类型

/// 小说与漫画分开管理
enum BookKind: String, Codable, CaseIterable, Identifiable {
    case novel, comic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .novel: return "小说"
        case .comic: return "漫画"
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
    /// 书籍类型（nil 视为小说，兼容旧数据）
    var kind: BookKind?
    /// 网络书：所属书源 id（本地书为 nil）
    var sourceID: String?
    /// 网络书：每章对应的链接（小说=正文页；漫画=该话图片页）
    var chapterLinks: [String]?
    /// 漫画：每话的图片 URL 列表（本地漫画直接填 URL；网络漫画抓取后回填）
    var pageImages: [[String]]?

    var wordCount: Int { chapters.reduce(0) { $0 + $1.wordCount } }

    var chapterCount: Int { chapters.count }

    var isComic: Bool { kind == .comic }

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        intro: String = "",
        category: String = "其他",
        coverTheme: CoverTheme = .indigo,
        chapters: [Chapter] = [],
        addedAt: Date = Date(),
        isFinished: Bool = false,
        kind: BookKind? = nil,
        sourceID: String? = nil,
        chapterLinks: [String]? = nil,
        pageImages: [[String]]? = nil
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
        self.kind = kind
        self.sourceID = sourceID
        self.chapterLinks = chapterLinks
        self.pageImages = pageImages
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
