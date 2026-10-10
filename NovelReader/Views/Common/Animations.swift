import SwiftUI

/// 按压缩放按钮样式：用于书架封面、列表行等可点击卡片
struct ScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 内容块出现动画：淡入 + 轻微上移，尊重「减弱动态效果」
struct FadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(.easeOut(duration: 0.35).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeIn(delay: delay))
    }
}
