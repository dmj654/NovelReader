import SwiftUI

/// 底部浮层提示：任何操作结束后都用它给出明确结果，避免"点了没反应"。
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let text = message {
                    Text(text)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(nanoseconds: 2_600_000_000)
                            self.message = nil
                        }
                }
            }
            .animation(.easeInOut, value: message)
    }
}

/// 导入/解析中的忙碌态遮罩
struct BusyOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }

    func busyOverlay(isPresented: Bool, title: String) -> some View {
        overlay {
            if isPresented {
                BusyOverlay(title: title)
            }
        }
    }
}
