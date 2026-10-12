import SwiftUI
import UIKit

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
    case curl, horizontal, scroll

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curl: return "仿真翻页"
        case .horizontal: return "左右滑动"
        case .scroll: return "上下滚动"
        }
    }

    var systemImage: String {
        switch self {
        case .curl: return "book"
        case .horizontal: return "arrow.left.and.line.vertical.and.arrow.right"
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

// MARK: - 页面几何

/// 阅读页的几何常量：分页端与渲染端必须共用同一套数值，否则会出现截断或大片空白。
enum ReaderLayout {
    /// 正文左右边距
    static let defaultHorizontalPadding: CGFloat = 20
    /// 页眉（章节名）高度
    static let headerHeight: CGFloat = 40
    /// 页脚（页码 / 时间 / 电量）高度
    static let footerHeight: CGFloat = 30
}

// MARK: - 设置持久化

final class ReadingSettingsStore: ObservableObject {
    private enum Key {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let paragraphSpacing = "reader.paragraphSpacing"
        static let horizontalPadding = "reader.horizontalPadding"
        static let paragraphIndent = "reader.paragraphIndent"
        static let theme = "reader.theme"
        static let mode = "reader.mode"
        static let fontName = "reader.fontName"
        static let brightness = "reader.brightness"
        static let keepAwake = "reader.keepAwake"
        static let showPageFooter = "reader.showPageFooter"
        static let speechRate = "reader.speechRate"
        static let speechPitch = "reader.speechPitch"
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
    @Published var horizontalPadding: CGFloat {
        didSet { defaults.set(Double(horizontalPadding), forKey: Key.horizontalPadding) }
    }
    /// 段首缩进两个字符（关闭时靠段间距区分段落）
    @Published var paragraphIndent: Bool {
        didSet { defaults.set(paragraphIndent, forKey: Key.paragraphIndent) }
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
    /// 听书语速（AVSpeechUtteranceRate，0.1 ~ 1.0，0.5 为正常）
    @Published var speechRate: Float {
        didSet { defaults.set(Double(speechRate), forKey: Key.speechRate) }
    }
    /// 听书语调（0.5 ~ 2.0，1.0 为正常）
    @Published var speechPitch: Float {
        didSet { defaults.set(Double(speechPitch), forKey: Key.speechPitch) }
    }

    /// 每次影响分页的参数变化都会让签名改变，用于触发重新分页
    var layoutSignature: String {
        [
            String(format: "%.1f", fontSize),
            String(format: "%.2f", lineSpacing),
            String(format: "%.2f", paragraphSpacing),
            fontOption.id,
            paragraphIndent ? "indent" : "flat",
            theme.rawValue
        ].joined(separator: "|")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.fontSize: 18.0,
            Key.lineSpacing: 9.0,
            Key.paragraphSpacing: 12.0,
            Key.horizontalPadding: 20.0,
            Key.paragraphIndent: true,
            Key.theme: ReaderTheme.paper.rawValue,
            Key.mode: PageTurnMode.curl.rawValue,
            Key.fontName: "PingFang SC",
            Key.brightness: 1.0,
            Key.keepAwake: true,
            Key.showPageFooter: true,
            Key.speechRate: 0.5,
            Key.speechPitch: 1.0
        ])

        self.fontSize = CGFloat(defaults.double(forKey: Key.fontSize))
        self.lineSpacing = CGFloat(defaults.double(forKey: Key.lineSpacing))
        self.paragraphSpacing = CGFloat(defaults.double(forKey: Key.paragraphSpacing))
        let savedPadding = defaults.object(forKey: Key.horizontalPadding) as? Double ?? 20.0
        self.horizontalPadding = CGFloat(savedPadding)
        self.paragraphIndent = defaults.object(forKey: Key.paragraphIndent) as? Bool ?? true
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .paper
        self.pageTurnMode = PageTurnMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .curl
        let savedFont = defaults.string(forKey: Key.fontName) ?? "PingFang SC"
        self.fontOption = ReaderFontOption.available.first { $0.id == savedFont } ?? ReaderFontOption.available[0]
        let savedBrightness = defaults.object(forKey: Key.brightness) as? Double ?? 1.0
        self.brightness = savedBrightness
        self.keepScreenAwake = defaults.bool(forKey: Key.keepAwake)
        self.showPageFooter = defaults.bool(forKey: Key.showPageFooter)
        let savedRate = defaults.object(forKey: Key.speechRate) as? Double ?? 0.5
        self.speechRate = Float(savedRate)
        let savedPitch = defaults.object(forKey: Key.speechPitch) as? Double ?? 1.0
        self.speechPitch = Float(savedPitch)
    }

    /// 恢复默认排版（不清空书源与书架）
    func resetToDefaults() {
        fontSize = 18
        lineSpacing = 9
        paragraphSpacing = 12
        horizontalPadding = ReaderLayout.defaultHorizontalPadding
        paragraphIndent = true
        theme = .paper
        pageTurnMode = .curl
        brightness = 1.0
        keepScreenAwake = true
        showPageFooter = true
    }

    // MARK: 排版

    /// 生成正文富文本样式。
    ///
    /// ⚠️ 这里**故意不做 UIFontMetrics 缩放**：用户拖字号滑块就是要那个精确值，
    /// 再叠一层 Dynamic Type 缩放会让实际显示字号比滑块大（v1.1"一页字少"的根因之一）。
    /// 渲染端 ReaderPageView 也已把 adjustsFontForContentSizeCategory 关掉，两边一致。
    func bodyAttributes() -> [NSAttributedString.Key: Any] {
        let base = fontOption.font(ofSize: fontSize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.paragraphSpacingBefore = 0
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.firstLineHeadIndent = 0
        paragraph.hyphenationFactor = 0

        return [
            .font: base,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor(named: theme.textAsset) ?? .label
        ]
    }

    /// 段首缩进量：两个字符宽；关闭缩进时为 0
    var paragraphIndentWidth: CGFloat {
        paragraphIndent ? fontSize * 2 : 0
    }
}
