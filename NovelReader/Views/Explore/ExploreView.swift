import SwiftUI

/// 发现页：本地精选与分类浏览，不依赖网络，避免新增权限。
struct ExploreView: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var selectedCategory: String = "全部"

    private var categories: [String] {
        ["全部"] + Array(Set(library.books.map(\.category))).sorted()
    }

    private var filtered: [Book] {
        guard selectedCategory != "全部" else { return library.books }
        return library.books.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { category in
                                CategoryChip(title: category, isSelected: selectedCategory == category) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selectedCategory = category }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("精选书单")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 20)

                        if filtered.isEmpty {
                            ContentUnavailableView("该分类暂无书籍", systemImage: "tray")
                                .frame(height: 200)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(filtered) { book in
                                    NavigationLink(value: book.id) {
                                        FeaturedRow(book: book)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("发现")
            .navigationDestination(for: UUID.self) { id in
                if let book = library.book(withID: id) {
                    BookDetailView(book: book) { }
                } else {
                    ContentUnavailableView("书籍不存在", systemImage: "book.closed")
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("把书带在身上")
                .font(.headline)
            Text("支持导入任意本地 TXT：自动识别章节、自动排版分页、自动记住读到第几页。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, 20)
    }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FeaturedRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(book.coverTheme.assetName).gradient)
                .frame(width: 56, height: 76)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(Color.white.opacity(0.9))
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(book.intro.isEmpty ? book.category : book.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(book.author) · \(book.wordCount.formatted()) 字")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，\(book.author)")
    }
}
