import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: ReadingSettingsStore

    @State private var searchText = ""
    @State private var isGrid = true
    @State private var showImporter = false
    @State private var showImageImporter = false
    @State private var readerBook: Book?
    @State private var importMessage: String?
    @State private var isImporting = false
    @State private var pendingImageURLs: [URL] = []
    @State private var comicTitle = ""
    @State private var showComicNamePrompt = false
    /// 书架分区：小说与漫画分开管理
    @State private var section: BookKind = .novel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var visibleBooks: [Book] {
        let base = library.books.filter { ($0.kind ?? .novel) == section }
        guard !searchText.trimmed.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText.trimmed) ||
            $0.author.localizedCaseInsensitiveContains(searchText.trimmed)
        }
    }

    private var continueBook: Book? {
        guard section == .novel else { return nil }
        return library.books.first { ($0.kind ?? .novel) == .novel && library.progress(for: $0.id).globalPageIndex > 0 && !$0.isFinished }
    }

    var body: some View {
        NavigationStack {
            bookList
            .navigationTitle("书架")
            .searchable(text: $searchText, prompt: section == .comic ? "搜索漫画" : "搜索书名或作者")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("分区", selection: $section) {
                    ForEach(BookKind.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
                .onChange(of: section) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) { searchText = "" }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if section == .comic {
                            showImageImporter = true
                        } else {
                            showImporter = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(section == .comic ? "导入本地图片" : "导入本地小说")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let book = library.book(withID: id) {
                    BookDetailView(book: book) { readerBook = book }
                } else {
                    ContentUnavailableView("书籍不存在", systemImage: "book.closed")
                }
            }
            // 小说：TXT 导入（放宽类型，任何文件都能选，解析失败会给明确提示）
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .text, .data]) { result in
                switch result {
                case .success(let url):
                    Task { await importNovel(from: url) }
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
            // 漫画：多选本地图片
            .fileImporter(
                isPresented: $showImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    pendingImageURLs = urls
                    comicTitle = defaultComicTitle
                    showComicNamePrompt = true
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
            .alert("给这本漫画起个名字", isPresented: $showComicNamePrompt) {
                TextField("名称", text: $comicTitle)
                Button("导入") {
                    Task { await importComic() }
                }
                Button("取消", role: .cancel) {
                    pendingImageURLs = []
                }
            } message: {
                Text("已选中 \(pendingImageURLs.count) 张图片，按选中顺序排列。")
            }
            .toast($importMessage)
            .busyOverlay(isPresented: isImporting, title: section == .comic ? "正在导入图片…" : "正在解析文件…")
            .fullScreenCover(item: $readerBook) { book in
                if book.isComic {
                    ComicReaderView(book: book)
                } else {
                    ReaderView(book: book, library: library, settings: settings)
                }
            }
        }
    }

    // MARK: - 列表

    @ViewBuilder
    private var bookList: some View {
        if visibleBooks.isEmpty && searchText.trimmed.isEmpty {
            emptyState
        } else if visibleBooks.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let continueBook, searchText.trimmed.isEmpty {
                        ContinueCard(book: continueBook) {
                            readerBook = continueBook
                        }
                        .fadeIn()
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(
                            title: section == .novel ? "全部藏书" : "全部漫画",
                            subtitle: "\(visibleBooks.count) 本",
                            isGrid: $isGrid
                        )

                        if isGrid {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(visibleBooks) { book in
                                    NavigationLink(value: book.id) {
                                        BookCoverView(book: book, progress: library.progress(for: book.id))
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            library.remove(book)
                                        } label: {
                                            Label("移出书架", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleBooks) { book in
                                    NavigationLink(value: book.id) {
                                        BookRowView(book: book, progress: library.progress(for: book.id))
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - 导入动作

    private func importNovel(from url: URL) async {
        isImporting = true
        let outcome = await library.importBook(from: url)
        isImporting = false
        importMessage = outcome.message
    }

    private func importComic() async {
        let urls = pendingImageURLs
        pendingImageURLs = []
        isImporting = true
        let outcome = await library.importComic(title: comicTitle, imageURLs: urls)
        isImporting = false
        importMessage = outcome.message
    }

    private var defaultComicTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "我的漫画 \(formatter.string(from: Date()))"
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: section == .comic ? "photo.on.rectangle.angled" : "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(section == .comic ? "还没有漫画" : "书架还是空的")
                    .font(.headline)
                Text(section == .comic
                     ? "点下面的按钮，从相册或「文件」里选一组图片，就能当漫画看。"
                     : "内置示例已就绪，也可以导入本地 TXT 小说。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Button {
                if section == .comic {
                    showImageImporter = true
                } else {
                    showImporter = true
                }
            } label: {
                Label(section == .comic ? "导入图片" : "导入 TXT", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if section == .novel {
                Text("支持 UTF-8 / GBK / UTF-16 编码，章节自动识别")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - 继续阅读卡片

private struct ContinueCard: View {
    let book: Book
    let action: () -> Void

    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                BookCoverView(book: book, progress: library.progress(for: book.id), size: .small)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("读到 \(library.progress(for: book.id).percentText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(book.intro.isEmpty ? "暂无简介" : book.intro)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("继续阅读 \(book.title)")
        .accessibilityHint("已读 \(library.progress(for: book.id).percentText)")
    }
}

// MARK: - 区块标题

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    @Binding var isGrid: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isGrid.toggle() }
            } label: {
                Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isGrid ? "切换为列表" : "切换为网格")
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
