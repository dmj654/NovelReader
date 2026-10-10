import SwiftUI

// MARK: - 阅读主题

/// 全部使用 Asset Catalog 语义色（Any Appearance / Dark 各一份），禁止硬编码色值。
enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case paper, cream, moss, ink, night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paper: return "纯白"
        case .cream: return "米黄"
        case .moss: return "护眼"
        case .ink: return "水墨"
        case .night: return "夜间"
        }
    }

    /// 页面背景色（Color Set 名称）
    var backgroundAsset: String {
        switch self {
        case .paper: return "ReaderPaperBackground"
        case .cream: return "ReaderCreamBackground"
        case .moss:  return "ReaderMossBackground"
        case .ink:   return "ReaderInkBackground"
        case .night: return "ReaderNightBackground"
        }
    }

    /// 正文文字色（Color Set 名称）
    var textAsset: String {
        switch self {
        case .paper: return "ReaderPaperText"
        case .cream: return "ReaderCreamText"
        case .moss:  return "ReaderMossText"
        case .ink:   return "ReaderInkText"
        case .night: return "ReaderNightText"
        }
    }

    /// 次要素描色（页眉、页脚、页码）
    var secondaryTextAsset: String { "ReaderSecondaryText" }

    var colorScheme: ColorScheme {
        switch self {
        case .night, .ink: return .dark
        default: return .light
        }
    }
}

// MARK: - 翻页方式

enum PageTurnMode: String, Codable, CaseIterable, Identifiable {
    case curl, scroll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curl: return "仿真翻页"
        case .scroll: return "上下滚动"
        }
    }

    var systemImage: String {
        switch self {
        case .curl: return "book"
        case .scroll: return "arrow.up.arrow.down"
        }
    }
}

// MARK: - 正文字体

struct ReaderFontOption: Identifiable, Hashable {
    let id: String          // UIFont 家族名
    let displayName: String

    static let available: [ReaderFontOption] = {
        let candidates: [(String, String)] = [
            ("PingFang SC", "苹方"),
            ("Songti SC", "宋体"),
            ("Kaiti SC", "楷体"),
            ("Heiti SC", "黑体"),
            ("Yuanti SC", "圆体")
        ]
        let families = Set(UIFont.familyNames)
        let picked = candidates.filter { families.contains($0.0) }
        return picked.isEmpty ? [ReaderFontOption(id: "PingFang SC", displayName: "系统")] :
            picked.map { ReaderFontOption(id: $0.0, displayName: $0.1) }
    }()

    /// 取该家族下的 Regular 字体，失败时回退到系统字体
    func font(ofSize size: CGFloat) -> UIFont {
        let names = UIFont.fontNames(forFamilyName: id)
        let regular = names.first { !$0.contains("Bold") && !$0.contains("Italic") && !$0.contains("Medium") }
        if let name = regular, let font = UIFont(name: name, size: size) { return font }
        if let first = names.first, let font = UIFont(name: first, size: size) { return font }
        return .systemFont(ofSize: size)
    }
}

// MARK: - 设置持久化

final class ReadingSettingsStore: ObservableObject {
    private enum Key {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let paragraphSpacing = "reader.paragraphSpacing"
        static let theme = "reader.theme"
        static let mode = "reader.mode"
        static let fontName = "reader.fontName"
        static let brightness = "reader.brightness"
        static let keepAwake = "reader.keepAwake"
        static let showPageFooter = "reader.showPageFooter"
    }

    private let defaults: UserDefaults

    @Published var fontSize: CGFloat {
        didSet { defaults.set(Double(fontSize), forKey: Key.fontSize) }
    }
    @Published var lineSpacing: CGFloat {
        didSet { defaults.set(Double(lineSpacing), forKey: Key.lineSpacing) }
    }
    @Published var paragraphSpacing: CGFloat {
        didSet { defaults.set(Double(paragraphSpacing), forKey: Key.paragraphSpacing) }
    }
    @Published var theme: ReaderTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }
    @Published var pageTurnMode: PageTurnMode {
        didSet { defaults.set(pageTurnMode.rawValue, forKey: Key.mode) }
    }
    @Published var fontOption: ReaderFontOption {
        didSet { defaults.set(fontOption.id, forKey: Key.fontName) }
    }
    /// 独立于系统亮度的阅读亮度（0.4 ~ 1.0）
    @Published var brightness: Double {
        didSet { defaults.set(brightness, forKey: Key.brightness) }
    }
    @Published var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Key.keepAwake) }
    }
    @Published var showPageFooter: Bool {
        didSet { defaults.set(showPageFooter, forKey: Key.showPageFooter) }
    }

    /// 每次影响分页的参数变化都会让签名改变，用于触发重新分页并清空页面缓存
    var layoutSignature: String {
        [
            String(format: "%.1f", fontSize),
            String(format: "%.2f", lineSpacing),
            String(format: "%.2f", paragraphSpacing),
            fontOption.id,
            theme.rawValue
        ].joined(separator: "|")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.fontSize: 18.0,
            Key.lineSpacing: 6.0,
            Key.paragraphSpacing: 10.0,
            Key.theme: ReaderTheme.paper.rawValue,
            Key.mode: PageTurnMode.curl.rawValue,
            Key.fontName: "PingFang SC",
            Key.brightness: 1.0,
            Key.keepAwake: true,
            Key.showPageFooter: true
        ])

        self.fontSize = CGFloat(defaults.double(forKey: Key.fontSize))
        self.lineSpacing = CGFloat(defaults.double(forKey: Key.lineSpacing))
        self.paragraphSpacing = CGFloat(defaults.double(forKey: Key.paragraphSpacing))
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .paper
        self.pageTurnMode = PageTurnMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .curl
        let savedFont = defaults.string(forKey: Key.fontName) ?? "PingFang SC"
        self.fontOption = ReaderFontOption.available.first { $0.id == savedFont } ?? ReaderFontOption.available[0]
        let savedBrightness = defaults.object(forKey: Key.brightness) as? Double ?? 1.0
        self.brightness = savedBrightness
        self.keepScreenAwake = defaults.bool(forKey: Key.keepAwake)
        self.showPageFooter = defaults.bool(forKey: Key.showPageFooter)
    }

    // MARK: 排版

    /// 生成正文富文本样式；字号再经 UIFontMetrics 缩放以支持 Dynamic Type
    func bodyAttributes() -> [NSAttributedString.Key: Any] {
        let base = fontOption.font(ofSize: fontSize)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.paragraphSpacingBefore = 0
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.firstLineHeadIndent = 0
        paragraph.hyphenationFactor = 0.6

        return [
            .font: scaled,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor(named: theme.textAsset) ?? .label
        ]
    }
}
