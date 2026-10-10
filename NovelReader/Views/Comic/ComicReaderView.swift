import SwiftUI
import UIKit

/// 漫画阅读器：竖向图片流 + 章节切换，与小说阅读器分开管理。
struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var library: LibraryStore

    let bookID: UUID

    @State private var book: Book
    @State private var chapterIndex = 0
    @State private var imageURLs: [String] = []
    @State private var isLoadingImages = false
    @State private var showChapterList = false

    init(book: Book) {
        _book = State(initialValue: book)
        self.bookID = book.id
    }

    private var currentChapterTitle: String {
        book.chapters.indices.contains(chapterIndex)
            ? book.chapters[chapterIndex].title
            : "第 \(chapterIndex + 1) 话"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                imageList
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showChapterList) {
            ComicChapterList(
                chapters: book.chapters,
                activeIndex: chapterIndex,
                onSelect: { index in
                    chapterIndex = index
                    showChapterList = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .task(id: chapterIndex) {
            await loadChapterIfNeeded()
        }
    }

    // MARK: - 顶部工具条

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回书架")

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(currentChapterTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                guard chapterIndex > 0 else { return }
                chapterIndex -= 1
            } label: {
                Image(systemName: "backward")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .disabled(chapterIndex == 0)
            .accessibilityLabel("上一话")

            Button {
                guard chapterIndex < book.chapters.count - 1 else { return }
                chapterIndex += 1
            } label: {
                Image(systemName: "forward")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .disabled(chapterIndex >= book.chapters.count - 1)
            .accessibilityLabel("下一话")

            Button {
                showChapterList = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("章节目录")
        }
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - 图片流

    private var imageList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                if isLoadingImages {
                    ForEach(0..<4, id: \.self) { _ in
                        placeholder
                    }
                } else if imageURLs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("这一话暂无图片")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 120)
                } else {
                    ForEach(imageURLs, id: \.self) { url in
                        RemoteImage(urlString: url)
                    }
                    endCard
                }
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .aspectRatio(0.66, contentMode: .fit)
            .overlay(ProgressView().tint(.white))
            .padding(.horizontal, 60)
    }

    private var endCard: some View {
        VStack(spacing: 10) {
            Text("本话完")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            if chapterIndex < book.chapters.count - 1 {
                Button {
                    chapterIndex += 1
                } label: {
                    Text("继续下一话")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 数据

    private func loadChapterIfNeeded() async {
        // 已有图片列表（本地漫画 / 之前抓取过）
        if let pages = book.pageImages, book.chapters.indices.contains(chapterIndex),
           pages.indices.contains(chapterIndex), !pages[chapterIndex].isEmpty {
            imageURLs = pages[chapterIndex]
            return
        }

        guard let sourceID = book.sourceID,
              let links = book.chapterLinks, links.indices.contains(chapterIndex),
              let source = library.source(withID: sourceID) else {
            imageURLs = []
            return
        }

        isLoadingImages = true
        defer { isLoadingImages = false }

        do {
            let urls = try await SourceEngine.fetchImageURLs(source: source, link: links[chapterIndex])
            imageURLs = urls
            // 回填到书籍数据，下次离线可见
            if var updated = library.book(withID: bookID) {
                if updated.pageImages == nil { updated.pageImages = [] }
                while (updated.pageImages?.count ?? 0) <= chapterIndex {
                    updated.pageImages?.append([])
                }
                updated.pageImages?[chapterIndex] = urls
                library.update(updated)
                book = updated
            }
        } catch {
            imageURLs = []
        }
    }
}

// MARK: - 单张远程图片

private struct RemoteImage: View {
    let urlString: String

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.white.opacity(0.6))
                    Text("图片加载失败")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .aspectRatio(0.66, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(0.66, contentMode: .fit)
                    .overlay(ProgressView().tint(.white))
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: urlString) {
            guard image == nil else { return }
            if let loaded = await Self.load(urlString) {
                withAnimation(.easeOut(duration: 0.25)) {
                    image = loaded
                }
            } else {
                failed = true
            }
        }
    }

    private static func load(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - 章节列表

private struct ComicChapterList: View {
    @Environment(\.dismiss) private var dismiss

    let chapters: [Chapter]
    let activeIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .foregroundStyle(index == activeIndex ? Color.accentColor : Color.primary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if index == activeIndex {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("共 \(chapters.count) 话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
