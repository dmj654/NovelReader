import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: ReadingSettingsStore

    @State private var searchText = ""
    @State private var isGrid = true
    @State private var showImporter = false
    @State private var showImportTip = false
    @State private var readerBook: Book?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var visibleBooks: [Book] {
        guard !searchText.trimmed.isEmpty else { return library.books }
        return library.books.filter {
            $0.title.localizedCaseInsensitiveContains(searchText.trimmed) ||
            $0.author.localizedCaseInsensitiveContains(searchText.trimmed)
        }
    }

    private var continueBook: Book? {
        library.books.first { library.progress(for: $0.id).globalPageIndex > 0 && !$0.isFinished }
            ?? library.books.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
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
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(
                                    title: "全部藏书",
                                    subtitle: "\(library.books.count) 本",
                                    isGrid: $isGrid
                                )

                                if isGrid {
                                    LazyVGrid(columns: columns, spacing: 20) {
                                        ForEach(visibleBooks) { book in
                                            NavigationLink(value: book.id) {
                                                BookCoverView(book: book, progress: library.progress(for: book.id))
                                            }
                                            .buttonStyle(.plain)
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
                                            .buttonStyle(.plain)
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
            .navigationTitle("书架")
            .searchable(text: $searchText, prompt: "搜索书名或作者")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入本地小说")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let book = library.book(withID: id) {
                    BookDetailView(book: book) { readerBook = book }
                } else {
                    ContentUnavailableView("书籍不存在", systemImage: "book.closed")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .text]) { result in
                switch result {
                case .success(let url):
                    library.importBook(from: url)
                    if library.lastError != nil { showImportTip = true }
                case .failure(let error):
                    library.lastError = error.localizedDescription
                    showImportTip = true
                }
            }
            .alert("导入失败", isPresented: $showImportTip) {
                Button("好", role: .cancel) {}
            } message: {
                Text(library.lastError ?? "未知错误")
            }
            .fullScreenCover(item: $readerBook) { book in
                ReaderView(book: book, library: library, settings: settings)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("书架还是空的")
                    .font(.headline)
                Text("内置示例已就绪，也可以导入本地 TXT 小说。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showImporter = true
            } label: {
                Label("导入 TXT", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
