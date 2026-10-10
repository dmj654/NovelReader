import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: ReadingSettingsStore

    @StateObject private var viewModel: ReaderViewModel
    @State private var showContents = false
    @State private var showSettings = false

    private let book: Book

    init(book: Book, library: LibraryStore, settings: ReadingSettingsStore) {
        self.book = book
        _viewModel = StateObject(wrappedValue: ReaderViewModel(book: book, library: library, settings: settings))
    }

    private var backgroundColor: UIColor {
        UIColor(named: settings.theme.backgroundAsset) ?? (settings.theme.colorScheme == .dark ? .black : .white)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(uiColor: backgroundColor)
                    .ignoresSafeArea()

                content(in: proxy.size)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggleChrome() }

                chrome(size: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                viewModel.updatePageSize(pageBodySize(for: newSize))
            }
            .onChange(of: settings.layoutSignature) { _, _ in
                viewModel.invalidateLayout()
            }
            .onChange(of: viewModel.currentIndex) { _, _ in
                viewModel.persist()
            }
            .task {
                viewModel.onAppear()
                viewModel.updatePageSize(pageBodySize(for: proxy.size))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $showContents) {
            ContentsSheet(
                chapters: viewModel.book.chapters,
                activeChapterIndex: viewModel.activeChapterIndex,
                onSelect: { index in
                    viewModel.jump(toChapter: index)
                    showContents = false
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet()
                .environmentObject(settings)
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: - 正文

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch settings.pageTurnMode {
        case .curl:
            if viewModel.pages.isEmpty {
                ReadingSkeleton()
            } else {
                PagedReader(
                    pages: viewModel.pages,
                    backgroundColor: backgroundColor,
                    currentIndex: Binding(
                        get: { viewModel.currentIndex },
                        set: { viewModel.jump(toGlobal: $0) }
                    )
                )
                .ignoresSafeArea(edges: .bottom)
            }
        case .scroll:
            ScrollReaderView(viewModel: viewModel, backgroundColor: backgroundColor)
        }
    }

    /// 页面正文可用尺寸：左右各留 24pt，上下预留页眉页脚
    private func pageBodySize(for size: CGSize) -> CGSize {
        let width = max(size.width - 48, 1)
        let height = max(size.height - 96, 1)
        return CGSize(width: width, height: height)
    }

    // MARK: - 浮层工具条

    @ViewBuilder
    private func chrome(size: CGSize) -> some View {
        if viewModel.isChromeVisible {
            VStack(spacing: 0) {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.persist()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("返回书架")

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(viewModel.currentPage?.chapterTitle ?? viewModel.book.chapters.first?.title ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    viewModel.goToPreviousChapter()
                } label: {
                    Label("上一章", systemImage: "arrow.up")
                }
                .disabled(viewModel.activeChapterIndex == 0)

                Button {
                    viewModel.goToNextChapter()
                } label: {
                    Label("下一章", systemImage: "arrow.down")
                }
                .disabled(viewModel.activeChapterIndex >= viewModel.book.chapters.count - 1)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("章节操作")
        }
        .padding(.horizontal, 8)
        .background(.bar)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text(viewModel.percentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(viewModel.currentIndex + 1) / \(max(viewModel.pages.count, 1))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            if viewModel.pages.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(viewModel.currentIndex) },
                        set: { viewModel.jump(toGlobal: Int($0.rounded())) }
                    ),
                    in: 0...Double(max(viewModel.pages.count - 1, 1))
                )
                .tint(.accentColor)
                .padding(.horizontal, 24)
                .accessibilityLabel("阅读进度")
                .accessibilityValue(viewModel.percentText)
            }

            HStack(spacing: 0) {
                toolButton("目录", systemImage: "list.bullet") {
                    showContents = true
                }
                toolButton(settings.theme == .night ? "日间" : "夜间", systemImage: settings.theme == .night ? "sun.max" : "moon") {
                    settings.theme = settings.theme == .night ? .paper : .night
                }
                toolButton("字号", systemImage: "textformat.size") {
                    showSettings = true
                }
                toolButton("设置", systemImage: "gearshape") {
                    showSettings = true
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(.bar)
    }

    private func toolButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption2)
            }
            .frame(minWidth: 60, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - 滚动模式

private struct ScrollReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let backgroundColor: UIColor

    @State private var scrolledChapterID: UUID?
    @EnvironmentObject private var settings: ReadingSettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(Array(viewModel.book.chapters.enumerated()), id: \.element.id) { index, chapter in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(chapter.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(uiColor: UIColor(named: settings.theme.textAsset) ?? .label))

                        ChapterScrollTextView(
                            attributedText: attributed(chapter.content),
                            backgroundColor: .clear
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(chapter.id)
                    .padding(.horizontal, 24)
                    .padding(.top, index == 0 ? 24 : 0)
                    .onAppear { syncProgress(for: index) }
                }
            }
            .scrollTargetLayout()
        }
        .background(Color(uiColor: backgroundColor).ignoresSafeArea())
        .scrollPosition(id: $scrolledChapterID, anchor: .top)
        .onAppear {
            scrolledChapterID = viewModel.book.chapters.indices.contains(viewModel.activeChapterIndex)
                ? viewModel.book.chapters[viewModel.activeChapterIndex].id
                : viewModel.book.chapters.first?.id
        }
    }

    private func attributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: settings.bodyAttributes())
    }

    private func syncProgress(for chapterIndex: Int) {
        guard viewModel.activeChapterIndex != chapterIndex else { return }
        viewModel.jump(toChapter: chapterIndex)
    }
}

// MARK: - 骨架屏（不使用全屏 spinner）

private struct ReadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 14)
                    .frame(maxWidth: index % 4 == 3 ? 240 : .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 80)
        .redacted(reason: .placeholder)
        .accessibilityLabel("正在排版正文")
    }
}
