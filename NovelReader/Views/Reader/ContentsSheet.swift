import SwiftUI

/// 目录抽屉：Modal 必须提供关闭按钮，同时保留下滑关闭手势（系统默认）
///
/// 注意：body 拆成多个计算属性，避免单个表达式过于复杂导致
/// "the compiler is unable to type-check this expression in reasonable time"。
struct ContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let chapters: [Chapter]
    let activeChapterIndex: Int
    let onSelect: (Int) -> Void

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [(Int, Chapter)] {
        let enumerated = Array(chapters.enumerated())
        guard !trimmedQuery.isEmpty else { return enumerated }
        return enumerated.filter { $0.element.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("目录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                            .accessibilityLabel("关闭目录")
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 子视图（拆分以降低类型检查复杂度）

    @ViewBuilder
    private var content: some View {
        if chapters.isEmpty {
            ContentUnavailableView(
                "暂无目录",
                systemImage: "list.bullet",
                description: Text("这本书还没有可识别的章节。")
            )
        } else {
            chapterList
        }
    }

    private var chapterList: some View {
        List {
            Section {
                ForEach(filtered, id: \.element.id) { index, chapter in
                    row(for: index, chapter: chapter)
                }
            } header: {
                Text("共 \(chapters.count) 章")
            }
        }
        .listStyle(.plain)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索章节"
        )
    }

    private func row(for index: Int, chapter: Chapter) -> some View {
        let isActive = index == activeChapterIndex

        return Button {
            onSelect(index)
        } label: {
            HStack(spacing: 12) {
                Text(chapter.title)
                    .font(.body)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityLabel(chapter.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
