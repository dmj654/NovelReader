import SwiftUI

/// 目录抽屉：Modal 必须提供关闭按钮，同时保留下滑关闭手势（系统默认）
struct ContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let chapters: [Chapter]
    let activeChapterIndex: Int
    let onSelect: (Int) -> Void

    private var filtered: [(Int, Chapter)] {
        let enumerated = Array(chapters.enumerated())
        guard !searchText.trimmed.isEmpty else { return enumerated }
        return enumerated.filter { $0.element.title.localizedCaseInsensitiveContains(searchText.trimmed) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView("暂无目录", systemImage: "list.bullet", description: Text("这本书还没有可识别的章节。"))
                } else {
                    List {
                        Section {
                            ForEach(filtered, id: \.element.id) { index, chapter in
                                Button {
                                    onSelect(index)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(chapter.title)
                                            .font(.body)
                                            .foregroundStyle(index == activeChapterIndex ? Color.accentColor : Color.primary)
                                            .lineLimit(2)
                                        Spacer(minLength: 8)
                                        if index == activeChapterIndex {
                                            Image(systemName: "bookmark.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .accessibilityLabel(chapter.title)
                                .accessibilityAddTraits(index == activeChapterIndex ? .isSelected : [])
                            }
                        } header: {
                            Text("共 \(chapters.count) 章")
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索章节")
                }
            }
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
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
