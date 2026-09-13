<img src="files/app.ico" width="72" align="right" alt=""/>

# zcode-wallpaper 🖼️

给 **ZCode Desktop** 与 **OpenCode Desktop**（OpenCode 系 AI 编程客户端）注入**动态壁纸背景**的社区补丁：

- 🎬 用**任意图片或视频**（mp4 / webm / gif / webp / png / jpg）作为整个界面的背景，视频静音循环播放
- 🌌 未设置壁纸时显示内置的**动态极光渐变**兜底
- 🪟 自动把界面面板改为半透明"玻璃"效果，弹窗保持高不透明度保证可读
- 🖱️ 现代 GUI 壁纸选择器（深色圆角界面、实时预览、拖拽导入）
- 📚 **壁纸库**：设置过的壁纸全部保留，缩略图网格管理，随时一键切回
- 🔄 **自动轮换**：勾选"打开 ZCode 时自动更换"后，每次打开 ZCode 自动换用库中勾选的下一张壁纸，重启进度不丢
- 🎛️ 所有透明度参数集中在壁纸目录下的 `custom.css`，改完重启即见，**无需重新打补丁**
- ↩️ 一键回滚：补丁自动备份原程序文件

> ⚠️ **本项目不分发 ZCode 程序本体**，只分发补丁脚本和我们自己编写的注入文件。安装时在你本机的程序上执行修改，原文件自动备份。

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
- ZCode Desktop 3.x / OpenCode Desktop（其他 Electron 应用原理相同，注入点可能不同，见下方"工作原理"）
- Node.js（仅打补丁时需要，用到 `npx @electron/asar`；日常使用不需要）

## 安装

```powershell
# 在仓库目录下执行（目标应用需处于关闭状态）
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1                    # ZCode
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App OpenCode     # OpenCode
powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App WorkBuddy    # WorkBuddy
```

脚本会自动：

1. 探测 ZCode 安装目录（也可用 `-InstallDir "D:\..."` 指定）
2. 备份 `resources\app.asar` → `resources\app.asar.zwp-backup`
3. 解包 → 注入壁纸脚本 → 重新打包并校验
4. 创建壁纸目录 `%USERPROFILE%\.zcode\wallpaper\`（OpenCode 为 `~\.opencode\wallpaper\`，含 `custom.css` 调参模板）
5. 在桌面和开始菜单创建「<应用名>壁纸选择器」快捷方式

完成后启动 ZCode，看到标题 **✦** 即生效。

## 使用壁纸

- 双击桌面的 **ZCode壁纸选择器** → 选择图片 / 视频（或直接拖文件进窗口）→ 「重启 ZCode」生效
- 每张设置过的壁纸都会自动存入**壁纸库**（`%USERPROFILE%\.zcode\wallpaper\library\`）
- 「壁纸库」页签里可以：单击卡片应用为当前壁纸、勾选「轮换」、删除不要的

### 自动轮换

在「壁纸库」页签打开 **"打开 ZCode 时自动更换壁纸"** 开关，并勾选想参与轮换的壁纸。
之后**每次打开 ZCode**（无论手动启动还是从选择器重启）都会自动换用勾选壁纸中的下一张，
轮换进度保存在应用本地，重启、升级都不丢。关闭开关即固定为当前壁纸。

也可以手动把文件改名为 `wallpaper.扩展名` 放进 `%USERPROFILE%\.zcode\wallpaper\`（不经过库）。
多个文件同时存在时按 `mp4 → webm → gif → webp → png → jpg` 优先。

## 调整透明度

编辑 `%USERPROFILE%\.zcode\wallpaper\custom.css`（文件内有注释模板），保存后重启 ZCode。删除该文件即恢复默认值。

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
3. **透明化**：WorkBuddy 用 VS Code 主题变量 + 自带皮肤系统（`--wb-*` 设计令牌，主题装载在
   构造式样式表 adoptedStyleSheets 里，页面级容器还会重新声明变量）。注入脚本运行时三管齐下：
   内联 `!important` 覆盖 `--vscode-*`、改写 CSSOM 里 `--wb-home-bg-*` / `--wb-bg-*` 等作用域
   声明（保留原色只压 alpha）、皮肤渐变图变量置空，并监听主题切换自动重覆盖。

OpenCode / WorkBuddy 的壁纸目录与选择器快捷方式按应用名自动区分，互不影响。

Electron 的 asar 本质是一个打包格式，任何 Electron 应用的 HTML 入口都可以用同样的思路注入自定义 CSS/JS——欢迎参考改造其他应用。

## 已知限制

- 应用**升级后补丁会被覆盖**，需要重新执行 `apply-patch.ps1`（先更新本仓库以适配新版，主 bundle 文件名带 hash 会变化，脚本用正则定位所以通常无需改动）。WorkBuddy 升级还会恢复其主程序（含新的内嵌哈希），重新打补丁即可。
- WorkBuddy 个别深度定制的浮层可能仍不透明，可往 `custom.css` 加针对性覆盖；其自带的"个性主题/皮肤"与透明化叠加生效，建议二选一
- 硬编码的 Tailwind 类 / 背景色（不走主题变量）的组件不会被透明化
- 视频壁纸占用 GPU，低配机器建议用图片或 gif

## 许可

本项目注入文件以 [MIT](LICENSE) 许可发布。ZCode / OpenCode 是其各自所有者的产品，本项目与其无隶属关系。
