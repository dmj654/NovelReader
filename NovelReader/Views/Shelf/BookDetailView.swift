import SwiftUI
import UniformTypeIdentifiers

struct BookDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: ReadingSettingsStore

    let book: Book
    let onStartReading: () -> Void

    @State private var introExpanded = false
    @State private var shareItem: ShareItem?
    @State private var showDeleteConfirm = false
    @State private var showComicReader = false

    /// 用包装类型替代 `URL: @retroactive Identifiable`，兼容 Swift 5.9 / 6 两种编译器
    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var current: Book { library.book(withID: book.id) ?? book }
    private var progress: ReadingProgress { library.progress(for: book.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                actionRow
                Divider().padding(.horizontal, 20)
                introSection
                chaptersSection
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        if let url = Exporter.writeTXT(for: current) {
                            shareItem = ShareItem(url: url)
                        }
                    } label: {
                        Label("导出为 TXT", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        library.markFinished(current, finished: !current.isFinished)
                    } label: {
                        Label(current.isFinished ? "标记为在读" : "标记为已读完", systemImage: current.isFinished ? "book" : "checkmark")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("移出书架", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .confirmationDialog("确定移出书架？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("移出书架", role: .destructive) {
                library.remove(current)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("阅读进度也会一并清除。")
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showComicReader) {
            ComicReaderView(book: current)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverView(book: current, progress: progress)
                .frame(width: 110)

            VStack(alignment: .leading, spacing: 8) {
                Text(current.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(current.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TagView(text: current.category)
                    TagView(text: current.isComic ? "\(current.chapterCount) 话" : current.wordCount.formatted() + " 字")
                }

                Text(progress.percent > 0 ? "已读 \(progress.percentText)" : "尚未开始")
                    .font(.caption)
                    .foregroundStyle(progress.percent > 0 ? Color.accentColor : Color.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 操作

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                if current.isComic {
                    showComicReader = true
                } else {
                    onStartReading()
                }
            } label: {
                Label(
                    current.isComic ? "开始阅读" : (progress.percent > 0 ? "继续阅读" : "开始阅读"),
                    systemImage: current.isComic ? "photo.on.rectangle" : "book.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                if let url = Exporter.writeTXT(for: current) {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("导出为 TXT")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 简介

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("简介")
                .font(.headline)
            Text(current.intro.isEmpty ? "这本书还没有简介。" : current.intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(introExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            Button(introExpanded ? "收起" : "展开") {
                withAnimation(.easeInOut(duration: 0.2)) { introExpanded.toggle() }
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 章节预览

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("目录")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("共 \(current.chapterCount) 章")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(current.chapters.prefix(6).enumerated()), id: \.element.id) { index, chapter in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .leading)
                    Text(chapter.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if index == progress.chapterIndex && progress.percent > 0 {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 6)
            }

            if current.chapterCount > 6 {
                Button {
                    onStartReading()
                } label: {
                    Text("查看完整目录")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 组件

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .accessibilityLabel(text)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - 导出

enum Exporter {
    static func writeTXT(for book: Book) -> URL? {
        var text = "\(book.title)\n作者：\(book.author)\n\n"
        for chapter in book.chapters {
            text += "\n\(chapter.title)\n\n\(chapter.content)\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(book.title).txt", isDirectory: false)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
