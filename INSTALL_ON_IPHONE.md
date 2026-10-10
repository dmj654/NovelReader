# 怎么在 iPhone 上跑起来

## 先说清楚一件事

**Windows 编译不了 iOS App。** Apple 的编译器、签名工具、模拟器全部只存在于 macOS 上，
这不是配置问题，是工具链的硬限制。所以你的 Windows 这台机器只能做「写代码 + 触发云构建」，最后一步安装必须在 iPhone 上完成。

另外确认设备门槛：当前工程最低部署 **iOS 17.0**，支持机型是 **iPhone XS / XR / SE(2代及以后) 及更新**。
如果你的 iPhone 更老，告诉我机型，我把工程降到 iOS 16（改动很小）。

下面四条路线，按「你的情况」排列：

| 路线 | 适合 | 要多久 |
| --- | --- | --- |
| **A** 在线原型添加到主屏幕 | 只想先看看长什么样 | 3 分钟 |
| **B** 有 Mac，Xcode 直接装 | 有 Mac | 10 分钟 |
| **C** 有证书，CI 产出已签名 IPA | 你有开发者证书（**推荐**） | 首次 20 分钟，之后 10 分钟 |
| **D** 未签名 IPA，自己用工具签 | 不想配证书 | 首次 15 分钟 |

---

## 路线 A：3 分钟，立刻在 iPhone 上看到它（无需 Mac）

把浏览器原型发布成一个在线链接：

> 这一步需要我先把原型发布成在线链接（说一声我就发）。
> 在发布之前，你也可以在电脑上双击打开 `prototype/index.html` 先看效果。
2. 点底部 **分享** 按钮 → 下滑找到 **「添加到主屏幕」** → 右上角「添加」
3. 桌面出现图标，点开就是**全屏、无地址栏**的 App 形态

可以试的交互：书架 → 点书 → 详情 →「开始阅读」→ **点击屏幕中间**唤出工具条 → 目录 / 夜间 / 字号 / 主题切换；屏幕左右两侧点一下翻页。

> 这是**高保真交互原型**（HTML），不是原生 App。它能验证交互流程、排版、配色和手感，
> 但没有真正的 TXT 导入、分页引擎和进度存储——那些必须编译原生 App 才有。

---

## 路线 B：有 Mac —— 正规装到 iPhone（推荐）

### 免费 Apple ID：能装，7 天过期
### 付费开发者账号（¥688/年）：1 年有效，还能上 TestFlight / App Store

步骤：

1. **Mac 装 Xcode 15 或更高**（Mac App Store 免费，约 40GB）

2. **生成工程**，两种方式二选一：
   - 方式一（推荐，快）：终端执行
     ```bash
     brew install xcodegen
     cd 项目目录
     xcodegen generate      # 用我写好的 project.yml 生成 NovelReader.xcodeproj
     open NovelReader.xcodeproj
     ```
   - 方式二（不装任何工具）：Xcode 手动新建 iOS App 工程 → 删掉 `ContentView.swift` →
     把 `NovelReader/` 里的 `.swift` 文件全部拖进去 → 把 `NovelReader/Resources/Assets.xcassets` 拖进去

3. **连接 iPhone**：数据线插上，iPhone 上点「信任此电脑」并输密码。
   同时 iPhone 需要打开 **设置 → 隐私与安全性 → 开发者模式**（iOS 16 起才有这个开关，打开后重启一次）。

4. **设置签名**：Xcode 左侧点蓝色项目图标 → `NovelReader` target → **Signing & Capabilities**
   → Team 下拉选择 `Add an Account...` → 登录你的 Apple ID
   - 免费账号会显示 **(Personal Team)**
   - 遇到 `Bundle Identifier` 冲突，把 `com.novelreader.app` 改成你自己的，比如 `com.你的名字.reader`

5. **选择设备并运行**：Xcode 顶部设备选择里选你的 iPhone（不是 Simulator）→ `⌘R`

6. **首次安装后信任**：iPhone 上 **设置 → 通用 → VPN 与设备管理** → 点你的 Apple ID → 「信任」

7. 装好了。**免费账号的 7 天有效期**：到期后 App 打不开，重新用数据线连上 `⌘R` 一次即可续期，数据不会丢（App 数据在沙盒里不受影响）。

> iPhone 上要真的放小说进去：Mac 上用 AirDrop 把 TXT 发给 iPhone → 存储到「文件」App →
> 打开阅栈 → 书架右上角 `＋` → 在文件选择器里选中这个 TXT。

---

## 路线 C：你有证书 —— 让 CI 直接产出「可安装」的 IPA（推荐给你）

既然你自己能签名，最省事的做法是让 GitHub 的 macOS 机器**签完再给你**，你下载 IPA 直接装。
对应 workflow：`.github/workflows/build-signed-ipa.yml`。

### C-1 一次性准备这 5 样东西

| 需要 | 从哪拿 |
| --- | --- |
| `.p12` 证书 | Mac 钥匙串 →「我的证书」→ 右键导出为 .p12（**要连私钥一起导出**）；或在 Apple Developer 下载证书导入钥匙串后再导出 |
| `.mobileprovision` | Apple Developer → Certificates, Identifiers & Profiles → Profiles → 下载。**Development / Ad Hoc 必须先登记你的 iPhone UDID** |
| Team ID | Apple Developer → Membership，10 位字母数字，如 `AB12CD34EF` |
| 证书名称 | 钥匙串里双击证书看「常用名称」，形如 `Apple Development: 张三 (AB12CD34EF)` |
| Profile 名称 | Apple Developer 里这个 Profile 的 **Name 字段**（不是文件名） |

**iPhone 13 Pro 的 UDID**（Development / Ad Hoc 才需要）：
- Windows：装爱思助手 → 连上 iPhone → 设备信息里那串 40 位字符串；或 iTunes 里点「序列号」那一行，会切换成 UDID
- 或 iPhone Safari 打开 https://udid.io 按提示装个临时描述文件就能看到
- 拿到后：Apple Developer → Devices → 添加 → **然后重新生成并下载 Profile**（旧的 Profile 不含新设备，装了会秒退）

> 如果你用的是**企业 In-House 证书**，不需要 UDID，导出方式选 `enterprise`。

### C-2 把上面这些填进 GitHub Secrets

仓库 → **Settings → Secrets and variables → Actions → New repository secret**，建这 7 个：

| Secret 名 | 值 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | p12 的 base64：`base64 -w0 cert.p12 > cert.txt`，把内容整段粘进去 |
| `P12_PASSWORD` | 导出 p12 时设的密码 |
| `KEYCHAIN_PASSWORD` | 随便写一个字符串，CI 建临时钥匙串用，不对应任何真实密码 |
| `BUILD_PROVISIONING_PROFILE_BASE64` | `base64 -w0 xxx.mobileprovision`，整段粘贴 |
| `CODE_SIGN_IDENTITY` | `Apple Development: 张三 (AB12CD34EF)` |
| `PROVISIONING_PROFILE_NAME` | Profile 的 Name |
| `DEVELOPMENT_TEAM` | Team ID |

> Windows 上没有 `base64 -w0`？用 Git Bash 执行，或者：
> `certutil -encode cert.p12 out.b64` 然后把 `out.b64` 中间那段（去掉首尾 CERTIFICATE 行）粘进去。

### C-3 触发构建

Actions → **Build Signed IPA (installable)** → Run workflow → `export_method` 选：
- `development` —— 自己手机调试用（Profile 含 UDID）
- `ad-hoc` —— 发给几台指定设备
- `enterprise` —— 企业 In-House，不需要 UDID

约 8–12 分钟，跑完在 Artifacts 下载 `NovelReader-development-ipa`。

### C-4 装进 iPhone 13 Pro

- **爱思助手**（Windows 最省事）：我的应用 → 导入 → 选 IPA → 安装
- **Apple Configurator 2**（Mac）：拖进去
- 装完首次打开：设置 → 通用 → VPN 与设备管理 → 信任你的证书

> 没配 Secrets 也不怕：这个 workflow 会自动回退成"不签名"，照样产出 IPA，你拿去用自己的工具签。

---

## 路线 D：没有 Mac、也不想配证书 —— 未签名 IPA + 侧载

用 GitHub 提供的 macOS 云机器编译，产出未签名 IPA，再在 Windows 上用你的 Apple ID 签名装进 iPhone。
对应 workflow：`.github/workflows/build-ipa.yml`，**不需要配置任何 Secrets**。

### 第 1 步：推到 GitHub

```bash
git init
git add .
git commit -m "NovelReader"
git remote add origin https://github.com/<你的用户名>/NovelReader.git
git push -u origin main
```

> 用**公开仓库**：GitHub Actions 对公开仓库的 macOS 机器完全免费；私有仓库每月只有 2000 分钟额度。

### 第 2 步：触发构建

打开仓库页面 → **Actions** → 左侧选 **Build iOS IPA (unsigned)** → 右侧 **Run workflow** → 绿色按钮。
等 5–10 分钟，跑完后点进这次运行，在底部 **Artifacts** 下载 `NovelReader-unsigned-ipa`，解压缩得到 `.ipa`。

### 第 3 步：签名安装

**如果你有自己的签名工具（你现在的情况）**：下载未签名 IPA 后直接用自己的工具签，跳过下面 Sideloadly 的部分。

**如果你想用免费的 Apple ID 签**：

1. 装 **iTunes 和 iCloud 的 Windows 版**（必须从 Apple 官网下，**不要用 Microsoft Store 版**，
   后者缺 Apple 的设备驱动库，Sideloadly 会卡在"找不到设备"）
   - https://support.apple.com/downloads/itunes
2. 装 **Sideloadly**：https://sideloadly.io（免费版够用，有次数限制）
3. iPhone 数据线连电脑 → 点「信任此电脑」
4. Sideloadly：
   - 左上角 IPA 图标 → 选刚才下载的 `.ipa`
   - 填你的 Apple ID（**建议注册一个小号**，不要用主力 ID）
   - 密码填 Apple ID 密码，或去 appleid.apple.com 生成的 **App 专用密码**
   - 点 **Start**，等进度条走完，桌面出现「阅栈」图标
5. iPhone 上 **设置 → 通用 → VPN 与设备管理** → 信任你的 Apple ID
6. 打开，搞定

### 关于 7 天重签

免费 Apple ID 签出来的 App 有效期 **7 天**。过期后：
电脑开着、iPhone 用数据线连着，Sideloadly 勾上 **Auto Re-sign** 会自动续；
或者手动再点一次 Start（几秒钟，数据不丢）。

免费账号的限制：同一 Apple ID 最多同时 3 个侧载 App、7 天内最多 10 个 App ID。日常自用足够。

---

## 常见报错对照

| 现象 | 原因 / 解决 |
| --- | --- |
| Xcode：`Signing for "NovelReader" requires a development team` | 没选 Team，回到 Signing & Capabilities 选你的 Apple ID |
| Xcode：`No account for team` / 一直转圈 | 退出 Xcode 账号重新登录；免费账号偶尔要重启 Xcode |
| iPhone 上「无法验证 App / 未受信任的企业级开发者」 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| Xcode：`This iPhone is not available` | iPhone 没开开发者模式，或数据线只充电不传数据，换原装线 |
| Sideloadly 报 `0xe8008015` / `0xe8000067` | 重新登录 Apple ID（建议用 App 专用密码），或换一个 Apple ID |
| Sideloadly 找不到设备 | 装了 Microsoft Store 版 iTunes，卸载后装 Apple 官网版并重启电脑 |
| CI：`No matching provisioning profile found` | `PROVISIONING_PROFILE_NAME` 填成了文件名，要填 Apple Developer 里的 Name 字段 |
| CI：`Code signing is required for product type 'Application'` | 没配 Secrets（会回退未签名），或 p12 导出时**没带私钥** |
| CI：`The certificate was not trusted` / `errSecInternalComponent` | p12 密码不对，或 `KEYCHAIN_PASSWORD` 含特殊字符被 shell 吃掉，换成纯字母数字 |
| IPA 装上后**秒退** | Profile 里没有这台 iPhone 的 UDID；重新添加设备并**重新生成下载** Profile，再填一次 Secret |
| 打开时「无法验证 App」 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| 免费签名的 App 7 天后打不开 | 正常，重签一次即可，数据不丢 |
| 编译报 `Cannot find type 'Tab' in scope` | 你用了 Xcode 14（iOS 17 SDK 以下）；升级 Xcode，或让我把代码退回 iOS 16 写法 |
| 构建成功但装在老 iPhone 上秒退 | 设备系统低于 iOS 17，告诉我机型，我下调部署目标 |

---

## 建议

- 只想先看看长什么样 → **路线 A**
- **你有证书（你的情况）→ 路线 C**：推到 GitHub、填 7 个 Secrets、点一次 Run workflow，10 分钟拿到可直装 IPA
- 不想配 Secrets、拿 IPA 自己签 → **路线 D**（同一套代码，零配置）
- 手上就有 Mac → **路线 B**，后续改代码最方便

### 你的最短路径（iPhone 13 Pro + 有证书）

```bash
git init && git add . && git commit -m "NovelReader"
git remote add origin https://github.com/<你的用户名>/NovelReader.git
git push -u origin main
```

然后：填 7 个 Secrets → Actions → **Build Signed IPA (installable)** → `development` → 下载 → 爱思助手安装 → 设置里信任。
iPhone 13 Pro 支持 iOS 17，工程无需任何改动。
