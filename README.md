<img src="files/app.ico" width="72" align="right" alt=""/>

# ai-wallpaper 🖼️

为 **ZCode 等 11 个主流 AI 桌面应用**注入**动态壁纸背景**的社区补丁，配套统一壁纸管理器「AI 壁纸设置」（另含经 Windows Terminal 承载的 **PowerShell / CMD** 零补丁目标）：

- 🎬 用**任意图片或视频**（mp4 / webm / gif / webp / png / jpg）作为整个界面的背景，视频静音循环播放
- 🌌 未设置壁纸时显示内置的**动态极光渐变**兜底
- 🪟 自动把界面面板改为半透明"玻璃"效果，弹窗保持高不透明度保证可读
- 🖱️ 现代 GUI 壁纸选择器（深色圆角界面、实时预览、拖拽导入）
- 📚 **壁纸库**：设置过的壁纸全部保留，缩略图网格管理，随时一键切回
- 🔄 **自动轮换**：勾选后每次打开应用自动换用库中勾选的下一张壁纸，重启进度不丢
- 🤖 **AI 生成壁纸**：内置「AI 生成」页，调用豆包 Seedream 图像生成（火山方舟 API），输入描述直接生成壁纸并入库，一键换上
- 🎛️ 所有透明度参数集中在壁纸目录下的 `custom.css`，改完重启即见，**无需重新打补丁**
- 🩹 **一键修复**：应用升级覆盖补丁后，选择器自动发现失效并弹警告条，一键自动识别安装目录重打补丁（补丁脚本随安装部署到本机，无需找回仓库）
- ↩️ 一键回滚：补丁自动备份原程序文件

> ⚠️ **本项目不分发任何第三方应用本体**，只分发补丁脚本和我们自己编写的注入文件。安装时在你本机的程序上执行修改，原文件自动备份。

---

## English

**ai-wallpaper** is a community patch that brings **animated wallpaper backgrounds** to **11 popular AI desktop apps** (ZCode and more — the full list is in the Chinese docs), plus a unified GUI wallpaper manager. Zero-patch targets for **PowerShell / CMD** (via Windows Terminal) are included as well.

- 🎬 Use **any image or video** (mp4 / webm / gif / webp / png / jpg) as the app's full-window background — videos loop silently
- 🌌 Built-in animated aurora gradient as the fallback when no wallpaper is set
- 🪟 Panels automatically turn into translucent "frosted glass" while dialogs stay opaque for readability
- 🖱️ Modern GUI wallpaper picker (dark UI, live preview, drag & drop import)
- 📚 Built-in wallpaper library with thumbnail grid and one-click restore
- 🔄 Auto-rotate: cycle through selected wallpapers on every app launch
- 🤖 AI-generated wallpapers (Doubao Seedream) straight from the picker
- 🩹 One-click repair: after an app update breaks the patch, the picker detects it and re-applies automatically (install dir is re-discovered on the fly)
- ↩️ Fully reversible — original program files are backed up automatically

> ⚠️ This project does **not** distribute any third-party app binaries — only our own patch scripts and injection files. Patches are applied to apps already installed on your machine, with automatic backups.
>
> 📖 The rest of this README (usage, per-app technical notes, troubleshooting) is written in Chinese.

## 效果预览

视频壁纸 + 半透明界面（壁纸为用户自选的 mp4，静音循环播放）：

![视频壁纸效果](docs/screenshot-wallpaper.png)

内置的 GUI 壁纸选择器：

![壁纸选择器](docs/screenshot-picker.png)

## 效果

| 状态 | 说明 |
|---|---|
| 未设置壁纸 | 界面半透明 + 蓝紫极光渐变缓慢漂移 |
| 设置图片 | 图片铺满窗口（object-fit: cover）+ 可调暗色遮罩 |
| 设置视频 | 视频铺满窗口静音循环播放 |

补丁生效后，ZCode 窗口标题末尾会出现 **✦** 标记。

## 环境要求

- Windows 10/11
- ZCode Desktop 3.x / OpenCode Desktop / Codex（微软商店 MSIX 包，其他 Electron 应用原理相同，注入点可能不同，见下方"工作原理"）
- **PowerShell / CMD 壁纸目标需要 Windows Terminal**（商店版 / 预览版 / 散装版均可；Win11 默认自带）
- Node.js（仅打补丁时需要，用到 `npx @electron/asar`；日常使用不需要）

## 安装

```powershell
# 在仓库目录下执行（asar/文件型应用需处于关闭状态；豆包无需关闭）
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1                    # ZCode
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App OpenCode     # OpenCode
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App WorkBuddy    # WorkBuddy
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Codex        # Codex（散装副本+CDP 代理，见下方「工作原理」）
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Doubao       # 豆包（不改程序文件，免 Node）
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Marvis       # 腾讯 Marvis（离线页内联补丁，零 UAC、免 Node）
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App DeepSeekHarness  # DeepSeek Harness（回环前端页内联补丁，零 UAC、免 Node）
```

脚本会自动：

1. 探测 ZCode 安装目录（也可用 `-InstallDir "D:\..."` 指定；Codex 经 `Get-AppxPackage` 解析商店包目录）
2. 备份 `resources\app.asar` → `resources\app.asar.zwp-backup`（Codex 为 MSIX 包，备份放 `%LOCALAPPDATA%\OpenAI.Codex\zwp-backup\`）
3. 解包 → 注入壁纸脚本 → 重新打包并校验（WorkBuddy / OpenCode / Codex 为原地补丁）
4. 创建壁纸目录 `%USERPROFILE%\.zcode\wallpaper\`（OpenCode 为 `~\.opencode\wallpaper\`、Codex 为 `~\.codex\wallpaper\`，含 `custom.css` 调参模板）
5. 在桌面和开始菜单创建「AI壁纸设置」统一选择器快捷方式（exe 启动器 `AI壁纸设置.exe`，无黑窗、
   任务栏图标正确；`AI壁纸设置.cmd` 保留作备用入口）

**豆包桌面版**例外：它是 Chromium 壳（主窗口为 `chrome://doubao-chat` 内部页，非 Electron），不改任何程序文件——
安装只做三件事：把 CDP 代理启动器部署到 `%USERPROFILE%\.ai-wallpaper\`、把开始菜单「豆包」快捷方式改指该启动器
（图标不变）、创建壁纸目录 `~\.doubao\wallpaper\`。之后**从「豆包」快捷方式启动**即带壁纸；
换壁纸 / 轮换 / 恢复极光**热生效，无需重启豆包**。

**腾讯 Marvis** 走**离线页内联补丁**（Qt5 + CEF 壳，详见下方「工作原理」）：改的是用户可写的
Roaming 离线缓存（`%APPDATA%\Tencent\Marvis\marvis-offline-page\using\`），安装/修复**零 UAC、免 Node、
无需关应用**；换壁纸经 refresh 标记热生效。任意方式启动 Marvis（官方快捷方式/开机自启）都带壁纸。

**DeepSeek Harness**（开源 DSH Desktop，`%LOCALAPPDATA%\Programs\DSH Desktop`）与 Marvis 同款
**回环前端页内联补丁**：壁纸脚本内联进 `resources\app\node_modules\@deepseek-ai\dsh-web-frontend\dist\index.html`，
媒体走回环服务的 `/dsh` 虚拟根（`~\.dsh\wallpaper\`）。零 UAC、免 Node、无需关应用；正常快捷方式启动即带壁纸。

**Windows PowerShell / CMD 是零安装目标**：无需运行 apply-patch，也无需关闭任何程序——只要检测到
Windows Terminal 的 `settings.json`（商店版 / 预览版 / 散装版任一），选择器启动时自动创建壁纸目录
（`~\.terminal\wallpaper-ps\`、`~\.terminal\wallpaper-cmd\`）并把两个目标常驻列表。见下文专节。

完成后启动 ZCode，看到标题 **✦** 即生效。

## 使用壁纸

- 双击桌面的 **AI壁纸设置**（统一选择器，装在 `%USERPROFILE%\.ai-wallpaper\`）→ 选择图片 / 视频（或直接拖文件进窗口）→ 几秒内自动生效，无需重启
- **「当前壁纸」页按应用单独显示**：顶部下拉框切换要查看的应用，预览与角标显示该应用**实际生效**的壁纸
  （轮换中的应用显示轮换集与换片节奏，未设置的显示极光兜底）；选择图片 / 恢复极光 / 重启 / 不透明度都只作用于当前查看的应用
- **「壁纸库」页**顶部的**应用芯片**勾选批量操作的目标应用（ZCode / WorkBuddy / OpenCode / Codex，自动探测）：
  - **同步设置开**（默认）：一套壁纸与轮换设置应用到所有勾选的应用
  - **同步设置关**：只改当前勾选的应用，其他应用保持各自的壁纸与轮换设置
- **共享壁纸库**存放在 `%USERPROFILE%\.ai-wallpaper\library\`，所有应用共用；各应用旧库会自动导入
- **「界面不透明度」滑杆**（当前壁纸页）：调整界面面板的透明程度，写入各应用 `custom.css` 的
  `--ocwp-ui-alpha` 管理块，拖动后几秒内热生效；同时作用于当前查看的应用与所有勾选应用
- 「壁纸库」页签里可以：单击卡片「应用」到目标应用、勾选「轮换」、删除不要的；视频卡片悬停即原地预览播放（移开恢复静态帧）
- 选择器的改动会写入 refresh 标记（编号每应用独立计数、按 1..3 循环——兼容 asar 里已部署的
  旧版注入脚本，它只探测 refresh-1..3；写到 4/5 它永远看不见，表现为壁纸迟迟不切换），
  应用内的壁纸脚本每 5 秒探测一次，**改完几秒内自动切换，无需重启**；「重启应用」按钮作为兜底

### 自动轮换

在「壁纸库」页签打开 **"打开 ZCode 时自动更换壁纸"** 开关，并勾选想参与轮换的壁纸。
之后**每次打开 ZCode**（无论手动启动还是从选择器重启）都会自动换用勾选壁纸中的下一张，
轮换进度保存在应用本地，重启、升级都不丢。关闭开关即固定为当前壁纸。

也可以手动把文件改名为 `wallpaper.扩展名` 放进 `%USERPROFILE%\.zcode\wallpaper\`（不经过库）。
多个文件同时存在时按 `mp4 → webm → gif → webp → png → jpg` 优先。

## PowerShell / CMD 壁纸（Windows Terminal）

PowerShell 与 CMD 由 Windows Terminal（WT）承载，壁纸走 **WT profile 方案**（零补丁、零进程注入）：
把背景图写入 `settings.json` 的背景三键，**profile 本体与 `profiles.defaults` 双写**，WT 监听该文件
改动**自动热加载**——换壁纸、调不透明度对已打开的终端窗口即时生效，无需重启任何东西。

- ⚠️ **键名必须是 `backgroundImage`**：旧名 `backgroundImagePath` 在 WT 1.24 已静默失效
  （设置解析正常、无报错，但背景图就是不渲染——实测踩坑）
- ⚠️ **必须双写 defaults**：从开始菜单/任务栏直接打开 cmd / powershell 时，WT 以「控制台接管」标签
  承载——它**不绑定任何 profile**，只继承 `profiles.defaults`；仅写 profile 的键只对 `wt -p` /
  WT 下拉菜单按 profile 开的标签生效。defaults 跟随"最后应用的终端目标"（从开始菜单打开时，
  cmd 与 powershell 显示同一张图——WT 层面无法区分接管窗口对应哪个 shell）
- **媒体适配**：png / jpg / bmp 直接用；**gif 动图 WT 原生支持动画**；视频（mp4 / webm）与 webp
  会用库自带的 ffmpeg（`~\.ai-wallpaper\bin\`）**自动抽帧转 png**（取第 1 秒画面），ffmpeg 缺失时
  明确报错并保留原壁纸
- **不透明度滑杆语义与其他应用一致**（越高界面越实）：映射为 WT 的 `backgroundImageOpacity = 1 - 滑杆值`，
  默认 55% → 图片不透明度 0.45；拉伸模式固定 `uniformToFill`（等同其他应用的 cover）
- **恢复极光 = 恢复纯色**：终端没有极光兜底，清除壁纸即移除背景三键（profile 无条件清；defaults
  仅在正指向该应用壁纸时才清，避免误删另一终端目标写入的值），回到 WT 默认背景色
- **自动轮换降级**：WT 没有轮换脚本可驱动，开启轮换时把轮换集第 1 张固定为当前壁纸
- **profile 定位**：优先按 WT 动态 profile 的规范 GUID 精确匹配（PowerShell
  `{61c54bbd-c2c6-5271-96e7-009a87ff44bf}`、命令提示符 `{0caa0dad-35be-5f56-a8ff-afceeeaa6101}`），
  找不到再按名称锚定回退，仍没有则在 `profiles.list` 追加最小条目（WT 会按 GUID 与内置动态 profile 合并）
- **兼容细节**：settings.json 按 JSONC 解析（容忍注释），写回保留原 BOM 状态；写入时自动清理旧键名
  `backgroundImagePath`（自愈旧数据）；「重启应用」按钮对终端目标显示「热生效 · 免重启」并拒绝杀终端
- **前提**：终端窗口须由 WT 承载（Win11 默认）。若把默认终端改回了经典 conhost，壁纸不生效
  （conhost 无背景图能力）；在 WT 设置 UI 里改「外观」同名选项会覆盖本补丁写入的值，属正常行为

## AI 生成壁纸（豆包 · Seedream）

选择器的「AI 生成 · 豆包」页可以直接用豆包的图像生成模型（Seedream，火山方舟 API）生成壁纸：

1. 填入**火山方舟 API Key** 并点「保存 Key」：火山引擎控制台 → 火山方舟 → API Key 管理；
   需在方舟开通**豆包·图像生成（Seedream）**模型后调用。Key 仅保存在本机 `%USERPROFILE%\.ai-wallpaper\doubao.json`
2. 输入画面描述（Ctrl+Enter 快速生成），按需选择模型、尺寸（2K / 4K 自适应，或 2560×1600 / 2048×1152 固定尺寸）与张数
3. 点「✨ 生成壁纸」：结果**自动存入共享壁纸库**（`ai-` 开头），点卡片「应用」立即换上——
   应用逻辑与「壁纸库」一致，同步模式下作用于所有勾选应用

- 默认模型 `doubao-seedream-4-0-250828`；方舟上线新模型后，直接在模型框粘贴新模型 ID 或推理接入点 `ep-xxx` 即可
- 生成在后台进行，不卡界面；失败时状态栏显示方舟返回的错误（Key 无效 / 未开通模型 / 余额不足等）
- API 调用按火山方舟计费，与本项目无关；生成请求固定关闭水印（`watermark: false`）

## 应用升级后一键修复

应用升级会覆盖补丁文件（ZCode/WorkBuddy/OpenCode 重写 `app.asar`，Codex 商店整包替换），壁纸随之失效。
「AI壁纸设置」每次打开时会**自动体检**所有应用：哪个补丁丢了，顶部立即出现 ⚠ 警告条，点**「一键修复」**即可：

1. **自动识别安装目录**（按优先级依次回退）：运行中进程 → 已知候选路径 → 开始菜单快捷方式 →
   注册表卸载信息（DisplayName / DisplayIcon 反查）→ MSIX 包（`Get-AppxPackage`）。
   全部落空时弹文件夹选择框人工指认。升级换了安装目录也能跟上。
2. 关闭正在运行的目标应用（带确认，修完可一键重启），后台调用补丁脚本重打
   （补丁脚本及其依赖在安装时已复制到 `%USERPROFILE%\.ai-wallpaper\repair\`，离线可用）
3. 修复后自动复检并汇报；Codex 需 UAC 管理员授权，授权完成每 3 秒自动复检（也可手动「重新检测」）

命令行同样把 `apply-patch.ps1` 当修复工具用——它现在是**幂等**的：

```powershell
# 补丁完好 → 直接跳过（应用无需关闭，零改动）；补丁丢失 → 自动识别目录重打
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App WorkBuddy
# 补丁还在但想强制重打（先从原版备份还原再重装，用于换注入脚本版本等场景）
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App WorkBuddy -Force
```

健康判定无需解包：asar 头部 JSON 明文列出归档内文件名，只读前 8MB 检索 `oc-wallpaper` 条目即可，亚秒级。

## 调整透明度

编辑 `%USERPROFILE%\.zcode\wallpaper\custom.css`（文件内有注释模板），改动会在下一次标记刷新时自动重载（几秒内）。删除该文件即恢复默认值。

## 卸载 / 回滚

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -Rollback
```

## 工作原理

ZCode Desktop 是 Electron 应用，界面打包在 `resources\app.asar` 中：

1. 解包 asar，得到 `out\renderer\index.html`（主窗口入口）
2. 在 index.html 的主 bundle `<script>` 之前插入一行 `<script src="./oc-wallpaper.js"></script>`
3. `oc-wallpaper.js` 在页面加载最早期：
   - 注入 CSS 把 Tailwind 语义变量（`--color-background`、`--color-panel`、`--color-sidebar` 等）覆盖为半透明值
   - 创建 `position:fixed; z-index:-1` 的壁纸层，探测壁纸文件（视频/图片元素方式加载，无跨域问题）
   - 没有壁纸文件时启用 CSS 动画极光兜底
4. 重新打包 asar 替换回去（`--unpack` 保持原生模块外置，打包后与原 `.unpacked` 目录清单比对校验）

**WorkBuddy**（腾讯，Electron 37）不能走解包重打包，有三处特殊处理，由零依赖的 `files/patch-inplace.js` 完成：

1. **asar 原地补丁**：其 asar 索引引用了约 3000 个 unpacked 文件（含安装器未落盘的跨平台残留条目），
   解包重打包会破坏结构。原地补丁只改写头部 + 把新的 index.html / 注入脚本追加到归档末尾，
   数据区与 `.unpacked` 完全不动，随后逐文件重算 SHA256 自校验后才替换。
2. **主程序内嵌哈希同步**：WorkBuddy 主程序开启了 Electron 的 asar 完整性 fuse
   （`EnableEmbeddedAsarIntegrityValidation`），exe 内嵌 JSON 存有 app.asar 头部的 SHA256，
   头部一变应用就会在启动时被静默处决。补丁脚本会把 exe 里的旧哈希等长替换为新哈希（两处）。
   ⚠️ 副作用：主程序的腾讯官方数字签名会失效（应用功能不受影响），在意签名校验的场景请勿使用。
3. **透明化（含菜单不透明）**：WorkBuddy 用 VS Code 主题变量 + 自带皮肤系统（`--wb-*` 设计令牌，
   主题装载在构造式样式表 adoptedStyleSheets 里，页面级容器还会重新声明变量）。运行时脚本三管齐下：
   内联 `!important` 覆盖 `--vscode-*`、改写 CSSOM 里 `--wb-home-bg-*` / `--wb-bg-*` 等作用域
   声明（保留原色只压 alpha）、皮肤渐变图变量置空，并监听主题切换自动重覆盖。
   **菜单 / 弹层 / 模态框保持完全不透明**：`--wb-bg-popover`、`--wb-bg-modal`、
   `--wb-dropdown-*` 等弹层令牌不参与改写，统一钉在随主题切换的 `--ocwp-popup-bg`（浅色 #ffffff / 深色 #252526）上。

**OpenCode Desktop**（`@opencode-aidesktop`）同样走原地补丁 + 两处特殊处理：

1. **asar 原地补丁**：与 WorkBuddy 同因——asar 索引含悬空 unpacked 引用和嵌套的 `app.asar.unpacked` 树，
   解包重打包会把外置文本文件嵌回归档。其 asar 完整性 fuse 实测为关闭，因此无需改主程序内嵌哈希。
2. **主进程 `wp://` 协议桥**：渲染页面由自定义协议 `oc://` 加载，Chromium 会拦截 `file://` 子资源
   （壁纸文件全部 "Not allowed to load local resource"）。补丁在主 bundle 的
   `registerSchemesAsPrivileged([...])` 里追加 `wp` 特权协议，并在文件末尾追加一段 ESM 桥接代码：
   `protocol.handle('wp')` 把 `wp://local/...` 映射到 `~\.opencode\wallpaper\`（路径白名单校验、
   支持 Range 视频拖动），注入脚本即通过 `wp://` 加载壁纸、轮换图与 `custom.css`。
3. **透明化**：界面用 v2 设计令牌（`bg-v2-background-*` 工具类），脚本同时覆盖旧版
   `--background-*` 与 `--v2-background-bg-base/deep/layer-01..04` 两组变量，
   暗色模式走 `:root[data-color-scheme="dark"]` 属性选择器。

**Codex 桌面版**（微软商店 `OpenAI.Codex` MSIX 包，`app\ChatGPT.exe`，Owl shell = OpenAI 定制 Chromium 152 + Electron 兼容层）走**散装副本 + CDP 代理**方案（2026-09-15 定稿，此前试验的原地补丁被系统拦停）：

1. **为什么放弃原地补丁**：包文件受系统内核级保护——takeown + icacls 拿到 FullControl 后写入/新建仍被拒
   （build 26340 实测，与安全软件无关）；且新版 owl 运行时会吞掉激活参数（社区 CDP 注入法在 ≥26.715 同样失效）。
2. **散装副本**：整包复制到 `%USERPROFILE%\CodexPatched`（普通可写目录）→ 移除商店包 →
   `ChatGPT.exe` 以普通程序直接带 `--remote-debugging-port` 启动。散装 asar 仍打过 wp:// 桥补丁备用，
   但媒体子资源会被该版 Chromium 的 URL 安全检查拒绝，壁纸改走 3 的通道。
3. **CDP 代理**（`codex-launcher.ps1`）：带端口拉起 Codex → 壁纸经 `app://fs/@fs/<路径>` 文件直通供给
   （应用自己的文件协议，不受媒体 URL 安全检查限制，**暂只支持图片壁纸**）→ CDP 注入壁纸层 +
   透明化 CSS（`--color-surface-*` / `--color-background-*` 令牌，`.electron-light/.electron-dark` 主题类）；
   桌面/开始菜单「ChatGPT」快捷方式指向启动器，普通方式启动不带壁纸。

OpenCode / WorkBuddy / Codex 的壁纸目录与选择器快捷方式按应用名自动区分，互不影响。

**豆包桌面版**（`F:\Program files\Doubao` 等，Chromium 147 定制壳，非 Electron）走完全不同的 **CDP 代理方案**：

1. 主窗口是内部页 `chrome://doubao-chat/chat`，UI 走自定义协议从本地缓存加载——内容脚本与 asar 补丁都不适用；
   程序文件也不改（无备份/回滚文件，应用升级零影响）。
2. 安装部署的 `doubao-launcher.ps1` 代理以**仅本机环回**的固定调试端口（19222-19226 白名单）拉起豆包，
   通过 DevTools 协议向聊天窗口注入壁纸层 + 透明化 CSS；壁纸以 base64 分块传输（2MB/块）内嵌为 data URL，
   视频（实测 4K mp4）与图片都支持。
3. 透明化：主题变量在 `:root`、`body`、`#chat-route-layout` 三层都有定义，需在三层同时覆盖
   `--chat-bg-color` / `--color-bg-body` / `--dbx-bg-base-web` 等；深色模式是 `html[data-theme="dark"]`，
   两套半透明值随主题自动切换。页头与输入框用元素级 `!important` 规则兜底。
4. 代理常驻监视壁纸目录（`~\.doubao\wallpaper\`），换壁纸 / 轮换槽位变化几秒内**热推送**到所有聊天窗口，
   无需重启；单实例互斥锁防重复注入；豆包退出后代理自动退出。
5. ⚠️ 壁纸只在**从「豆包」快捷方式启动**时加载（快捷方式带调试端口参数）；从豆包自带更新器或
   `app\Doubao.exe` 直接启动则无壁纸。选择器「重启应用」会经启动器重启，自动带上。

**腾讯 Marvis**（`C:\Program Files\Tencent\Marvis`，Qt5 + CEF 壳，非 Electron）走**离线页内联补丁**，与以上各家机制差异最大：

1. **主窗口是 CEF 视图**，加载 `https://yyb-ai-launcher-offline.qq.com/index.html`——实为本地离线包
   经 CEF 拦截器服务（`ai_starter::OfflinePage`）。真正被服务的目录是**用户可写的 Roaming 缓存**
   `%APPDATA%\Tencent\Marvis\marvis-offline-page\using\`（安装目录里的 `marvis-offline-page\` 只是
   种子副本，改它无效——这一步踩过坑）。补丁 = 把壁纸脚本**内联**进该目录的 `index.html`
   （拦截器不保证服务新增文件，外链脚本实测 404，必须内联）。
2. **CDP 调试端口实测不可行**：`Marvis.exe` 里虽有 `--remote-debugging-port` 字样，但 CEF 的
   DevTools 端口只能由原生 `CefSettings` 开启，命令行开关对该构建无效（带参重启后端口始终不启动）。
   `Marvis.exe` 清单为 `requireAdministrator`，因此仅"重启 Marvis"这一步需要管理员（与平时启动一致），
   打补丁本身零 UAC。
3. **媒体/样式/轮换标记走本机回环 HTTP 服务**（`http://127.0.0.1:19399`，`zwp-media-server.ps1`，
   计划任务「AI壁纸媒体服务」登录自启）：离线页拦截器是**白名单式**——junction/新增文件一律拒绝
   （实测 `zwp-media/wallpaper.mp4` 走真实网络报 -2），所以媒体改由回环服务供给壁纸目录。
   127.0.0.1 是 Chromium 认定的安全来源；注入时同步移除 `index.html` 的
   `upgrade-insecure-requests` CSP meta（否则 http 被强制升级 https 而失效）。
4. **透明化用运行时自适应扫描**：界面是 CSS-in-JS（构建期哈希类名，随版本变化，CSS 猜测不可靠）。
   注入脚本在页面里扫描"盖住几乎整个视口、或全高侧栏"的大块不透明背景，统一压到 alpha 0.45
   （React 异步挂载，0/2.5/6 秒各跑一遍）；卡片/弹窗等小块不动保证可读性。另加根透明 +
   `--default-bg-color` 变量 + body 壁纸图兜底（视频壁纸时该图加载失败自动让位）。
   窗口标题不显示 ✦（Qt 标题不跟随页面标题），**以壁纸可见为准**。
5. **无轮换/热点探测的缓存穿透参数**（`?v=`/`?t=` 已全部去掉）：拦截器对带查询串的 URL 行为未知；
   代价是同名壁纸文件被覆盖后需要重启才刷新，选择器换壁纸（写不同文件名/轮换标记）不受影响。

**DeepSeek Harness**（开源 [DSH Desktop](https://github.com/anywhere-labs/dsh-desktop)，MIT，Electron 43 壳 +
内嵌 NodeService 回环 webserver）走**回环前端页内联补丁**，机制与 Marvis 最近似：

1. **主窗口 `loadURL` 到 `http://127.0.0.1:<动态端口>/`**：官方 Web UI 由壳内嵌的 harness host 服务，
   端口动态、来源带校验（外部 `curl` 一律 403），页面对应安装目录里**散装可写**的
   `resources\app\node_modules\@deepseek-ai\dsh-web-frontend\dist\index.html`（Vite SPA）。
   补丁 = 壁纸脚本**内联**进该文件（无 asar、无 fuse，改文件即可）。
2. **媒体/样式/轮换标记走回环媒体服务的 `/dsh` 虚拟根**（与 Marvis 共用同一个服务与计划任务；
   `apply-patch -App DeepSeekHarness` 会检测旧版服务并热重启升级，路由见 `zwp-media-server.ps1`）。
3. **透明化**：主题令牌 `--dsw-alias-bg-base` / `--dsw-alias-bg-layer-1` 在 `body`（浅色）与
   `body[data-ds-dark-theme]`（深色）两处同源覆盖——基底透明、主面板改半透明磨砂
   （custom.css 的 `--ocwp-ui-alpha` 可调，0~1）；卡片/弹层令牌 layer-2/3 保持原色保证可读性；
   另有大色块运行时扫描兜底（与 Marvis 同款）。
4. **autoplay 策略**：该壳限 `user-gesture-required`，脚本直接 `play()` 会被拒——注入脚本先 seek
   到第 2 秒跳过壁纸视频的黑场片头（暂停态显示有效画面），首次点击/按键/滚轮即解锁循环播放。
5. **外壳拦截「跨源 + 带查询串」的请求**（同源带串、跨源无串均正常，实测）→ 与 Marvis 同款限制：
   不用缓存穿透参数，轮换集（不同 URL）热切换正常，同名 wallpaper.* 覆盖需重启才可见。
6. 兼容模式的顶部控制条是独立的 `compatibility-chrome.html` 窗口（file://），保持原样不透明；
   窗口标题被外壳接管时 ✦ 标记不显示，以壁纸可见为准。

Electron 的 asar 本质是一个打包格式，任何 Electron 应用的 HTML 入口都可以用同样的思路注入自定义 CSS/JS——欢迎参考改造其他应用。

## 已知限制

- 应用**升级后补丁会被覆盖**：打开「AI壁纸设置」点**一键修复**即可（见上文），或重新执行 `apply-patch.ps1`（先更新本仓库以适配新版，主 bundle 文件名带 hash 会变化，脚本用正则定位所以通常无需改动）。WorkBuddy 升级还会恢复其主程序（含新的内嵌哈希），重新打补丁即可。**Codex 的商店更新是整包替换**（安装目录版本号变化），更新后一键修复会重新走 UAC 授权补上。豆包升级**不受影响**（未改程序文件），从快捷方式启动即可。
- 豆包壁纸依赖「豆包」快捷方式携带的调试端口参数：开机自启 / 固定到任务栏的入口若直接指向官方 exe 则无壁纸；调试端口仅监听 127.0.0.1 且限白名单端口段
- Marvis 的壁纸补丁在 Roaming 离线缓存里，**Marvis 自动更新离线页会覆盖补丁**：一键修复或重跑 `apply-patch.ps1 -App Marvis` 即可（零 UAC）。重启 Marvis 需管理员（其 exe 清单 requireAdministrator）；热切换已去掉缓存穿透参数，手动覆盖同名壁纸文件需重启才刷新；窗口标题不显示 ✦ 属正常。媒体服务（127.0.0.1:19399）只监听本机回环、仅服务壁纸目录，由计划任务「AI壁纸媒体服务」登录自启
- DeepSeek Harness（DSH Desktop）同受「跨源带查询串被外壳拦截」限制：**选择器覆盖同名壁纸文件后需重启应用**才可见（轮换集热切换正常）；未交互前视频壁纸暂停在第 2 秒画面（autoplay 需用户手势，首次点击/按键即开始播放）；应用升级覆盖补丁后重跑 `apply-patch.ps1 -App DeepSeekHarness`（零 UAC、免关应用）
- WorkBuddy 个别深度定制的浮层可能仍不透明，可往 `custom.css` 加针对性覆盖；其自带的"个性主题/皮肤"与透明化叠加生效，建议二选一
- Codex 修改过包内文件后，商店对已安装包的"修复/重置"会把文件还原；MSIX 签名不再匹配完整的 BlockMap（应用功能不受影响，但增量更新可能退化为全量下载）
- 硬编码的 Tailwind 类 / 背景色（不走主题变量）的组件不会被透明化
- 视频壁纸占用 GPU，低配机器建议用图片或 gif
- PowerShell / CMD 壁纸只在 Windows Terminal 承载时生效（经典 conhost 无背景图能力）；WT 不支持
  视频背景，应用视频时自动降级为抽帧静态图；设置 WT 自带「外观」里同名选项会覆盖本补丁写入的值

## 2026-09-15 审查修复

全面代码审查后修复的问题（v2.1.1）：

- **P0 · 硬链接写穿污染中心库**：旧壁纸被运行中应用占用、删/改名都失败时，选择器的回退复制会
  覆写现存硬链接路径，把新内容写进中心库文件本身（所有应用的壁纸一起被改）。现在该场景明确
  报错并跳过，不再覆写。
- **P1 · 全新机器首装代理型应用必崩**：agent/Marvis/DSH 分支往 `~\.ai-wallpaper` 拷启动器时
  hub 目录尚未创建（创建代码在所有分支之后），`Copy-Item` 直接崩；Marvis/DSH 还会留下
  "补丁已上、媒体服务未部署"的半成品。hub 目录现已提前创建。
- **P1 · 一键修复链路自复制**：health-check / 选择器运行的是 `repair\` 里的 apply-patch 副本，
  收尾时"复制自己到自己"必抛错，补丁已好却被误报失败。已加源=目标检测。
- **P1 · UAC 提权丢失 -Force**：AutoClaw 等需提权场景下 `-Force` 未转发给提权子进程，强制重打
  被静默降级为 no-op。已转发。
- **P1 · 换片定时器生命周期（8 个注入脚本变体）**：关闭轮换/清空间隔后旧 `intervalTimer` 永远
  存活——视频壁纸每 N 分钟被重建闪断一次，或轮换关不掉。探测穷尽路径现在会清掉旧定时器；
  换片 tick 补 `document.hidden` 守卫，后台窗口不再换片（后台零解码真正闭环）。
- **P1 · vscode 变体 `customImgVars` 未声明**：每次 fullPass 必抛 ReferenceError 且被空 catch
  吞掉（WorkBuddy 背景图变量内联钉死功能从未生效）。已声明并在 CSSOM 扫描时动态收集。
- **P1 · 发布包漏运行时文件**：`wp-scheme-find/replace.txt` 是 OpenCode/Trae 系协议桥载荷，
  之前被当"探测残留"排除，安装包在新机器上给这三个应用打补丁必失败。v2.1.1 起正确打包
  （真正的一次性脚本 patch-codex-loose / fix-bridge-guard / -codex.txt 改为排除）。
- **P1 · health-check 的 Codex 探测过时**：仍按已废弃的 MSIX 原地补丁方案探测，商店包残留时
  误报、自动修复会误拉起商店版。已同步到"散装副本 + CDP 代理"方案（含未安装判定）。
- **选择器体验**：视频导入归一化移到后台进程（此前 UI 线程同步跑 ffmpeg，窗口假死数分钟，
  关窗时自动终止）；库网格改 480px 降采样解码（此前全分辨率解码，大库多 GB 内存）；修复
  "错误提示被成功文案覆盖"、非终端目标复制失败静默报成功的问题；热切换计数文件丢失时从
  现存标记续接编号（避免应用端漏检切换）；同秒导入加随机后缀防覆盖；WT settings.json 首次
  写回前自动留 `.zwp-backup`（JSONC 写回会剥注释）。
- **清理**：删除已废弃的 marvis-launcher（29KB 死代码，且其 `setBypassCSP` 参数名有误）；
  删除 codex-launcher 内嵌但从未启动的回环媒体服务器（约 70 行）；修正 Codex 启动器乱码的
  base64 中文串、Marvis/Reasonix 注入脚本描述旧方案的失实注释。

## 许可

本项目注入文件以 [MIT](LICENSE) 许可发布。ZCode / OpenCode 是其各自所有者的产品，本项目与其无隶属关系。
