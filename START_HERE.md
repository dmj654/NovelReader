# 接着做：把「阅栈」装进 iPhone 13 Pro

> 全程鼠标操作，不用敲任何命令。
> 这次是 **v1.1**（重做了排版、导入、漫画、书源、设置）。

---

> 🔒 **我这边每次给你之前会先跑一遍预检**（`tools/preflight_check.py`），
> 检查括号配对、import 缺失、ForEach 元组数组、变量遮蔽、语义色是否存在、
> project.yml 是否合法、打包内容与源码是否同步等，**有错误就不发给你**。
> 另外 CI 里也加了一步 Swift 语法快检，语法有问题 1 分钟就能看到，不用等 10 分钟。
> 剩下的风险主要是类型推断类错误，那种只能靠真机编译暴露——真红了把日志发我，我改。

---

## 第 1 步：解压新的压缩包

找到 **`NovelReader-upload.zip`**（刚刚重新生成的这一版，别用旧的）
→ 右键「全部解压缩」→ 得到：

> 不确定是不是最新的？打开解压出来的 **`包信息.txt`**，第一行就是生成时间，
> 还有一行「project.yml 已修复（不含 info 块）：是」。两份 zip 分不清的时候看它。

```
NovelReader/        ← App 源码
project.yml         ← 工程配置（这次改过，必须传）
README.md
INSTALL_ON_IPHONE.md
workflow-backup/    ← 备用：万一 .github 里的脚本丢了，用它手动重建
.github/            ← 不用管（GitHub 网页传不上去，见下）
```

---

## 第 2 步：上传源码

1. 打开仓库首页 `github.com/dmj554/NovelReader`
2. 右上角 **Add file** → **Upload files**
3. 把解压出来的 **`NovelReader` 文件夹** 和 **`project.yml`** 拖进虚线框
   - ❌ **不要拖 `.github`**（GitHub 网页会忽略点开头的文件夹，传不上去）
   - ❌ **不要拖外层的 `NovelReader-upload` 文件夹**（会变成 `NovelReader-upload/NovelReader/...` 嵌套路径，编译会找不到文件）
4. 等文件列表出现 → 拉到页面最下面 → 点绿色 **Commit changes**

### 怎么确认传对了

回到仓库首页，点进 `NovelReader` 文件夹，里面应该**直接**就是这些：

```
App/  Models/  Reader/  Services/  Views/  Resources/
```

如果你看到的是 `NovelReader/NovelReader/App/...`（套了两层），说明拖错了外层文件夹，
需要进 `NovelReader` → 再进一层 `NovelReader` → 右上角 `···` → Delete directory，删掉后重传一次。

---

## 第 3 步：让编译跑起来

> ⚠️ **先确认第 2 步的上传真的完成了。**
> Run workflow 编的是**仓库里此刻的代码**——如果新源码还没传上去，跑一万次也还是旧 App。

### 方法 A：手动点一下（最可靠，推荐）

1. 点仓库顶部的 **Actions** 标签
2. 左边列表里点 **Build iOS IPA (unsigned)**
3. 右边会出现一个 **`Run workflow`** 按钮（蓝灰色）→ 点它 → 再点弹出的绿色 **Run workflow**
4. 列表里立刻多出一条运行记录，开始转圈

> 这个方法不依赖任何上传触发条件，**只要你点，它就一定跑**。

### 方法 B：靠上传自动触发

上传完成 = 一次新提交，理论上会自动开始。
**如果 Actions 页面半天没动静**，按下面顺序排查：

| 检查 | 怎么看 | 不对怎么办 |
| --- | --- | --- |
| ① 提交了吗 | 仓库首页最上面，绿色按钮那一行有没有新的提交记录 | 回到第 2 步，确认点了 **Commit changes**（很多人拖完就关页面了，不算提交） |
| ② 脚本还在吗 | 打开 `github.com/dmj554/NovelReader/tree/main/.github/workflows` | 看不到 `build-ipa.yml` 就按下面「脚本丢了怎么办」重建 |
| ③ Actions 开着吗 | 仓库 **Settings** → 左侧 **Actions** → **General** → 最下面 Actions permissions | 选 **Allow all actions and reusable workflows** → Save |
| ④ 分支对吗 | 仓库首页左上角分支名 | 脚本只在 `main` / `master` 上跑，如果在别的分支，切回默认分支再传 |

### 脚本丢了怎么办

`.github` 文件夹可能在某次删除操作里被一起删了。重建方法（网页操作，30 秒）：

1. 仓库首页 → **Add file** → **Create new file**
2. 上方文件名框里**完整输入**这一串（GitHub 会自动帮你建文件夹）：

   ```
   .github/workflows/build-ipa.yml
   ```

3. 打开解压出来的 `workflow-backup/build-ipa.yml`，**全选复制**里面的内容，粘贴进下面的大文本框
4. 拉到底 → **Commit changes**

回到 Actions 页面，就能看到这个 workflow 了。

---

## 第 4 步：等编译（5～10 分钟，不用操作）

| 图标 | 意思 | 怎么办 |
| --- | --- | --- |
| 🟡 黄点转圈 | 正在编译 | 等着，别动 |
| ✅ 绿勾 | **成功了** | 进第 5 步 |
| ❌ 红叉 | 还有报错 | 见最后「万一还是红的」 |

---

## 第 5 步：下载 IPA

1. 点**最新那条**运行记录的标题（看时间，必须是刚刚跑完的那条；旧记录点进去下载到的是旧包）
2. 进详情页后拉到**页面最最底部**
3. 找到 **Artifacts** 一栏 → 点 `NovelReader-unsigned-ipa` → 浏览器下载一个 zip
4. 解压它 → 得到 **`NovelReader-unsigned.ipa`** 🎉

---

## 第 6 步：装进 iPhone 13 Pro

### 用爱思助手（Windows 最简单）

1. 打开爱思助手，iPhone 用**数据线**连电脑 → 手机点「信任此电脑」→ 输密码
2. 左侧 **我的应用** → 上方 **导入** → 选第 5 步那个 `.ipa` → 安装
3. 装完 iPhone 上：**设置 → 通用 → VPN 与设备管理** → 点你的开发者 → **信任**

### 用你自己的证书 / 签名工具

直接拿这个未签名的 IPA 签就行，签完同样去设置里信任。

---

## 装好之后，重点看这几件事

1. **排版**：打开任意一本，一页应该有约 20 行中文，底部只剩很窄一条空白；长按设置里可以调字号/行距/段距/页边距/字体/主题/翻页方式
2. **导入 TXT**：书架右上角 **`＋`** → 选一个 txt → **一定会弹一句话提示**（成功就显示"已导入《书名》，共 N 章"，失败会写清原因）
   - 支持 UTF-8 / GBK / UTF-16 编码，章节名会自动识别
3. **漫画**：书架顶部切到「漫画」分区 → 右上角 **`＋`** → 多选几张图片 → 起个名字 → 就能当漫画翻
4. **书源**：我的 → 书源管理 → 右上角 `···` → 「添加示例书源」先看看长什么样；真实站点需要你把自己书源的 JSON 粘进去

---

## 装到手机上"和以前一模一样"？按顺序查

App 现在带版本号了：**我的 → 版本**，v1.1 显示 `1.1.0（构建 2）`。
如果手机上看到的还是 `1.0.0`，说明装的确实是旧包，按下面查：

### ① 仓库里的源码是不是新的

打开这个地址看一眼：

```
github.com/dmj554/NovelReader/tree/main/NovelReader/Views/Common
```

- 能看到 **`Toast.swift`** → 新源码已经传上去了 ✅
- 看不到 → 第 2 步没成功，重新传一次（注意：**必须点 Commit changes**）

顺便打开 `project.yml`，最上面几行里应该能看到：

```
MARKETING_VERSION: "1.1.0"
CURRENT_PROJECT_VERSION: "2"
```

没有的话说明 `project.yml` 没传上去，一起补传。

### ② 跑的是不是新的那次

Actions 页面里每一条记录左边都有**提交信息**和时间。**必须点刚刚跑完的那条**，
旧记录里的 artifact 还在（保留 30 天），点错了下载到的就是旧安装包。

### ③ 手机上是不是真的覆盖安装了

用爱思助手重新导入安装后，回到 iPhone 桌面看图标有没有短暂变灰再恢复；
进 App → 我的 → 版本，确认显示 `1.1.0（构建 2）`。
如果版本还是旧的，先在 iPhone 上**删掉阅栈**再装一次。

---

## CI 报 `Decoding failed at 'path': Nothing found`

说明仓库里的 `project.yml` 还是**旧版本**（带一个格式错误的 `info:` 块）。修法二选一：

### 修法 A：在网页上直接改（最快，推荐）

1. 打开 `github.com/dmj554/NovelReader/edit/main/project.yml`（直接进编辑模式）
2. 按 `Ctrl+F` 搜 `info:`，找到这一段：

   ```yaml
       resources:
         - path: NovelReader/Resources/Assets.xcassets
       info:                                   ← 从这一行开始删
         # 让「文件」App 与其他 App 可以把 TXT / JSON 分享到阅栈打开
         CFBundleDocumentTypes:
           - CFBundleTypeName: "Text Document"
             ...
         NSAppTransportSecurity:
           NSAllowsArbitraryLoads: true          ← 删到这一行为止
       settings:
   ```

3. **从 `info:` 这一行，一直删到 `NSAllowsArbitraryLoads: true` 这一行**（含这两行）
   删完应该变成：

   ```yaml
       resources:
         - path: NovelReader/Resources/Assets.xcassets
       settings:
   ```

4. 拉到底 → **Commit changes**
5. 回 Actions → `Build iOS IPA (unsigned)` → **Run workflow**

### 修法 B：重新上传

确认解压出来的是**最新那个 zip**（打开包里的 `包信息.txt` 看生成时间），
把 `project.yml` 拖进仓库覆盖 → **Commit changes**。

> ⚠️ **不要点右上角的 `Re-run jobs`** —— 那是重跑同一次提交，代码一个字都不会变，
> 只会再红一次。必须产生一个新提交。

---

## CI 报 `method must be declared fileprivate`

完整的一般是：

```
.../ChapterPaginator.swift:95: error: method must be declared fileprivate
because its result uses a private type
```

**这一条我已经修好了**。如果你还看到它，说明仓库里跑的还是旧源码
（多半是压缩包没覆盖成功，或者点了 `Re-run jobs`）。

按「装到手机上和以前一模一样」那节的 **①** 确认一下源码是不是新的，
看不到 `NovelReader/Views/Common/Toast.swift` 就重传一次 `NovelReader` 文件夹。

---

## 这三次红的记录（都修完了，留着对照）

| 报错关键词 | 真正原因 | 现在的状态 |
| --- | --- | --- |
| `Decoding failed at 'path': Nothing found` | `project.yml` 里有个格式错的 `info:` 块 | 已删掉，预检会拦 |
| `Decoding failed at 'path': Nothing found`（第二次） | 同上，那次是用了旧包或点了 Re-run | 已删掉 |
| `method must be declared fileprivate` | `ChapterPaginator` 的访问控制 | 已改 `fileprivate` |

---

## 万一还是红的

1. 点那条 ❌ 记录
2. 点左边**带红叉的那个步骤名**（很可能是 `Archive` 或 `Install XcodeGen`）
3. 在日志页右上角 **Search logs** 框里搜 `error:`
4. 截图发我

这样我能直接看到是哪一行代码的问题，改完你再重传一次就行。
