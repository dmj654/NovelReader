import SwiftUI
import UIKit

/// 单页正文渲染。使用 UITextView 而非 SwiftUI Text，保证与 TextKit 分页结果像素级一致。
///
/// 重要：iOS 16 起 UITextView 默认使用 TextKit 2，与分页端（TextKit 1 的 NSLayoutManager）
/// 行距/段距计算不一致，会出现"一页只有两三行 + 巨大空白"的排版错乱。
/// 访问 `layoutManager` 属性会让 UITextView 回退到 TextKit 1（Apple 文档行为），
/// 这里显式触发，保证渲染与分页使用同一套排版引擎。
///
/// 另外：字号已在 NSAttributedString 里用 UIFontMetrics 缩放过，
/// 必须关闭 adjustsFontForContentSizeCategory，否则会二次缩放导致与分页结果不符。
struct ReaderPageView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let backgroundColor: UIColor
    /// 当前页内需要高亮的区间（相对本页文本，用于听书跟读）
    var highlightRange: NSRange? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.bounces = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.backgroundColor = backgroundColor
        // 字号已由 UIFontMetrics 处理，禁止 TextView 再缩放一次
        textView.adjustsFontForContentSizeCategory = false
        textView.clipsToBounds = true
        textView.accessibilityTraits = .staticText

        // 强制回退 TextKit 1，与 ChapterPaginator 的分页引擎保持一致
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.layoutManager.usesFontLeading = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if let highlightRange, highlightRange.length > 0,
           NSMaxRange(highlightRange) <= attributedText.length {
            let highlighted = NSMutableAttributedString(attributedString: attributedText)
            let color = UIColor(named: "AccentColor")?.withAlphaComponent(0.30)
                ?? UIColor.systemYellow.withAlphaComponent(0.30)
            highlighted.addAttribute(.backgroundColor, value: color, range: highlightRange)
            textView.attributedText = highlighted
        } else {
            textView.attributedText = attributedText
        }
        textView.backgroundColor = backgroundColor
    }
}

/// 滚动模式下的整章渲染（可选中、可复制）
struct ChapterScrollTextView: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.bounces = false
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = false
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.layoutManager.usesFontLeading = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedText
        textView.invalidateIntrinsicContentSize()
    }
}
