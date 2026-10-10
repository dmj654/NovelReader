import Foundation

/// 书源：用「正则捕获组」描述搜索 / 目录 / 正文 / 图片的提取规则。
/// 规则全部基于正则，不依赖第三方 HTML 解析库，导入导出为 JSON。
struct BookSource: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    /// 站点根地址，用于把相对链接转成绝对链接
    var baseURL: String
    /// 搜索地址模板，含 {query} 与 {page} 占位符
    /// 例：https://example.com/search?q={query}&p={page}
    var searchTemplate: String
    /// 该源提供的是小说还是漫画
    var isComic: Bool
    var isEnabled: Bool
    var sortOrder: Int
    var rules: SourceRules
    var lastCheckedAt: Date?
    var lastCheckSucceeded: Bool?

    init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        searchTemplate: String,
        isComic: Bool = false,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        rules: SourceRules,
        lastCheckedAt: Date? = nil,
        lastCheckSucceeded: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.searchTemplate = searchTemplate
        self.isComic = isComic
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.rules = rules
        self.lastCheckedAt = lastCheckedAt
        self.lastCheckSucceeded = lastCheckSucceeded
    }
}

/// 提取规则（全部为正则表达式 + 捕获组序号，从 1 开始）
struct SourceRules: Codable, Hashable {
    /// 搜索结果分块：每个匹配 = 一条结果
    var listPattern: String
    /// 标题所在的捕获组序号
    var titleGroup: Int
    /// 链接所在的捕获组序号
    var linkGroup: Int
    /// 目录分块（缺省时沿用 listPattern）
    var tocPattern: String?
    /// 正文捕获组（缺省 = 取整页文本并去标签）
    var contentPattern: String?
    /// 漫画：图片 URL 捕获（对章节页 HTML 应用，每个匹配 = 一张图）
    var imagePattern: String?

    init(
        listPattern: String,
        titleGroup: Int = 1,
        linkGroup: Int = 2,
        tocPattern: String? = nil,
        contentPattern: String? = nil,
        imagePattern: String? = nil
    ) {
        self.listPattern = listPattern
        self.titleGroup = titleGroup
        self.linkGroup = linkGroup
        self.tocPattern = tocPattern
        self.contentPattern = contentPattern
        self.imagePattern = imagePattern
    }

    // JSON 导入容错：字段缺失时取默认值，不整条报废
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listPattern = try c.decodeIfPresent(String.self, forKey: .listPattern) ?? ""
        titleGroup = try c.decodeIfPresent(Int.self, forKey: .titleGroup) ?? 1
        linkGroup = try c.decodeIfPresent(Int.self, forKey: .linkGroup) ?? 2
        tocPattern = try c.decodeIfPresent(String.self, forKey: .tocPattern)
        contentPattern = try c.decodeIfPresent(String.self, forKey: .contentPattern)
        imagePattern = try c.decodeIfPresent(String.self, forKey: .imagePattern)
    }
}
