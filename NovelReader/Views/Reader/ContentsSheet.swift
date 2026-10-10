import SwiftUI

/// 行模型：ForEach 需要 Identifiable 元素，SwiftUI 不支持无标签元组数组
private struct ChapterRow: Identifiable {
    let index: Int
    let chapter: Chapter
    var id: UUID { chapter.id }
}

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

    private var filtered: [ChapterRow] {
        let rows = chapters.enumerated().map { row in
            ChapterRow(index: row.offset, chapter: row.element)
        }
        guard !trimmedQuery.isEmpty else { return rows }
        return rows.filter { $0.chapter.title.localizedCaseInsensitiveContains(trimmedQuery) }
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
                ForEach(filtered) { row in
                    rowView(row)
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

    private func rowView(_ row: ChapterRow) -> some View {
        let isActive = row.index == activeChapterIndex

        return Button {
            onSelect(row.index)
        } label: {
            HStack(spacing: 12) {
                Text(row.chapter.title)
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
        .accessibilityLabel(row.chapter.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
