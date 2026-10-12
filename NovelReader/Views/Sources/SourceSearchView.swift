import SwiftUI

/// 书源搜索页：选源 → 关键字搜索 → 结果加入书架（自动解析目录）。
struct SourceSearchView: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var kind: BookKind = .novel
    @State private var selectedSourceID: String?
    @State private var query = ""
    @State private var results: [SourceEngine.SearchResult] = []
    @State private var isSearching = false
    @State private var addingLinks: Set<String> = []
    @State private var addedLinks: Set<String> = []
    @State private var toast: String?

    private var availableSources: [BookSource] {
        library.enabledSources(isComic: kind == .comic)
    }

    private var activeSource: BookSource? {
        availableSources.first { $0.id == selectedSourceID } ?? availableSources.first
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerBar
            resultList
        }
        .navigationTitle("书源搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedSourceID == nil {
                selectedSourceID = availableSources.first?.id
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        self.toast = nil
                    }
            }
        }
        .animation(.easeInOut, value: toast)
    }

    // MARK: - 选择区

    private var pickerBar: some View {
        VStack(spacing: 10) {
            Picker("类型", selection: $kind) {
                ForEach(BookKind.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .onChange(of: kind) { _, _ in
                selectedSourceID = availableSources.first?.id
                results = []
            }

            if availableSources.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("还没有启用的\(kind == .comic ? "漫画" : "小说")书源。书源是一段描述「从哪里抓书」的规则，需要自己添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        SourceManageView()
                    } label: {
                        Label("去书源管理添加", systemImage: "list.star")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            } else {
                // 选中的是内置示例源时说清楚，否则用户搜 example.com 搜不到东西，
                // 会以为"书源功能没反应"
                if let source = activeSource, source.id.hasPrefix("demo-") {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("这是示例书源，站点是 example.com，搜不到内容是正常的")
                                .font(.caption.weight(.semibold))
                            Text("到「书源管理」把这个源的网址和规则换成你自己的站点，就能真的搜到书。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 20)
                }

                Picker("书源", selection: $selectedSourceID) {
                    ForEach(availableSources) { source in
                        Text(source.name).tag(Optional(source.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 20)

                HStack(spacing: 10) {
                    TextField("输入关键字搜索", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { search() }

                    Button {
                        search()
                    } label: {
                        if isSearching {
                            ProgressView()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                    .accessibilityLabel("搜索")
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - 结果

    @ViewBuilder
    private var resultList: some View {
        if results.isEmpty {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text(isSearching ? "正在搜索…" : "输入关键字开始搜索")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(results) { result in
                    resultRow(result)
                }
            }
            .listStyle(.plain)
        }
    }

    private func resultRow(_ result: SourceEngine.SearchResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body)
                    .lineLimit(2)
                Text(result.link)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if addedLinks.contains(result.link) {
                Label("已在书架", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button {
                    add(result)
                } label: {
                    if addingLinks.contains(result.link) {
                        ProgressView()
                            .frame(width: 20, height: 20)
                    } else {
                        Text("加入书架")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(addingLinks.contains(result.link))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 动作

    private func search() {
        guard let source = activeSource else {
            toast = "请先选择一个书源"
            return
        }
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }

        // 示例源的站点是 example.com，发请求只会失败或超时，还让用户干等。
        // 直接说明白，比"点了没反应"好得多。
        if source.id.hasPrefix("demo-") {
            toast = "示例源站点（example.com）搜不到内容，请先把书源管理里的网址换成你自己的站点"
            return
        }

        isSearching = true
        results = []
        Task {
            do {
                let found = try await SourceEngine.search(source: source, query: keyword, page: 1)
                results = found
                if found.isEmpty { toast = "没有搜到结果，换个关键字或检查书源规则" }
            } catch {
                toast = "搜索失败：\(SourceEngine.readableMessage(error))"
            }
            isSearching = false
        }
    }

    private func add(_ result: SourceEngine.SearchResult) {
        guard let source = activeSource else { return }
        addingLinks.insert(result.link)
        Task {
            let ok = await library.addBook(from: result, source: source)
            addingLinks.remove(result.link)
            if ok {
                addedLinks.insert(result.link)
                toast = "《\(result.title)》已加入书架"
            } else {
                toast = library.lastError ?? "加入书架失败，检查书源规则。"
            }
        }
    }
}
