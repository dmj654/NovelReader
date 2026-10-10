import SwiftUI
import UIKit

/// 书源管理页：增删改、启用禁用、拖拽排序、JSON 导入导出、可用性校验。
struct SourceManageView: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var editingSource: BookSource?
    @State private var showEditor = false
    @State private var isCheckingAll = false
    @State private var toast: String?

    private var orderedSources: [BookSource] {
        library.sources.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Group {
            if orderedSources.isEmpty {
                ContentUnavailableView(
                    "还没有书源",
                    systemImage: "tray.full",
                    description: Text("点右上角 ＋ 手动添加，或从菜单导入 JSON 书源。")
                )
            } else {
                sourceList
            }
        }
        .navigationTitle("书源管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingSource = BookSource(
                        name: "",
                        baseURL: "",
                        searchTemplate: "",
                        sortOrder: (library.sources.map(\.sortOrder).max() ?? -1) + 1,
                        rules: SourceRules(listPattern: "")
                    )
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加书源")
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        importFromPasteboard()
                    } label: {
                        Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        exportToPasteboard()
                    } label: {
                        Label("导出到剪贴板", systemImage: "square.and.arrow.up.on.square")
                    }
                    Button {
                        checkAll()
                    } label: {
                        Label("校验全部书源", systemImage: "checkmark.seal")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("导入导出与校验")
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: { editingSource = nil }) {
            if let source = editingSource {
                SourceEditorSheet(source: source)
                    .environmentObject(library)
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
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        self.toast = nil
                    }
            }
        }
        .animation(.easeInOut, value: toast)
    }

    // MARK: - 列表

    private var sourceList: some View {
        List {
            ForEach(orderedSources) { source in
                Button {
                    editingSource = source
                    showEditor = true
                } label: {
                    sourceRow(source)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    let source = orderedSources[index]
                    library.removeSource(source)
                }
            }
            .onMove { from, to in
                library.moveSources(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.inactive))
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(source.name.isEmpty ? "未命名书源" : source.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(source.isEnabled ? Color.primary : Color.secondary)
                    Text(source.isComic ? "漫画" : "小说")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                Text(source.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let ok = source.lastCheckSucceeded, let date = source.lastCheckedAt {
                        Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(ok ? Color.green : Color.orange)
                        Text("校验于 \(date.formatted(.dateTime.month().day()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未校验")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { library.toggleSource(source, enabled: $0) }
            ))
            .labelsHidden()
            .accessibilityLabel("\(source.name) 启用")
        }
        .contentShape(Rectangle())
    }

    // MARK: - 动作

    private func importFromPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            toast = "剪贴板是空的"
            return
        }
        do {
            let count = try library.importSourcesJSON(text)
            toast = "成功导入 \(count) 个书源"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func exportToPasteboard() {
        UIPasteboard.general.string = library.exportSourcesJSON()
        toast = "已复制到剪贴板"
    }

    private func checkAll() {
        guard !isCheckingAll else { return }
        isCheckingAll = true
        Task {
            for source in library.sources {
                let ok = await SourceEngine.checkAvailability(source)
                var updated = source
                updated.lastCheckedAt = Date()
                updated.lastCheckSucceeded = ok
                library.upsertSource(updated)
            }
            isCheckingAll = false
            toast = "校验完成"
        }
    }
}

// MARK: - 编辑

struct SourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    @State private var draft: BookSource
    @State private var showRuleHelp = false

    private let isNew: Bool

    init(source: BookSource) {
        _draft = State(initialValue: source)
        isNew = source.name.isEmpty && source.baseURL.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("书源名称", text: $draft.name)
                    TextField("站点地址（https://…）", text: $draft.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("搜索地址（含 {query} 和 {page}）", text: $draft.searchTemplate)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    Picker("类型", selection: $draft.isComic) {
                        Text("小说").tag(false)
                        Text("漫画").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("结果列表正则", text: $draft.rules.listPattern, axis: .vertical)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                    Stepper("标题捕获组：第 \(draft.rules.titleGroup) 组", value: $draft.rules.titleGroup, in: 1...9)
                    Stepper("链接捕获组：第 \(draft.rules.linkGroup) 组", value: $draft.rules.linkGroup, in: 1...9)
                } header: {
                    Text("搜索结果提取")
                } footer: {
                    Button {
                        showRuleHelp = true
                    } label: {
                        Label("规则怎么写？", systemImage: "questionmark.circle")
                            .font(.caption)
                    }
                }

                Section("目录提取（可留空，沿用搜索规则）") {
                    TextField("目录列表正则", text: Binding(
                        get: { draft.rules.tocPattern ?? "" },
                        set: { draft.rules.tocPattern = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                }

                Section("正文 / 图片提取") {
                    TextField("小说正文正则（可留空）", text: Binding(
                        get: { draft.rules.contentPattern ?? "" },
                        set: { draft.rules.contentPattern = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)

                    TextField("漫画图片正则（可留空）", text: Binding(
                        get: { draft.rules.imagePattern ?? "" },
                        set: { draft.rules.imagePattern = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(isNew ? "添加书源" : "编辑书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        library.upsertSource(draft)
                        dismiss()
                    }
                    .disabled(draft.name.isEmpty || draft.baseURL.isEmpty)
                }
            }
            .alert("规则写法", isPresented: $showRuleHelp) {
                Button("好", role: .cancel) {}
            } message: {
                Text("""
                用正则表达式描述要抓的内容，用捕获组 () 标出标题和链接的位置。\
                例如搜索结果：<a href="(...链接...)" title="(...标题...)">\
                对应 linkGroup=1、titleGroup=2。\
                正文正则取第一个捕获组；漫画图片正则取图片地址。\
                导入别人的书源 JSON 时这些字段会自动填好。
                """)
            }
        }
    }
}
