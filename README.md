# 阅栈 NovelReader

一个 iOS 原生小说阅读 App。SwiftUI 负责界面，UIKit（TextKit + UIPageViewController）负责排版与翻页。
不联网、不要账号、不申请任何系统权限，所有数据只存在本机。

---

## 一、功能

| 模块 | 能力 |
| --- | --- |
| 书架 | 网格 / 列表双视图、搜索、继续阅读卡片、书籍详情、TXT 导入与导出 |
| 阅读器 | TextKit 精确分页、仿真翻页（pageCurl）与上下滚动双模式、章节跳转、进度拖拽 |
| 排版 | 字号 14–30pt、行距、4 种中文字体、首行缩进 2 字符、两端对齐 |
| 外观 | 5 套主题（纯白 / 米黄 / 护眼 / 水墨 / 夜间）、独立亮度、屏幕常亮 |
| 解析 | UTF-8 / GB18030 / Big5 编码探测，正则识别「第 N 章」「Chapter N」「序章 / 楔子 / 后记」等标题，自动过滤站点广告行 |
| 数据 | 书籍 JSON + 进度 JSON 存于 Documents，进入后台立即落盘 |

内置 3 本原创示例小说（科幻 / 生活 / 悬疑），首次启动自动写入书架。

---

## 二、目录结构

```
NovelReader/
├── App/
│   └── NovelReaderApp.swift            # @main 入口，环境对象注入，后台落盘
├── Models/
│   ├── Book.swift                      # Book / Chapter / CoverTheme / ReadingProgress
│   └── ReadingSettings.swift           # ReaderTheme / PageTurnMode / 字体选项 / 设置持久化
├── Services/
│   ├── NovelParser.swift               # TXT 编码探测 + 章节切分 + 正文清洗
│   ├── LibraryStore.swift              # 书架与进度的增删改查与持久化
│   └── SampleLibrary.swift             # 内置示例书（原创内容）
├── Reader/
│   ├── ChapterPaginator.swift          # TextKit 分页：NSRange 切分 + 全书页面构建
│   ├── ReaderPageView.swift            # UITextView 渲染单页 / 整章
│   ├── PagedReader.swift               # UIPageViewController 的 SwiftUI 封装
│   └── ReaderViewModel.swift           # 分页调度、页码定位、进度保存、屏幕策略
├── Views/
│   ├── RootTabView.swift               # Tab Bar 根导航（书架 / 发现 / 我的）
│   ├── Shelf/{ShelfView, BookCoverView, BookDetailView}.swift
│   └── Reader/{ReaderView, ContentsSheet, ReaderSettingsSheet}.swift
└── Resources/Assets.xcassets/          # 18 个语义色 Color Set（脚本生成）

tools/generate_assets.py                # 生成上述 Color Set
prototype/index.html                    # 可在浏览器直接打开的交互原型
project.yml                             # XcodeGen 工程描述，一键生成 .xcodeproj
.github/workflows/build-ipa.yml         # GitHub macOS 云构建，产出未签名 IPA
INSTALL_ON_IPHONE.md                    # 装到真机的三条路线与排错表
```

> 版本说明：最低部署 **iOS 17.0**（iPhone XS / XR / SE2 及更新）。
> 代码已规避 iOS 18 专属的 `Tab(_:systemImage:value:)`，改用 `tabItem + tag` 写法。

---

## 三、在 Mac 上运行 / 装到 iPhone

> **装到 iPhone 的完整步骤见 [`INSTALL_ON_IPHONE.md`](INSTALL_ON_IPHONE.md)**
> （含无 Mac 时用 GitHub Actions 云构建 + Sideloadly 侧载的路线）。
> Windows 无法编译 iOS App，这是工具链限制，不是配置问题。

### 方式一：XcodeGen 自动生成工程（推荐）

```bash
brew install xcodegen
xcodegen generate      # 读取根目录 project.yml，生成 NovelReader.xcodeproj
open NovelReader.xcodeproj
```

`project.yml` 里已经配好：iOS 17.0 部署目标、Bundle ID `com.novelreader.app`、
自动生成的启动屏（无需 storyboard）、资源目录与 Display Name「阅栈」。

### 方式二：Xcode 手动新建工程

1. 新建工程：`File ▸ New ▸ Project ▸ iOS ▸ App`
   - Language：**Swift**，Interface：**SwiftUI**，最低部署 **iOS 17.0**
2. 删除模板生成的 `ContentView.swift`，把 `NovelReader/` 下的全部 `.swift` 文件拖入工程（勾选 Copy items if needed）。
3. 生成并加入资源：

   ```bash
   python3 tools/generate_assets.py
   ```

   把生成的 `NovelReader/Resources/Assets.xcassets` 拖入 Xcode 工程，
   并在 Target ▸ Build Settings ▸ **Asset Catalog Compiler - Options** 中确认它已被包含。

4. 设置 App Icon：在 `Assets.xcassets` 的 `AppIcon` 中放入 1024×1024 图片（脚本已生成占位目录）。
5. 若要在真机导入 TXT，无需任何权限声明——使用系统 `.fileImporter`，由用户主动选择文件。
6. `⌘R` 运行。

> 依赖：仅系统框架（SwiftUI / UIKit / Foundation / UniformTypeIdentifiers），**无第三方库**。

---

## 四、关键实现说明

### 分页为什么用 TextKit

SwiftUI 的 `Text` 无法直接获取"第 N 页的字符范围"。这里用 `NSLayoutManager` 依次追加 `NSTextContainer`，
每个容器返回的 `glyphRange` 换算成 `characterRange` 即为一页：

```swift
let storage = NSTextStorage(attributedString: attributed)
let layout = NSLayoutManager(); storage.addLayoutManager(layout)
while previousEnd < layout.numberOfGlyphs {
    let container = NSTextContainer(size: pageSize)   // lineFragmentPadding = 0
    layout.addTextContainer(container)
    let glyphRange = layout.glyphRange(for: container)
    let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    ...
}
```

渲染端同样使用 `UITextView`（`lineFragmentPadding = 0`、容器尺寸一致），保证分页与显示像素级一致，
不会出现"最后一行被切掉"的问题。

### 改字号后如何保持阅读位置

进度采用**双坐标**：`chapterIndex + pageIndexInChapter`，而不是全局页码。
排版参数变化时重新分页，再用双坐标回查新的全局页码，因此改字号 / 换字体 / 旋转屏幕后仍停在同一段。
`ReadingSettingsStore.layoutSignature` 变化即触发重排。

### 进度持久化

- 翻页后 `.onChange(of: currentIndex)` 写入内存字典；
- `scenePhase != .active` 时 `LibraryStore.save()` 落盘；
- 冷启动 `ReaderViewModel.updatePageSize` 完成后按双坐标恢复。

---

## 五、Apple HIG 与无障碍清单

已落实：

- **导航**：Tab Bar 三个标签，无 hamburger 菜单；不覆盖系统边缘返回手势（阅读器未添加自定义返回手势，仅使用顶部返回按钮 + 系统 `dismiss`）。
- **触控目标**：所有按钮最小 44×44pt（`frame(minWidth: 60, minHeight: 44)`）。
- **安全区域**：`.ignoresSafeArea()` 仅用于阅读页背景与翻页容器，交互元素全部在安全区内；底部工具条自带 `.padding(.bottom, 26)`。
- **字号**：正文经 `UIFontMetrics(forTextStyle: .body).scaledFont(for:)` 缩放，支持 Dynamic Type；`ReaderPageView` 开启 `adjustsFontForContentSizeCategory`。
- **语义色**：全部使用 Asset Catalog 的 Color Set，自动适配深色模式，无硬编码色值。
- **无障碍标签**：所有图标按钮均有 `accessibilityLabel`；封面合并子元素并朗读"书名 / 作者 / 已读百分比"；进度滑块带 `accessibilityValue`。
- **加载态**：分页期间显示 `.redacted` 骨架屏，不使用全屏 spinner；尊重 `accessibilityReduceMotion`。
- **Modal**：目录与设置面板均提供「关闭 / 完成」按钮，并保留系统下拉关闭手势。
- **权限**：不在启动时请求权限；仅在用户点击导入时通过系统文件选择器读取文件；亮度与常亮仅在阅读器前台生效，退出自动恢复。
- **信息不靠颜色单独传达**：已读状态同时用"进度文字 + 书签图标"表达。

---

## 六、可继续扩展的方向

- EPUB 解析（`ZIPFoundation` + OPF/NCX），接入同一套 `Book` 模型即可复用全部阅读能力；
- iCloud Drive / `NSFileProvider` 同步书架与进度；
- 阅读时长统计与连续打卡（当前仅统计页数）；
- 书签、划线与笔记（在 `ReaderPage` 上叠加 `NSAttributedString` 高亮属性）；
- 听书：用 `AVSpeechSynthesizer` 朗读当前页文本。

---

## 七、原型预览

`prototype/index.html` 是同一套设计的浏览器交互原型（无需构建，双击打开即可）：
书架 → 详情 → 阅读器，支持目录跳转、字号 / 行距 / 字体 / 主题实时切换与翻页。
