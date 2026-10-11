import SwiftUI
import UIKit

/// 漫画阅读器：竖向图片流 + 章节切换，与小说阅读器分开管理。
struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    let bookID: UUID

    @State private var book: Book
    @State private var chapterIndex = 0
    @State private var imageURLs: [String] = []
    @State private var isLoadingImages = false
    @State private var loadError: String?
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

    @ViewBuilder
    private var imageList: some View {
        if isLoadingImages {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        placeholder
                    }
                }
            }
        } else if imageURLs.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(imageURLs.enumerated()), id: \.element) { index, url in
                        ComicPageView(urlString: url, pageIndex: index + 1, total: imageURLs.count)
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.5))
            Text(loadError ?? "这一话暂无图片")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await loadChapterIfNeeded(force: true) }
            } label: {
                Label("重新加载", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var endCard: some View {
        VStack(spacing: 10) {
            Text("本话完 · 共 \(imageURLs.count) 页")
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
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 数据

    private func loadChapterIfNeeded(force: Bool = false) async {
        loadError = nil

        // 已有图片列表（本地漫画 / 之前抓取过）
        if !force,
           let pages = book.pageImages,
           book.chapters.indices.contains(chapterIndex),
           pages.indices.contains(chapterIndex),
           !pages[chapterIndex].isEmpty {
            imageURLs = pages[chapterIndex]
            return
        }

        guard let sourceID = book.sourceID,
              let links = book.chapterLinks, links.indices.contains(chapterIndex),
              let source = library.source(withID: sourceID) else {
            imageURLs = []
            loadError = "这一话没有图片来源。本地漫画请从书架右上角 ＋ 导入图片；书源漫画请确认书源的图片规则正确。"
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
            loadError = "图片加载失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 单页图片（支持本地文件 / 内置示例页 / 远程地址）

private struct ComicPageView: View {
    let urlString: String
    let pageIndex: Int
    let total: Int

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if urlString.hasPrefix("art://") {
                ComicArtPage(pageIndex: pageIndex, total: total)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.white.opacity(0.6))
                    Text("第 \(pageIndex) 页加载失败")
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
            guard image == nil, !urlString.hasPrefix("art://") else { return }
            if let loaded = await Self.load(urlString) {
                image = loaded
            } else {
                failed = true
            }
        }
    }

    private static func load(_ urlString: String) async -> UIImage? {
        // 本地导入的漫画：相对沙盒 Documents 的路径
        if urlString.hasPrefix("local://") {
            let relative = String(urlString.dropFirst("local://".count))
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            guard let documents else { return nil }
            let fileURL = documents.appendingPathComponent(relative)
            return UIImage(contentsOfFile: fileURL.path)
        }
        guard let url = URL(string: urlString), url.scheme != nil else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - 内置示例漫画页（纯本地绘制，不联网也能看）

private struct ComicArtPage: View {
    let pageIndex: Int
    let total: Int

    private var palette: [Color] {
        let sets: [[Color]] = [
            [Color(red: 0.36, green: 0.58, blue: 0.92), Color(red: 0.86, green: 0.93, blue: 0.99)],
            [Color(red: 0.98, green: 0.66, blue: 0.42), Color(red: 0.99, green: 0.92, blue: 0.80)],
            [Color(red: 0.30, green: 0.42, blue: 0.48), Color(red: 0.85, green: 0.90, blue: 0.88)]
        ]
        return sets[(pageIndex - 1) / 4 % sets.count]
    }

    private var symbol: String {
        let symbols = ["cloud.sun.fill", "house.fill", "wind", "lightbulb.fill", "moon.stars.fill", "bicycle"]
        return symbols[(pageIndex - 1) % symbols.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .top, endPoint: .bottom)

            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 84))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 8)
                Text("第 \(pageIndex) 页")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("内置示例画面")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 8)
                    Text("\(pageIndex) / \(total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.25), in: Capsule())
                        .padding(12)
                }
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .frame(maxWidth: .infinity)
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
