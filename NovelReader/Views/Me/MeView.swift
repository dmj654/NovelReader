import SwiftUI
import UniformTypeIdentifiers

struct MeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: ReadingSettingsStore

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showResetConfirm = false
    @State private var toast: String?

    private var totalWords: Int { library.books.reduce(0) { $0 + $1.wordCount } }
    private var finishedCount: Int { library.books.filter(\.isFinished).count }
    private var readPages: Int {
        library.books.reduce(0) { $0 + library.progress(for: $1.id).globalPageIndex + 1 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 20) {
                        StatItem(value: "\(library.books.count)", label: "藏书")
                        StatItem(value: totalWords.formatted(), label: "总字数")
                        StatItem(value: "\(readPages)", label: "已读页数")
                        StatItem(value: "\(finishedCount)", label: "读完")
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("藏书 \(library.books.count) 本，总字数 \(totalWords) 字，已读 \(readPages) 页，读完 \(finishedCount) 本")
                }

                Section("书库") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入本地 TXT", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("阅读设置", systemImage: "textformat.size")
                    }
                }

                Section("阅读偏好") {
                    HStack {
                        Label("翻页方式", systemImage: settings.pageTurnMode.systemImage)
                        Spacer(minLength: 8)
                        Text(settings.pageTurnMode.displayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("当前主题", systemImage: "paintpalette")
                        Spacer(minLength: 8)
                        Text(settings.theme.displayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("正文字号", systemImage: "character")
                        Spacer(minLength: 8)
                        Text("\(Int(settings.fontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("清空书架与进度", systemImage: "trash")
                    }
                } footer: {
                    Text("所有数据仅保存在本机，不会上传任何服务器。")
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer(minLength: 8)
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("隐私与权限说明", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("我的")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .text]) { result in
                switch result {
                case .success(let url):
                    let before = library.books.count
                    library.importBook(from: url)
                    toast = library.books.count > before ? "导入成功" : (library.lastError ?? "导入失败")
                case .failure(let error):
                    toast = error.localizedDescription
                }
            }
            .sheet(isPresented: $showSettings) {
                ReaderSettingsSheet()
                    .environmentObject(settings)
            }
            .confirmationDialog("确定清空书架？", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    // 边遍历边删除不安全，逐个从头移除
                    while let first = library.books.first {
                        library.remove(first)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("书籍与全部阅读进度将被删除，此操作不可撤销。")
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
                            toast = nil
                        }
                }
            }
            .animation(.easeInOut, value: toast)
        }
    }
}

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("权限与数据")
                    .font(.title3.weight(.semibold))
                BulletText("本 App 不请求定位、相机、通讯录、通知等任何系统权限。")
                BulletText("仅在你在「我的」或「书架」中主动点击导入时，才通过系统文件选择器读取你选定的 TXT 文件。")
                BulletText("阅读时可选择调整屏幕亮度与保持常亮，仅作用于 App 前台，退出后自动恢复。")
                BulletText("书籍、目录、阅读进度全部保存在本机 Documents 目录，卸载 App 即被系统清除。")
                BulletText("没有账号、没有埋点、没有上传。")
            }
            .padding(20)
        }
        .navigationTitle("隐私与权限")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BulletText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
                .padding(.top, 8)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
