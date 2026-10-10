import SwiftUI

/// 书封：语义色渐变 + 书名 + 作者 + 进度条；不使用硬编码色值。
struct BookCoverView: View {
    enum Size {
        case small, regular

        var width: CGFloat { self == .small ? 64 : 110 }
        var titleFont: Font { self == .small ? .caption.weight(.semibold) : .subheadline.weight(.semibold) }
        var authorFont: Font { self == .small ? .caption2 : .caption }
    }

    let book: Book
    let progress: ReadingProgress
    var size: Size = .regular

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var aspectRatio: CGFloat { 3.0 / 4.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            metadata
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，作者 \(book.author)，已读 \(progress.percentText)")
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 书脊压线，仅作装饰
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: size == .small ? 4 : 8) {
                Text(book.title)
                    .font(size.titleFont)
                    .foregroundStyle(Color.white)
                    .lineLimit(size == .small ? 2 : 3)
                    .minimumScaleFactor(0.8)
                if size != .small {
                    Text(book.author)
                        .font(size.authorFont)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(size == .small ? 8 : 12)
            .padding(.leading, 4)

            if book.isFinished {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Text("已读完")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.35), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .padding(size == .small ? 6 : 8)
            }
        }
        .frame(width: size.width, height: size.width / aspectRatio)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if progress.percent > 0, !book.isFinished {
                ProgressView(value: progress.percent)
                    .tint(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var metadata: some View {
        if size != .small {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(progress.percent > 0 ? progress.percentText : "\(book.chapterCount) 章")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: size.width, alignment: .leading)
        }
    }

    private var gradientColors: [Color] {
        let base = Color(book.coverTheme.assetName)
        return [base, base.opacity(0.72)]
    }
}

/// 列表形态的书目行
struct BookRowView: View {
    let book: Book
    let progress: ReadingProgress

    var body: some View {
        HStack(spacing: 14) {
            BookCoverView(book: book, progress: progress, size: .small)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(book.author) · \(book.chapterCount) 章 · \(book.wordCount.formatted()) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(progress.percent > 0 ? "已读 \(progress.percentText)" : "未开始")
                    .font(.caption2)
                    .foregroundStyle(progress.percent > 0 ? Color.accentColor : Color.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，作者 \(book.author)，已读 \(progress.percentText)")
    }
}
