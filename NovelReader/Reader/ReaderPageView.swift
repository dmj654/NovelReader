import SwiftUI

/// 单页正文渲染。使用 UITextView 而非 SwiftUI Text，保证与 TextKit 分页结果像素级一致。
struct ReaderPageView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.backgroundColor = backgroundColor
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityTraits = .staticText
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedText
        textView.backgroundColor = backgroundColor
    }
}

/// 滚动模式下的整章渲染（可选中、可复制、支持系统字号）
struct ChapterScrollTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedText
        textView.invalidateIntrinsicContentSize()
    }
}
