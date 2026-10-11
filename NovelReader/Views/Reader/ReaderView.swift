import SwiftUI
import UIKit

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: ReadingSettingsStore

    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var speech = SpeechController()

    @State private var showContents = false
    @State private var showSettings = false
    @State private var isSpeechMode = false
    @State private var appeared = false

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

                content

                chrome
            }
            .onChange(of: proxy.size) { _, _ in
                viewModel.updatePageSize(pageBodySize(for: proxy.size, insets: proxy.safeAreaInsets))
            }
            .onChange(of: settings.layoutSignature) { _, _ in
                viewModel.invalidateLayout()
            }
            .onChange(of: settings.horizontalPadding) { _, _ in
                viewModel.invalidateLayout()
            }
            .onChange(of: viewModel.currentIndex) { _, _ in
                viewModel.persist()
            }
            .onChange(of: viewModel.activeChapterIndex) { _, newIndex in
                // 手动跳章或听书翻章后：听书模式下从头朗读新章
                if isSpeechMode {
                    restartSpeech(at: newIndex)
                }
                prefetchAround(newIndex)
            }
            .task {
                viewModel.onAppear()
                viewModel.updatePageSize(pageBodySize(for: proxy.size, insets: proxy.safeAreaInsets))
            }
            .task(id: viewModel.activeChapterIndex) {
                // 书源书：进入章节时按需抓取正文
                if viewModel.isNetworkBook {
                    await viewModel.ensureChapterContent(viewModel.activeChapterIndex)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .rotation3DEffect(
            .degrees(appeared ? 0 : -14),
            axis: (x: 0, y: 1, z: 0),
            anchor: .leading,
            perspective: 0.55
        )
        .onAppear {
            // 一章读完 → 跳到下一章；onChange(of: activeChapterIndex) 会自动重新开始朗读。
            // 跳转交给 onChange 重启朗读，这里返回 nil 让合成器先停下。
            speech.onChapterFinish = { next in
                viewModel.jump(toChapter: next)
                return nil
            }
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.38)) { appeared = true }
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
        .onDisappear {
            speech.stop()
            viewModel.onDisappear()
        }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: - 正文

    @ViewBuilder
    private var content: some View {
        if viewModel.pages.isEmpty {
            ReadingSkeleton()
        } else {
            switch settings.pageTurnMode {
            case .curl:
                pagedReader(style: .pageCurl)
            case .horizontal:
                pagedReader(style: .scroll)
            case .scroll:
                ScrollReaderView(viewModel: viewModel, backgroundColor: backgroundColor)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggleChrome() }
            }
        }
    }

    private func pagedReader(style: UIPageViewController.TransitionStyle) -> some View {
        PagedReader(
            pages: viewModel.pages,
            backgroundColor: backgroundColor,
            transitionStyle: style,
            bodyHeight: viewModel.bodyHeight,
            horizontalPadding: settings.horizontalPadding,
            currentIndex: Binding(
                get: { viewModel.currentIndex },
                set: { viewModel.jump(toGlobal: $0) }
            ),
            highlightFor: { pageIndex in
                speechHighlightRange(forPageAt: pageIndex)
            }
        )
        .overlay {
            pageTapRegions
        }
    }

    /// 仿真模式的三区点击：左 = 上翻/上一句，中 = 呼出工具条，右 = 下翻/下一句
    private var pageTapRegions: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleLeadingTap() }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleChrome() }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleTrailingTap() }
        }
        .accessibilityHidden(true)
    }

    private func handleLeadingTap() {
        if isSpeechMode {
            speech.previousSentence()
        } else {
            viewModel.jump(toGlobal: viewModel.currentIndex - 1)
        }
    }

    private func handleTrailingTap() {
        if isSpeechMode {
            speech.nextSentence()
        } else {
            viewModel.jump(toGlobal: viewModel.currentIndex + 1)
        }
    }

    /// 正文可用尺寸：左右边距 + 上下页眉页脚与安全区都已扣除，
    /// 与 ReaderPageContainer 里的实际布局严格一致。
    private func pageBodySize(for size: CGSize, insets: EdgeInsets) -> CGSize {
        let width = max(size.width - settings.horizontalPadding * 2, 1)
        let height = max(
            size.height - insets.top - insets.bottom - ReaderLayout.headerHeight - ReaderLayout.footerHeight,
            1
        )
        return CGSize(width: width, height: height)
    }

    // MARK: - 听书

    /// 把听书高亮（章节内区间）映射为某页内的相对区间
    private func speechHighlightRange(forPageAt pageIndex: Int) -> NSRange? {
        guard isSpeechMode,
              let highlight = speech.highlight,
              viewModel.pages.indices.contains(pageIndex) else { return nil }
        let page = viewModel.pages[pageIndex]
        guard page.chapterIndex == highlight.chapterIndex else { return nil }

        let intersection = NSIntersectionRange(page.rangeInChapter, highlight.range)
        guard intersection.length > 0 else { return nil }
        return NSRange(
            location: intersection.location - page.rangeInChapter.location,
            length: intersection.length
        )
    }

    private func toggleSpeechMode() {
        if isSpeechMode {
            speech.stop()
            isSpeechMode = false
        } else {
            isSpeechMode = true
            startSpeech(at: viewModel.activeChapterIndex)
            if !viewModel.isChromeVisible {
                viewModel.toggleChrome()
            }
        }
    }

    private func startSpeech(at chapterIndex: Int) {
        Task {
            let text = await viewModel.ensureChapterContent(chapterIndex)
                ?? viewModel.book.chapters[safe: chapterIndex]?.content
                ?? ""
            speech.start(
                chapter: chapterIndex,
                text: text,
                rate: settings.speechRate,
                pitch: settings.speechPitch
            )
        }
    }

    private func restartSpeech(at chapterIndex: Int) {
        guard isSpeechMode else { return }
        startSpeech(at: chapterIndex)
    }

    /// 预取相邻章节（网络书），保证一章读完能无缝接下一章
    private func prefetchAround(_ chapterIndex: Int) {
        guard viewModel.isNetworkBook else { return }
        let next = chapterIndex + 1
        Task {
            if viewModel.book.chapters.indices.contains(next) {
                await viewModel.ensureChapterContent(next)
            }
        }
    }

    // MARK: - 浮层工具条

    @ViewBuilder
    private var chrome: some View {
        if viewModel.isChromeVisible {
            VStack(spacing: 0) {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
                if isSpeechMode {
                    speechBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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

    // MARK: 听书控制区

    private var speechBar: some View {
        VStack(spacing: 10) {
            if let remaining = speech.sleepRemainingSeconds {
                Text(String(format: "定时停止：%d 分 %02d 秒后", remaining / 60, remaining % 60))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                speechControlItem("上一句", systemImage: "backward.end.fill") {
                    speech.previousSentence()
                }
                Button {
                    speech.togglePlayPause()
                } label: {
                    Image(systemName: speech.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 34))
                        .frame(width: 60, height: 44)
                }
                .accessibilityLabel(speech.isPaused ? "继续朗读" : "暂停朗读")

                speechControlItem("下一句", systemImage: "forward.end.fill") {
                    speech.nextSentence()
                }

                Divider().frame(height: 28)

                speechControlItem("上一章", systemImage: "backward") {
                    viewModel.goToPreviousChapter()
                }
                speechControlItem("下一章", systemImage: "forward") {
                    viewModel.goToNextChapter()
                }
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(SpeechPreset.speeds) { preset in
                        Button(preset.label) {
                            settings.speechRate = preset.value
                            speech.updateRate(preset.value)
                        }
                    }
                } label: {
                    speechLabel("语速 \(SpeechPreset.speedName(settings.speechRate))")
                }

                Menu {
                    ForEach(SpeechPreset.pitches) { preset in
                        Button(preset.label) {
                            settings.speechPitch = preset.value
                            speech.updatePitch(preset.value)
                        }
                    }
                } label: {
                    speechLabel("语调 \(SpeechPreset.pitchName(settings.speechPitch))")
                }

                Menu {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Button("\(minutes) 分钟") {
                            speech.scheduleSleepTimer(minutes: minutes)
                        }
                    }
                    Button("取消定时", role: .destructive) {
                        speech.cancelSleepTimer()
                    }
                } label: {
                    speechLabel("定时")
                }

                Button {
                    toggleSpeechMode()
                } label: {
                    speechLabel("退出听书")
                }
            }
        }
        .padding(.top, 12)
        .background(.bar)
    }

    private func speechControlItem(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(title)
                    .font(.caption2)
            }
            .frame(minWidth: 56, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func speechLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    // MARK: 底部主工具条

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
                toolButton(isSpeechMode ? "停止听书" : "听书", systemImage: isSpeechMode ? "waveform" : "headphones") {
                    toggleSpeechMode()
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

// MARK: - 听书预设

enum SpeechPreset {
    struct Preset: Identifiable {
        let label: String
        let value: Float
        var id: Float { value }
    }

    static let speeds: [Preset] = [
        Preset(label: "很慢", value: 0.35),
        Preset(label: "慢", value: 0.42),
        Preset(label: "正常", value: 0.5),
        Preset(label: "快", value: 0.6),
        Preset(label: "很快", value: 0.7)
    ]

    static let pitches: [Preset] = [
        Preset(label: "低沉", value: 0.8),
        Preset(label: "正常", value: 1.0),
        Preset(label: "清亮", value: 1.25)
    ]

    static func speedName(_ value: Float) -> String {
        speeds.first { abs($0.value - value) < 0.03 }?.label ?? String(format: "%.2f", value)
    }

    static func pitchName(_ value: Float) -> String {
        pitches.first { abs($0.value - value) < 0.05 }?.label ?? String(format: "%.2f", value)
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

                        ChapterScrollTextView(attributedText: attributed(chapter.content))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(chapter.id)
                    .padding(.horizontal, settings.horizontalPadding)
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
        let attributes = settings.bodyAttributes()
        let body = NSMutableAttributedString(string: text, attributes: attributes)
        let indentStyle = NSMutableParagraphStyle()
        if let base = attributes[.paragraphStyle] as? NSParagraphStyle {
            indentStyle.setParagraphStyle(base)
        }
        indentStyle.firstLineHeadIndent = settings.paragraphIndentWidth
        body.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: body.length))
        return body
    }

    private func syncProgress(for chapterIndex: Int) {
        guard viewModel.activeChapterIndex != chapterIndex else { return }
        viewModel.jump(toChapter: chapterIndex)
    }
}

// MARK: - 骨架屏（不使用全屏 spinner）

private struct ReadingSkeleton: View {
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

// MARK: - 安全下标

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
