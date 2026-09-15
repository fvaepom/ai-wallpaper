# ai-wallpaper — ZCode / OpenCode / WorkBuddy / Codex Desktop / Trae CN / Trae Work / Doubao 动态壁纸补丁
# 用法：
#   ZCode:     powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1
#   OpenCode:  powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App OpenCode
#   WorkBuddy: powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App WorkBuddy
#   Codex:     powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Codex
#              （微软商店 MSIX 包，脚本会自动请求管理员授权；商店更新应用后需重新执行）
#   Trae CN:   powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App TraeCN
#   Trae Work: powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App TraeWorkCN
#              （两者为散装 resources\app 目录，零依赖直改文件；应用升级后需重新执行）
#   Doubao:    powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Doubao
#              （Chromium 壳 CDP 代理方案：不改程序文件、免关应用、免 Node；升级不影响，重跑即可）
#   Marvis:    powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Marvis
#              （腾讯 Marvis = Qt5+CEF 壳，同 CDP 代理方案；Marvis.exe 需管理员，启动经 UAC，同平时一致）
#   Reasonix:  powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App Reasonix
#              （launcher+versions 布局的 Electron 壳，散装直改；应用升级换版本目录后需重新执行）
#   DeepSeek Harness: powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App DeepSeekHarness
#              （开源 DSH Desktop 的回环前端页内联补丁 + 回环媒体服务，同 Marvis 架构；
#               不需要 Node、免关应用；应用升级覆盖补丁后重跑即可）
#   回滚:      powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 [-App <名称>] -Rollback
#   升级后修复: 应用更新会覆盖补丁文件；重新运行与安装相同的命令即可——脚本自动识别安装目录、
#              检测到补丁仍在时直接跳过（幂等），补丁丢失时自动重打。「AI壁纸设置」的一键修复即调用本脚本。
# 需要: Node.js（ZCode/OpenCode/Codex 用 npx @electron/asar 或内置 patch-inplace.js，WorkBuddy 用内置 patch-inplace.js，零依赖），
#       Trae 系直改文件不需要 Node。目标应用处于关闭状态。

param(
    [string]$App = 'ZCode',
    [string]$InstallDir = '',
    [switch]$Rollback,
    [switch]$Force,     # 已打过补丁也强制重打（先从原版备份还原再重装）
    [switch]$NoShortcut,
    [switch]$Elevated   # 内部标记：本次是 UAC 提权后的子实例，结束前暂停便于查看输出
)

$ErrorActionPreference = 'Stop'
$Script:RepoFiles = Join-Path $PSScriptRoot 'files'

function Write-Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# ── 每个应用的补丁配置 ──────────────────────────────────
$Apps = @{
    'ZCode' = @{
        Process     = 'ZCode'
        WallDir     = Join-Path $env:USERPROFILE '.zcode\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ZCode.lnk"
        Candidates  = @('F:\Program files\ZCode', 'C:\Program files\ZCode',
                        "$env:LOCALAPPDATA\Programs\zcode", "$env:LOCALAPPDATA\Programs\ZCode")
        # 解包 → 注入 → 重打包（asar 内目录 out\renderer，Tailwind 语义变量透明化）
        RendererDir = 'out\renderer'
        InjectSrc   = 'oc-wallpaper.js'
        Method      = 'repack'
        # 多锚点回退：应用升级改版后逐个尝试，提高重打成功率
        BundleRegex = @('(<script type="module" crossorigin src="\./assets/index-[^"]+\.js"></script>)',
                        '(<script[^>]+type="module"[^>]+src="\./assets/index-[^"]+\.js"[^>]*></script>)',
                        '(<script[^>]+src="\./assets/index-[^"]+\.js"[^>]*></script>)')
    }
    'OpenCode' = @{
        Process     = 'OpenCode'
        WallDir     = Join-Path $env:USERPROFILE '.opencode\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OpenCode.lnk"
        Candidates  = @("$env:LOCALAPPDATA\Programs\@opencode-aidesktop",
                        'F:\Program files\OpenCode', 'C:\Program files\OpenCode',
                        "$env:LOCALAPPDATA\Programs\OpenCode")
        # 原地补丁（与 WorkBuddy 同因：asar 索引含悬空 unpacked 引用 + 嵌套 app.asar.unpacked 树，
        # 常规重打包会把外置文本文件嵌回归档；bundle 命名为 assets/main-*.js。
        # 渲染页面由自定义协议 oc:// 加载，file:// 子资源会被 Chromium 拦截 →
        # 在主进程注入 wp:// 协议桥服务壁纸目录，透明化走 --background-* 变量）
        RendererDir = 'out/renderer'
        InjectSrc   = 'oc-wallpaper.js'
        Method      = 'inplace'
        BundleName  = 'main'
        ExeHash     = $false  # 实测 OpenCode.exe 的 asar 完整性 fuse 为关闭，无需改主程序
        WallUrl     = 'wp://local'
        MainBridge  = $true
    }
    'WorkBuddy' = @{
        Process     = 'WorkBuddy'
        WallDir     = Join-Path $env:USERPROFILE '.workbuddy\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\WorkBuddy.lnk"
        Candidates  = @('F:\Program files\WorkBuddy', 'C:\Program files\WorkBuddy',
                        "$env:LOCALAPPDATA\Programs\WorkBuddy", "$env:LOCALAPPDATA\Programs\workbuddy")
        # 原地补丁（asar 内目录 renderer；索引带 integrity 且含大量悬空 unpacked 引用，
        # 常规重打包会把几千个文本文件嵌进 asar 并破坏可执行文件外置 → 用 patch-inplace.js）
        RendererDir = 'renderer'
        InjectSrc   = 'oc-wallpaper-vscode.js'
        Method      = 'inplace'
        BundleName  = 'index'
        ExeHash     = $true   # Electron asar 完整性 fuse 开启，需同步更新主程序内嵌头部哈希
    }
    'Codex' = @{
        Process     = 'ChatGPT'   # OpenAI.Codex 商店包：主程序为 app\ChatGPT.exe（Codex 桌面端）
        WallDir     = Join-Path $env:USERPROFILE '.codex\wallpaper'
        Lnk         = ''
        # 2026-09-15 起 Codex 走「散装副本 + CDP 代理」方案（与豆包同架构）：
        #   1. WindowsApps 包文件被系统内核级保护（有 DACL 也一律拒绝写入），原地补丁不可行
        #   2. 整包复制到 %USERPROFILE%\CodexPatched → 移除商店包 → ChatGPT.exe 以普通程序
        #      带 --remote-debugging-port 启动（商店版无法传参，owl 会吞掉激活参数）
        #   3. 壁纸由 codex-launcher 代理经 CDP 注入；媒体子资源有 URL 安全检查，
        #      wp:// 桥与 http://127.0.0.1 对 <video>/<img> 均被拒 → 图片走 app://fs/@fs/<路径> 直通
        #      （散装 asar 里的 wp:// 桥保留备用，暂只支持图片壁纸）
        # 安装 = 部署启动器 + 建「ChatGPT」快捷方式；商店包若还在，提示先卸载并复制散装目录
        Method      = 'agent'
        AgentFiles  = @('codex-launcher.ps1', 'codex-launcher.vbs')
        LooseCopy   = 'C:\Users\FVAEP\CodexPatched'
        Candidates  = @('C:\Users\FVAEP\CodexPatched')
        MsixId      = 'OpenAI.Codex'
        # 用户级开始菜单新建「ChatGPT」入口（商店包已卸载，原入口随之消失）；桌面同名入口由安装器同步创建
        AgentLnkNew = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ChatGPT.lnk"
        AgentIcon   = 'C:\Users\FVAEP\CodexPatched\app\resources\chatgpt-app-light.ico'
        AgentPorts  = @(19330, 19331, 19332, 19333, 19334)
    }
    'TraeCN' = @{
        Process     = 'Trae CN'
        WallDir     = Join-Path $env:USERPROFILE '.trae-cn\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Trae CN\Trae CN.lnk"
        Candidates  = @('F:\AIcodeprogram\Trae CN', "$env:LOCALAPPDATA\Programs\Trae CN",
                        'F:\Program files\Trae CN', 'C:\Program files\Trae CN')
        # Trae 为 VS Code 派生（字节跳动 icube），resources 下是散装 app 目录（无 app.asar）：
        # 直接改文件。主窗口经 vscode-file:// 加载，Chromium 禁止其加载 file:// 子资源 →
        # 与 OpenCode/Codex 同款 wp:// 协议桥（注册特权协议 + 主进程服务壁纸目录），
        # CSP 放宽 img/media/style-src 允许 wp:
        ProbeRel    = 'app\out\vs\code\electron-browser\workbench\workbench.html'
        InjectSrc   = 'oc-wallpaper-trae.js'
        Method      = 'files'
        # 多锚点回退：不同构建的入口脚本名可能是 workbench.js / workbench-esm.js 等；
        # 全部落空时退到"第一个 <script 标签前注入"（壁纸脚本本身兼容 body 未就绪）
        InjectBefore = @('<script src="./workbench.js"', '<script src="./workbench-esm.js"',
                         '<script src="./workbench-desktop.js"')
        RelaxCsp    = $true
        WallUrl     = 'wp://local'
        MainBridge  = $true
        BridgeRel   = 'app\out\main.js'
    }
    'TraeWorkCN' = @{
        Process     = 'TRAE SOLO CN'
        WallDir     = Join-Path $env:USERPROFILE '.trae-cn\wallpaper-solo'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\TRAE Work CN\TRAE Work CN.lnk"
        Candidates  = @('F:\AIcodeprogram\TRAE SOLO CN', "$env:LOCALAPPDATA\Programs\TRAE SOLO CN",
                        'F:\Program files\TRAE SOLO CN', 'C:\Program files\TRAE SOLO CN')
        # 同 TraeCN（同一代码底座）。注意两个应用共用 .trae-cn 数据目录，壁纸目录分设 wallpaper-solo。
        # SOLO 主窗口是自定义外壳 solo-lite.html（无 CSP meta，无需放宽；开始菜单名「TRAE Work CN」）
        ProbeRel    = 'app\out\vs\code\electron-browser\solo\solo-lite.html'
        InjectSrc   = 'oc-wallpaper-trae.js'
        Method      = 'files'
        InjectBefore = @('<script src="./workbench.js"', '<script src="./workbench-esm.js"',
                         '<script src="./workbench-desktop.js"')
        RelaxCsp    = $false
        WallUrl     = 'wp://local'
        MainBridge  = $true
        BridgeRel   = 'app\out\main.js'
    }
    'AutoClaw' = @{
        Process     = 'AutoClaw'
        WallDir     = Join-Path $env:APPDATA 'autoclaw\wallpaper'
        Lnk         = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AutoClaw.lnk'
        Candidates  = @('F:\AIcodeprogram\AUTOCLAW', 'C:\Program files\AutoClaw',
                        "$env:LOCALAPPDATA\Programs\AutoClaw")
        # Electron（Vite+React 壳，index-CWzVkVlB.js）。asar 完整性 fuse 实测关闭，主程序不用改；
        # asar 索引含 unpacked 清单 → 与 WorkBuddy 同款 patch-inplace 原地补丁。
        # 主窗口经 loadFile（file://）加载，file:// 子资源可直接访问，无需协议桥。
        # 皮肤系统为 --theme-* 令牌（body[data-skin][data-theme]，--bg/--panel/--surface-* 皆别名），
        # 弹层/模态令牌 --theme-surface-overlay 保持不透明
        RendererDir = 'out/renderer'
        InjectSrc   = 'oc-wallpaper-autoclaw.js'
        Method      = 'inplace'
        BundleName  = 'index'
        ExeHash     = $false
        # AutoClaw 常驻进程以管理员权限运行：杀进程需提权；StopRunning = 打补丁时自动结束进程
        RequireAdmin = $true
        StopRunning  = $true
    }
    'Doubao' = @{
        Process     = 'Doubao'
        WallDir     = Join-Path $env:USERPROFILE '.doubao\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\豆包.lnk"
        Candidates  = @('F:\Program files\Doubao', 'C:\Program files\Doubao',
                        "$env:LOCALAPPDATA\Doubao")
        # 豆包桌面版是 Chromium 壳（无 asar，主窗口 chrome://doubao-chat 内部页，CDP 可注入）：
        # 不改程序文件；安装 = 部署 doubao-launcher.ps1/.vbs（带本机调试端口启动豆包 + CDP 注入
        # 壁纸层与透明化 CSS）并把开始菜单快捷方式改指 vbs。换壁纸/轮换由代理热更新，无需重启
        # 豆包。不需要 Node.js。
        Method      = 'agent'
        AgentFiles  = @('doubao-launcher.ps1', 'doubao-launcher.vbs')
        AgentExe    = 'Doubao.exe'
        AgentPorts  = @(19222, 19223, 19224, 19225, 19226)
        # 官方快捷方式的原始指向/参数（回滚还原用）：豆包直接启动、无参数
        AgentLnkTarget = ''
        AgentLnkArgs   = ''
    }
    'Marvis' = @{
        Process     = 'Marvis'
        WallDir     = Join-Path $env:USERPROFILE '.marvis\wallpaper'
        Candidates  = @('C:\Program Files\Tencent\Marvis\Application')
        # 腾讯 Marvis 是 Qt5 + CEF 壳，主窗口页面 = Roaming 离线缓存 marvis-offline-page\using\
        # （安装目录里的同名目录只是种子副本，改它无效；CEF 调试端口实测不开放，CDP 不可行）。
        # 壁纸脚本【内联】注入 using\index.html；媒体/轮换标记/custom.css 由本机回环 HTTP 服务
        # （127.0.0.1:19399，登录自启）供给——离线页拦截器是白名单式，junction/新增文件一律拒绝。
        # 127.0.0.1 是 Chromium 安全来源，但需移除 index.html 的 upgrade-insecure-requests CSP。
        # 补丁目录用户可写 → 安装/修复零 UAC；仅重启 Marvis 需管理员（与平时启动一致）。
        Method      = 'marvis'
        OfflineDir  = Join-Path $env:APPDATA 'Tencent\Marvis\marvis-offline-page\using'
        InjectSrc   = 'zwp-wallpaper-marvis.js'
        MediaUrl    = 'http://127.0.0.1:19399'
        MediaPort   = 19399
        MediaServer = 'zwp-media-server.ps1'
        MediaTask   = 'AI壁纸媒体服务'
        # 历史方案（CDP 代理 + 「Marvis 壁纸」快捷方式）残留清理清单
        CleanupHub  = @('marvis-launcher.ps1', 'marvis-launcher.vbs')
        CleanupLnk  = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Marvis 壁纸.lnk"
    }
    'Reasonix' = @{
        Process     = 'Reasonix'
        WallDir     = Join-Path $env:USERPROFILE '.reasonix\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Reasonix.lnk"
        Candidates  = @('F:\AIcodeprogram\Reasonix', 'C:\Program files\Reasonix',
                        "$env:LOCALAPPDATA\Programs\Reasonix")
        # Reasonix 桌面壳：launcher + versions\<激活版本>\app 布局（current.json 指向激活版本），
        # app\resources\app 为散装前端（Vite/React），无 CSP meta，asar 完整性 fuse 实测关闭
        # （asar 内只有 main.cjs 等，不需要动）→ 与 Trae 同款散装直改。
        # 壁纸媒体经 distRoot 内 zwp junction（→ %USERPROFILE%\.reasonix\wallpaper）以
        # 同源相对路径 reasonix://app/zwp/... 供给：该应用的协议处理器服务 distRoot 下任意
        # 真实文件（路径穿越检查 + isFile），junction 透明解析 → 无需 CDP/协议桥/回环服务，
        # 升级换版本目录后 junction 随补丁一起重建。
        # 透明化：全部表面色从根源令牌 --bg/--bg-soft/--bg-elev/--bg-elev-2/--chat-bg 派生
        # （--stage/--surface/--panel 与 color-mix 均引用），!important 覆盖一次全主题生效；
        # 深浅色按 html[data-theme] 判定，弹层 --overlay-surface-bg 单独保持近乎不透明。
        Method      = 'reasonix'
        RendererRel = 'app\index.html'   # 相对 appDir（versions\<激活版本>\app）
        InjectSrc   = 'oc-wallpaper-reasonix.js'
        WallUrl     = './zwp'            # 注入脚本内用同源相对路径
    }
    'DeepSeekHarness' = @{
        Process     = 'DSH Desktop'
        WallDir     = Join-Path $env:USERPROFILE '.dsh\wallpaper'
        Lnk         = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DSH Desktop.lnk"
        Candidates  = @("$env:LOCALAPPDATA\Programs\DSH Desktop")
        # DeepSeek Harness 开源桌面端（github.com/anywhere-labs/dsh-desktop，MIT）：
        # Electron 壳 + 内嵌 NodeService 回环 webserver（动态端口、带来源校验）供官方 Web UI，
        # 主窗口 loadURL 到 http://127.0.0.1:<动态端口>/。页面静态源是散装可写目录
        # resources\app\node_modules\@deepseek-ai\dsh-web-frontend\dist\ → 与 Marvis 同款
        # 【内联】补丁：壁纸脚本注入 dist\index.html（内联避免服务端 MIME/新增文件差异），
        # 媒体/轮换标记/custom.css 走回环媒体服务 127.0.0.1:19399 的 /dsh 虚拟根。
        # 零 UAC、免 Node、免关应用（补丁在下次启动时生效）。
        # 透明化：主题令牌 --dsw-alias-bg-base/-layer-1（body 浅色 + body[data-ds-dark-theme]
        # 深色两处同源覆盖）；卡片/弹层令牌 layer-2/3 保持原色保证可读性。
        ProbeRel    = 'app\node_modules\@deepseek-ai\dsh-web-frontend\dist\index.html'
        Method      = 'dsh'
        InjectSrc   = 'zwp-wallpaper-dsh.js'
        MediaUrl    = 'http://127.0.0.1:19399/dsh'
        MediaPort   = 19399
        MediaServer = 'zwp-media-server.ps1'
        MediaTask   = 'AI壁纸媒体服务'
    }
}
if (-not $Apps.ContainsKey($App)) {
    throw "未知应用 '$App'，支持：$($Apps.Keys -join ' / ')"
}
$Cfg = $Apps[$App]

function Test-AsarPatched([string]$path) {
    # asar 头部 JSON 明文列出归档内全部文件名：补丁存在 ⇒ 头部必含 oc-wallpaper 条目。
    # 只读前 8MB，几百 MB 的归档也能亚秒级判定，无需解包
    if (-not (Test-Path $path)) { return $false }
    $fs = [IO.File]::OpenRead($path)
    try {
        $n = [int][Math]::Min(8MB, $fs.Length)
        $buf = New-Object byte[] $n
        $read = 0
        while ($read -lt $n) { $r = $fs.Read($buf, $read, $n - $read); if ($r -le 0) { break }; $read += $r }
    } finally { $fs.Close() }
    return ([Text.Encoding]::ASCII.GetString($buf, 0, $read).Contains('oc-wallpaper'))
}

# 补丁是否仍在（应用升级覆盖补丁文件后为 false → 触发重装；一键修复的主要判定）
function Test-PatchPresent {
    if ($Cfg.Method -eq 'agent') {
        # 豆包（代理方案）：补丁 = hub 里的代理启动器文件
        $hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
        foreach ($f in $Cfg.AgentFiles) { if (-not (Test-Path (Join-Path $hub $f))) { return $false } }
        return $true
    }
    if ($Cfg.Method -eq 'marvis') {
        # Marvis：补丁 = Roaming using\index.html 含内联壁纸脚本
        $idx = Join-Path $Cfg.OfflineDir 'index.html'
        if (-not (Test-Path $idx)) { return $false }
        return ([IO.File]::ReadAllText($idx) -match 'oc-wallpaper')
    }
    if ($Cfg.Method -eq 'dsh') {
        # DeepSeek Harness：补丁 = 前端 dist\index.html 含内联壁纸脚本
        $idx = Join-Path $res $Cfg.ProbeRel
        if (-not (Test-Path $idx)) { return $false }
        return ([IO.File]::ReadAllText($idx) -match 'oc-wallpaper')
    }
    if ($Cfg.Method -eq 'files') {
        $htmlPath = Join-Path $res $Cfg.ProbeRel
        if (-not (Test-Path $htmlPath)) { return $false }
        if ([IO.File]::ReadAllText($htmlPath) -notmatch 'oc-wallpaper') { return $false }
        if ($Cfg.MainBridge) {
            $mainJs = Join-Path $res $Cfg.BridgeRel
            if (-not (Test-Path $mainJs)) { return $false }
            if ([IO.File]::ReadAllText($mainJs) -notmatch 'zcode-wallpaper bridge') { return $false }
        }
        return $true
    }
    return (Test-AsarPatched $asar)
}

function Find-Target {
    if ($InstallDir) { return $InstallDir }
    # MSIX 包（Codex）：安装目录在 ACL 保护的 WindowsApps 内且路径带版本号，经 Get-AppxPackage 解析
    if ($Cfg.MsixId) {
        $pkg = Get-AppxPackage -Name $Cfg.MsixId -ErrorAction SilentlyContinue
        if ($pkg -and $pkg.InstallLocation) {
            $appDir = Join-Path $pkg.InstallLocation 'app'
            if (Test-Path (Join-Path $appDir 'resources\app.asar')) { return $appDir }
        }
        throw "未找到 $App 的 MSIX 包（$($Cfg.MsixId)）。请确认已从 Microsoft Store 安装。"
    }
    # Trae 系：散装 app 目录，用主窗口 HTML 文件本身作为定位探针
    $probeRel = if ($Cfg.ProbeRel) { $Cfg.ProbeRel } else { 'app.asar' }
    # 1) 运行中的进程路径反查（应用正在跑 → 路径最真实，装在非标准位置也能找到）
    $proc = Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path } | Select-Object -First 1
    if ($proc) {
        $dir = Split-Path $proc.Path
        if ($dir -and (Test-Path (Join-Path (Join-Path $dir 'resources') $probeRel))) { return $dir }
    }
    # 2) 固定候选目录
    foreach ($c in $Cfg.Candidates) {
        if (Test-Path (Join-Path (Join-Path $c 'resources') $probeRel)) { return $c }
    }
    # 3) 开始菜单全量反查（快捷方式被移动/改名后单一路径会失效）
    foreach ($root in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
                        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs')) {
        if (-not (Test-Path $root)) { continue }
        $lnk = Get-ChildItem $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like "*$($Cfg.Process)*" } | Select-Object -First 1
        if (-not $lnk) { continue }
        $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName)
        if ($sh.TargetPath) {
            $dir = Split-Path $sh.TargetPath
            if ($dir -and (Test-Path (Join-Path (Join-Path $dir 'resources') $probeRel))) { return $dir }
        }
    }
    # 4) 注册表卸载信息反查（InstallLocation 指向安装根目录）
    $hit = Get-ItemProperty @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -like "*$($Cfg.Process)*" -and $_.InstallLocation } |
        Select-Object -First 1
    if ($hit) {
        $dir = $hit.InstallLocation.TrimEnd('\')
        if ($dir -and (Test-Path (Join-Path (Join-Path $dir 'resources') $probeRel))) { return $dir }
    }
    throw "未找到 $App 安装目录，请用 -InstallDir 参数指定。"
}

function Test-Node {
    try { $null = & node --version 2>$null; return $LASTEXITCODE -eq 0 } catch { return $false }
}

# Reasonix（launcher+versions 布局）：root\current.json → activeDir → versions\<v>\app。
# -InstallDir 允许直接给 appDir（选择器修复流程）或 launcher 根（人工指认常见错误层，自动纠正）
function Get-ReasonixAppDirFromRoot([string]$root) {
    if (-not $root -or -not (Test-Path $root)) { return $null }
    # 直接就是 appDir（含 resources\app\index.html）？
    if (Test-Path (Join-Path $root 'resources\app\index.html')) { return $root }
    $cj = Join-Path $root 'current.json'
    if (-not (Test-Path $cj)) { return $null }
    try { $meta = Get-Content $cj -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $meta.activeDir) { return $null }
    $appDir = Join-Path (Join-Path $root $meta.activeDir) 'app'
    if (Test-Path (Join-Path $appDir 'resources\app\index.html')) { return $appDir }
    return $null
}
function Find-ReasonixAppDir {
    if ($InstallDir) {
        $d = Get-ReasonixAppDirFromRoot $InstallDir
        if ($d) { return $d }
    }
    # 1) 运行进程：app 子进程路径在 versions\<v>\app 下 → 直接用；launcher 进程 → 取其根再解析
    foreach ($p in (Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue)) {
        if (-not $p.Path) { continue }
        $dir = Split-Path $p.Path
        if ($dir -match '\\versions\\') {
            if (Test-Path (Join-Path $dir 'resources\app\index.html')) { return $dir }
        } else {
            $d = Get-ReasonixAppDirFromRoot $dir
            if ($d) { return $d }
        }
    }
    # 2) 候选根目录 → current.json
    foreach ($c in $Cfg.Candidates) {
        $d = Get-ReasonixAppDirFromRoot $c
        if ($d) { return $d }
    }
    # 3) 开始菜单快捷方式反查（目标多为顶层 launcher）
    foreach ($root in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
                        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs')) {
        if (-not (Test-Path $root)) { continue }
        $lnk = Get-ChildItem $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like "*$($Cfg.Process)*" } | Select-Object -First 1
        if (-not $lnk) { continue }
        $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName)
        if ($sh.TargetPath) {
            $d = Get-ReasonixAppDirFromRoot (Split-Path $sh.TargetPath)
            if ($d) { return $d }
        }
    }
    # 4) 注册表卸载信息反查（InstallLocation = launcher 根）
    $hit = Get-ItemProperty @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -like "*$($Cfg.Process)*" -and $_.InstallLocation } |
        Select-Object -First 1
    if ($hit) {
        $d = Get-ReasonixAppDirFromRoot $hit.InstallLocation.TrimEnd('\')
        if ($d) { return $d }
    }
    throw "未找到 $App 的激活版本目录，请用 -InstallDir 指定（launcher 根目录或 versions\<版本>\app 均可）。"
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ── 需要管理员权限的场景：MSIX 包写入（写包必须提权；Codex 已改散装副本+代理方案，无需提权）、
#    目标应用以管理员运行需强制结束（AutoClaw，仅在应用确实在运行时才提权） ──
$needAdmin = ($Cfg.MsixId -and $Cfg.Method -ne 'agent')
if (-not $needAdmin -and $Cfg.RequireAdmin -and -not (Test-Admin) -and
    (Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue)) { $needAdmin = $true }
if ($needAdmin -and -not (Test-Admin)) {
    Write-Step "本应用补丁需要管理员权限（结束管理员权限的应用进程），请求提权（请在 UAC 弹窗中确认）"
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-App', $App)
    if ($InstallDir) { $argList += @('-InstallDir', "`"$InstallDir`"") }
    if ($Rollback)   { $argList += '-Rollback' }
    if ($NoShortcut) { $argList += '-NoShortcut' }
    if ($Force)      { $argList += '-Force' }   # 不转发会静默降级为 no-op（AutoClaw -Force 场景）
    Start-Process powershell -Verb RunAs -ArgumentList ($argList + '-Elevated')
    exit 0
}

function Write-Utf8NoBom($path, $content) {
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
}

# ── 回滚 ────────────────────────────────────────────────
if ($Rollback) {
    if ($Cfg.Method -eq 'agent') {
        # 代理型应用（豆包/Marvis）：还原/移除快捷方式、移除代理文件；壁纸目录保留
        Write-Step "回滚 $App（代理方案：还原快捷方式、移除代理文件）"
        $ws = New-Object -ComObject WScript.Shell
        if ($Cfg.AgentLnkNew) {
            # Marvis 模式：官方快捷方式从未动过，只需删除新建的「<App> 壁纸」入口
            foreach ($lnkPath in @($Cfg.AgentLnkNew,
                    (Join-Path ([Environment]::GetFolderPath('Desktop')) (Split-Path $Cfg.AgentLnkNew -Leaf)))) {
                if ($lnkPath -and (Test-Path $lnkPath)) {
                    Remove-Item $lnkPath -Force
                    Write-Ok "已移除快捷方式: $lnkPath"
                }
            }
        } else {
            # 豆包模式：官方快捷方式被改指代理 → 还原为官方启动器
            $stock = $Cfg.Candidates | Where-Object { Test-Path (Join-Path $_ $Cfg.AgentExe) } | Select-Object -First 1
            $restoreTarget = $Cfg.AgentLnkTarget
            if (-not $restoreTarget -and $stock) { $restoreTarget = Join-Path $stock $Cfg.AgentExe }
            $lnkPaths = @($Cfg.Lnk) + @((Join-Path ([Environment]::GetFolderPath('Desktop')) (Split-Path $Cfg.Lnk -Leaf)))
            foreach ($lnkPath in $lnkPaths) {
                if (-not $lnkPath -or -not (Test-Path $lnkPath)) { continue }
                $lnk = $ws.CreateShortcut($lnkPath)
                if ($restoreTarget -and (Test-Path $restoreTarget)) {
                    $lnk.TargetPath = $restoreTarget
                    $lnk.Arguments = $Cfg.AgentLnkArgs
                    $lnk.WorkingDirectory = Split-Path $restoreTarget
                    try { $lnk.Save() } catch {
                        # ProgramData 等位置的快捷方式用户可能只可删建、不可原地改写
                        Remove-Item $lnkPath -Force
                        $lnk = $ws.CreateShortcut($lnkPath)
                        $lnk.TargetPath = $restoreTarget
                        $lnk.Arguments = $Cfg.AgentLnkArgs
                        $lnk.WorkingDirectory = Split-Path $restoreTarget
                        $lnk.Save()
                    }
                    Write-Ok "已还原快捷方式: $lnkPath"
                } else {
                    Remove-Item $lnkPath -Force
                    Write-Ok "已移除快捷方式: $lnkPath"
                }
            }
        }
        $hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
        foreach ($f in $Cfg.AgentFiles) { Remove-Item (Join-Path $hub $f) -Force -ErrorAction SilentlyContinue }
        Write-Ok ("已移除代理启动器（$hub）。壁纸目录 {0} 保留。" -f $Cfg.WallDir)
        exit 0
    }
    if ($Cfg.Method -eq 'marvis') {
        # Marvis：恢复离线页原版 index.html、停止媒体服务并注销自启任务；壁纸目录保留
        Write-Step "回滚 $App（恢复 Roaming 离线页原版）"
        $idx = Join-Path $Cfg.OfflineDir 'index.html'
        $idxBak = "$idx.zwp-backup"
        if (-not (Test-Path $idxBak)) { throw "未找到备份 $idxBak，无法回滚。" }
        Copy-Item $idxBak $idx -Force
        Get-ScheduledTask -TaskName $Cfg.MediaTask -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        $mPid = (Get-NetTCPConnection -LocalPort $Cfg.MediaPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
        if ($mPid) { Stop-Process -Id $mPid -Force -ErrorAction SilentlyContinue }
        $junc = Join-Path $Cfg.OfflineDir 'zwp-media'
        if (Test-Path $junc) { $null = & cmd /c ('rmdir "{0}" 2>nul' -f $junc) }
        Write-Ok "已恢复 $idx （确认正常后可删除 $idxBak）"
        Write-Ok ("媒体服务已停止并注销。壁纸目录 {0} 保留。" -f $Cfg.WallDir)
        exit 0
    }
    if ($Cfg.Method -eq 'reasonix') {
        # Reasonix：恢复主窗口 HTML、移除注入脚本与 zwp junction；壁纸目录保留
        $appDir  = Find-ReasonixAppDir
        $res     = Join-Path $appDir 'resources'
        $htmlPath = Join-Path $res $Cfg.RendererRel
        $htmlBak  = "$htmlPath.zwp-backup"
        if (-not (Test-Path $htmlBak)) { throw "未找到备份 $htmlBak，无法回滚。" }
        Write-Step "恢复原版主窗口 HTML（$($Cfg.RendererRel)）"
        Copy-Item $htmlBak $htmlPath -Force
        Remove-Item (Join-Path (Split-Path $htmlPath) 'oc-wallpaper.js') -Force -ErrorAction SilentlyContinue
        $junc = Join-Path (Split-Path $htmlPath) 'zwp'
        if (Test-Path $junc) { $null = & cmd /c ('rmdir "{0}" 2>nul' -f $junc) }
        Write-Ok "已恢复（zwp junction 已移除）。确认正常后可删除 $htmlBak 释放空间。壁纸目录 $($Cfg.WallDir) 保留。"
        if ($Elevated) { Write-Host ''; Read-Host '按回车关闭窗口' | Out-Null }
        exit 0
    }
    if ($Cfg.Method -eq 'dsh') {
        # DeepSeek Harness：恢复前端 dist\index.html 原版；回环媒体服务与 Marvis 共用，保留
        $target = Find-Target
        $idx = Join-Path (Join-Path $target 'resources') $Cfg.ProbeRel
        $idxBak = "$idx.zwp-backup"
        if (-not (Test-Path $idxBak)) { throw "未找到备份 $idxBak，无法回滚。" }
        Write-Step "恢复原版前端页（$($Cfg.ProbeRel)）"
        Copy-Item $idxBak $idx -Force
        Write-Ok "已恢复 $idx （确认正常后可删除 $idxBak）"
        Write-Ok ("媒体服务为与 Marvis 共用的基础设施，已保留运行。壁纸目录 {0} 保留。" -f $Cfg.WallDir)
        if ($Elevated) { Write-Host ''; Read-Host '按回车关闭窗口' | Out-Null }
        exit 0
    }
    $target = Find-Target
    $res = Join-Path $target 'resources'
    if ($Cfg.Method -eq 'files') {
        # Trae 系：恢复主窗口 HTML 与主进程 bundle、移除注入脚本文件
        $htmlPath = Join-Path $res $Cfg.ProbeRel
        $htmlBak  = "$htmlPath.zwp-backup"
        if (-not (Test-Path $htmlBak)) { throw "未找到备份文件 $htmlBak，无法回滚。" }
        Write-Step "恢复原版主窗口 HTML（$($Cfg.ProbeRel)）"
        Copy-Item $htmlBak $htmlPath -Force
        Remove-Item (Join-Path (Split-Path $htmlPath) 'oc-wallpaper.js') -Force -ErrorAction SilentlyContinue
        if ($Cfg.MainBridge) {
            $mainJs  = Join-Path $res $Cfg.BridgeRel
            $mainBak = "$mainJs.zwp-backup"
            if (Test-Path $mainBak) {
                Write-Step "恢复原版主进程 bundle（$($Cfg.BridgeRel)）"
                Copy-Item $mainBak $mainJs -Force
            }
        }
        Write-Ok "已恢复。确认正常后可删除 $htmlBak 释放空间。"
        if ($Elevated) { Write-Host ''; Read-Host '按回车关闭窗口' | Out-Null }
        exit 0
    }
    if ($Cfg.MsixId) {
        # MSIX：备份放在包外 %LOCALAPPDATA%\<MsixId>\zwp-backup\
        $bak = Join-Path (Join-Path $env:LOCALAPPDATA ($Cfg.MsixId + '\zwp-backup')) 'app.asar'
    } else {
        $bak = Join-Path $res 'app.asar.zwp-backup'
    }
    if (-not (Test-Path $bak)) { throw "未找到备份文件 $bak，无法回滚。" }
    if ($Cfg.MsixId) {
        Write-Step "临时授权写入（takeown + icacls）"
        & takeown /f $res | Out-Null
        & icacls $res /grant '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        & takeown /f (Join-Path $res 'app.asar') | Out-Null
        & icacls (Join-Path $res 'app.asar') /grant '*S-1-5-32-544:F' | Out-Null
    }
    Write-Step "恢复原版 app.asar"
    Copy-Item $bak (Join-Path $res 'app.asar') -Force
    if ($Cfg.MsixId) {
        # 把文件属主交还 TrustedInstaller，尽量还原包的 ACL 状态
        & icacls (Join-Path $res 'app.asar') /setowner 'NT SERVICE\TrustedInstaller' | Out-Null
        & icacls $res /setowner 'NT SERVICE\TrustedInstaller' | Out-Null
        Write-Ok "文件属主已交还 TrustedInstaller"
    }
    $exeBak = Join-Path $target ($Cfg.Process + '.exe.zwp-backup')
    if (Test-Path $exeBak) {
        Write-Step "恢复原版主程序（内嵌头部哈希）"
        Copy-Item $exeBak (Join-Path $target ($Cfg.Process + '.exe')) -Force
        Write-Ok "已恢复 $exeBak 对应的原版主程序"
    }
    Write-Ok "已恢复。确认正常后可删除 $bak 释放空间。"
    if ($Elevated) { Write-Host ''; Read-Host '按回车关闭窗口' | Out-Null }
    exit 0
}

# ── 安装（兼作升级后修复：补丁被更新覆盖时自动重打，自动识别安装目录） ──
# hub 中心目录提前建好：agent/marvis/dsh 分支会往 %USERPROFILE%\.ai-wallpaper 拷启动器/媒体服务，
# 全新机器上目录尚不存在时 Copy-Item 会直接崩（此前创建目录的代码在所有方法分支之后才执行）
$hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
if (-not (Test-Path $hub)) { New-Item -ItemType Directory -Path $hub -Force | Out-Null }
if ($Cfg.Method -eq 'agent') {
    # 代理型应用（豆包/Marvis 等 Chromium/CEF 壳）：不改程序文件，部署 CDP 代理启动器并把
    # 开始菜单快捷方式指向它。应用无需关闭、无需 Node.js；重复运行幂等（覆盖部署同版代理文件）。
    $target = $null
    if ($InstallDir -and (Test-Path $InstallDir)) { $target = $InstallDir }
    if (-not $target) { $target = $Cfg.Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1 }
    if (-not $target) { throw "未找到 $App 安装目录（候选路径均不存在，可用 -InstallDir 显式指定）。" }
    Write-Step "$App 目录: $target（CEF/Chromium 壳 → CDP 代理方案，不改程序文件）"
    $run = $true
    $hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
    foreach ($f in $Cfg.AgentFiles) {
        Copy-Item (Join-Path $Script:RepoFiles $f) (Join-Path $hub $f) -Force
    }
    Write-Ok ("代理启动器已部署: $hub\" + ($Cfg.AgentFiles -join ' / '))
    # 开始菜单快捷方式 → wscript 运行启动器 vbs（隐藏 PowerShell，图标保持应用原样）
    $ws = New-Object -ComObject WScript.Shell
    if ($Cfg.AgentLnkNew) {
        # Marvis 模式：官方快捷方式不可改写（ProgramData 受保护）→ 用户级开始菜单新建「<App> 壁纸」
        $newLnk = $ws.CreateShortcut($Cfg.AgentLnkNew)
        $newLnk.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
        $newLnk.Arguments = ('"' + (Join-Path $hub ($Cfg.AgentFiles | Where-Object { $_ -like '*.vbs' } | Select-Object -First 1)) + '"')
        $newLnk.WorkingDirectory = $hub
        if ($Cfg.AgentIcon -and (Test-Path $Cfg.AgentIcon)) { $newLnk.IconLocation = ($Cfg.AgentIcon + ',0') }
        $newLnk.Save()
        Write-Ok ("已创建快捷方式: {0}（官方 Marvis 快捷方式保持原样）" -f $Cfg.AgentLnkNew)
    } elseif (Test-Path $Cfg.Lnk) {
        $setLnk = {
            param($lnk)
            $lnk.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
            $lnk.Arguments = ('"' + (Join-Path $hub ($Cfg.AgentFiles | Where-Object { $_ -like '*.vbs' } | Select-Object -First 1)) + '"')
            $lnk.WorkingDirectory = $hub
            if ($Cfg.AgentIcon -and (Test-Path $Cfg.AgentIcon)) { $lnk.IconLocation = ($Cfg.AgentIcon + ',0') }
        }
        try {
            $lnk = $ws.CreateShortcut($Cfg.Lnk)
            & $setLnk $lnk
            $lnk.Save()
        } catch {
            # ProgramData 等位置的快捷方式用户可能只可删建、不可原地改写 → 删除后重建
            Remove-Item $Cfg.Lnk -Force
            $lnk = $ws.CreateShortcut($Cfg.Lnk)
            & $setLnk $lnk
            $lnk.Save()
        }
        Write-Ok "开始菜单快捷方式已指向壁纸启动器（图标不变）"
    } elseif (-not $Cfg.AgentLnkNew) {
        Write-Warn2 "未找到开始菜单快捷方式（$($Cfg.Lnk)），跳过；请从开始菜单固定 $App 后再运行本脚本。"
    }
    if (Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue) {
        # 应用在跑：若调试端口在（代理已加载）则无需动作，否则提示重启一次
        $agentUp = $false
        foreach ($p in $Cfg.AgentPorts) {
            try { $null = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/version" -f $p) -TimeoutSec 1; $agentUp = $true; break } catch {}
        }
        if (-not $agentUp) {
            Write-Warn2 "$App 正在运行（本次未带代理）：退出 $App 后从「$App」快捷方式重新启动即可加载壁纸。"
        }
    }
} elseif ($Cfg.Method -eq 'marvis') {
    # Marvis（Qt5+CEF）：补丁 Roaming 离线页缓存（用户可写，零 UAC、无需 Node、无需关应用）。
    # 顺带清理历史 CDP 代理方案的残留（hub 启动器 + 「Marvis 壁纸」快捷方式）。
    $hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
    Write-Step "$App 离线页目录: $($Cfg.OfflineDir)"
    $idx = Join-Path $Cfg.OfflineDir 'index.html'
    if (-not (Test-Path $idx)) {
        throw "未找到 $idx（离线缓存尚未生成）。请先正常启动一次 Marvis，再重新运行本脚本。"
    }
    $hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
    foreach ($f in @($Cfg.CleanupHub)) { Remove-Item (Join-Path $hub $f) -Force -ErrorAction SilentlyContinue }
    foreach ($l in @($Cfg.CleanupLnk, (Join-Path ([Environment]::GetFolderPath('Desktop')) (Split-Path $Cfg.CleanupLnk -Leaf)))) {
        if ($l -and (Test-Path $l)) { Remove-Item $l -Force -ErrorAction SilentlyContinue; Write-Ok "已移除历史快捷方式: $l" }
    }
    # 清理上一版方案的 junction（媒体改走本机回环服务）
    $oldJunc = Join-Path $Cfg.OfflineDir 'zwp-media'
    if (Test-Path $oldJunc) { $null = & cmd /c ('rmdir "{0}" 2>nul' -f $oldJunc) }

    $already = Test-PatchPresent
    $run = (-not $already -or $Force)
    if ($already -and -not $Force) {
        Write-Ok "$App 已含壁纸补丁，无需重复安装（Marvis 更新离线缓存覆盖补丁后重新运行本脚本即可修复）"
    }

    if ($run) {
        $bak = "$idx.zwp-backup"
        if (-not (Test-Path $bak)) {
            Copy-Item $idx $bak
            Write-Ok "已备份原版 index.html"
        } else {
            Copy-Item $bak $idx -Force
            Write-Warn2 "已存在备份，从原版重放（避免补丁版覆盖原版备份）"
        }
        # 壁纸脚本内联注入（拦截器不保证服务新增文件，内联绕开该限制）
        $js = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles $Cfg.InjectSrc))
        $js = $js.Replace('__WALLPAPER_DIR__', $Cfg.MediaUrl)
        if ($js -match '</script') { throw "注入脚本含 </script，无法内联。" }
        $html = [IO.File]::ReadAllText($idx)
        # 移除 upgrade-insecure-requests CSP（否则 http://127.0.0.1 媒体被强制升级 https 而失效）
        $html = [regex]::Replace($html, '<meta\s+http-equiv="Content-Security-Policy"[^>]*>', '')
        if ($html -match 'zwp-wallpaper') {
            Write-Warn2 "index.html 已含壁纸脚本（跳过重复注入）"
        } else {
            $anchors = @('<script type="module" crossorigin src="./assets/main-', '<script type="module"', '</head>')
            $marker = $null
            foreach ($a in $anchors) { if ($html.IndexOf($a) -ge 0) { $marker = $a; break } }
            if (-not $marker) { throw "index.html 中未找到注入锚点，此版本可能不兼容。" }
            $html = $html.Replace($marker, '<script>' + $js + '</script>' + $marker)
            [IO.File]::WriteAllText($idx, $html, [Text.UTF8Encoding]::new($false))
            Write-Ok "壁纸脚本已内联注入 index.html（CSP meta 已移除）"
        }
        # 媒体服务：部署脚本 + 登录自启计划任务 + 立即拉起（端口在则自退出，天然幂等）
        $msHub = Join-Path $hub ($Cfg.MediaServer)
        Copy-Item (Join-Path $Script:RepoFiles $Cfg.MediaServer) $msHub -Force
        if (-not (Get-ScheduledTask -TaskName $Cfg.MediaTask -ErrorAction SilentlyContinue)) {
            $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $msHub + '"')
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            Register-ScheduledTask -TaskName $Cfg.MediaTask -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null
            Write-Ok ("媒体服务已注册登录自启: " + $Cfg.MediaTask)
        } else {
            Write-Warn2 "媒体服务计划任务已存在（跳过）"
        }
        $msUp = $false
        try { $null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/__ping' -f $Cfg.MediaPort) -TimeoutSec 2; $msUp = $true } catch {}
        if (-not $msUp) {
            Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $msHub)
            for ($i = 0; $i -lt 20 -and -not $msUp; $i++) {
                Start-Sleep -Milliseconds 500
                try { $null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/__ping' -f $Cfg.MediaPort) -TimeoutSec 2; $msUp = $true } catch {}
            }
        }
        if ($msUp) { Write-Ok ("媒体服务运行中: http://127.0.0.1:" + $Cfg.MediaPort) }
        else { Write-Warn2 "媒体服务未能启动，壁纸媒体将无法加载（重新运行本脚本重试）" }
        if (Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue) {
            Write-Warn2 "$App 正在运行：新壁纸脚本将在下次启动 $App 时生效（重启一次即可）。"
        }
    }
} elseif ($Cfg.Method -eq 'dsh') {
    # DeepSeek Harness（开源 DSH Desktop）：内联补丁回环前端 dist\index.html + 回环媒体服务
    # 的 /dsh 虚拟根（服务与 Marvis 共用，见 zwp-media-server.ps1）。零 UAC、免 Node、
    # 免关应用（补丁在下次启动应用时生效）。
    $target = Find-Target
    $res    = Join-Path $target 'resources'
    $idx    = Join-Path $res $Cfg.ProbeRel
    if (-not (Test-Path $idx)) { throw "未找到 $idx，此版本结构可能不兼容。" }
    Write-Step "$App 前端页: $idx"
    New-Item -ItemType Directory -Path (Join-Path $Cfg.WallDir 'rotate') -Force | Out-Null

    $already = Test-PatchPresent
    $run = (-not $already -or $Force)
    if ($already -and -not $Force) {
        Write-Ok "$App 已含壁纸补丁，无需重复安装（应用升级覆盖补丁后重新运行本脚本即可修复）"
    }

    if ($run) {
        $bak = "$idx.zwp-backup"
        if (-not (Test-Path $bak)) {
            Copy-Item $idx $bak
            Write-Ok "已备份原版 index.html"
        } else {
            Copy-Item $bak $idx -Force
            Write-Warn2 "已存在备份，从原版重放（避免补丁版覆盖原版备份）"
        }
        # 壁纸脚本内联注入（与页面同源执行，不依赖服务端对新增文件/MIME 的处理）
        $js = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles $Cfg.InjectSrc))
        $js = $js.Replace('__WALLPAPER_DIR__', $Cfg.MediaUrl)
        if ($js -match '</script') { throw "注入脚本含 </script，无法内联。" }
        $html = [IO.File]::ReadAllText($idx)
        if ($html -match 'oc-wallpaper') {
            Write-Warn2 "index.html 已含壁纸脚本（跳过重复注入）"
        } else {
            $anchors = @('<script type="module" crossorigin src="./assets/index-', '<script type="module"', '</head>')
            $marker = $null
            foreach ($a in $anchors) { if ($html.IndexOf($a) -ge 0) { $marker = $a; break } }
            if (-not $marker) { throw "index.html 中未找到注入锚点，此版本可能不兼容。" }
            $html = $html.Replace($marker, '<script>' + $js + '</script>' + $marker)
            [IO.File]::WriteAllText($idx, $html, [Text.UTF8Encoding]::new($false))
            Write-Ok "壁纸脚本已内联注入 index.html"
        }
        # 媒体服务：部署脚本 + 登录自启计划任务（与 Marvis 共用）+ 按需拉起/热重启。
        # 旧版服务只认根路径（无 /dsh 根）→ 根 __ping 通而 /dsh/__ping 不通时杀掉重启。
        $hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
        $msHub = Join-Path $hub ($Cfg.MediaServer)
        Copy-Item (Join-Path $Script:RepoFiles $Cfg.MediaServer) $msHub -Force
        if (-not (Get-ScheduledTask -TaskName $Cfg.MediaTask -ErrorAction SilentlyContinue)) {
            $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $msHub + '"')
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            Register-ScheduledTask -TaskName $Cfg.MediaTask -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null
            Write-Ok ("媒体服务已注册登录自启: " + $Cfg.MediaTask)
        } else {
            Write-Warn2 "媒体服务计划任务已存在（跳过）"
        }
        $rootUp = $false; $dshUp = $false
        try { $null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/__ping' -f $Cfg.MediaPort) -TimeoutSec 2; $rootUp = $true } catch {}
        try { $null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/dsh/__ping' -f $Cfg.MediaPort) -TimeoutSec 2; $dshUp = $true } catch {}
        if ($rootUp -and -not $dshUp) {
            Write-Warn2 "媒体服务为旧版（无 /dsh 根）：热重启升级"
            $mPid = (Get-NetTCPConnection -LocalPort $Cfg.MediaPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
            if ($mPid) { Stop-Process -Id $mPid -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1 }
            $rootUp = $false
        }
        if (-not $rootUp) {
            Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $msHub)
        }
        $dshUp = $false
        for ($i = 0; $i -lt 20 -and -not $dshUp; $i++) {
            Start-Sleep -Milliseconds 500
            try { $null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/dsh/__ping' -f $Cfg.MediaPort) -TimeoutSec 2; $dshUp = $true } catch {}
        }
        if ($dshUp) { Write-Ok ("媒体服务运行中: http://127.0.0.1:" + $Cfg.MediaPort + "/dsh") }
        else { Write-Warn2 "媒体服务未能启动，壁纸媒体将无法加载（重新运行本脚本重试）" }
        if (Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue) {
            Write-Warn2 "$App 正在运行：新壁纸脚本将在下次启动 $App 时生效（重启一次即可）。"
        }
    }
} elseif ($Cfg.Method -eq 'reasonix') {
    # Reasonix（Electron 壳，launcher+versions 布局）：散装直改 resources\app\index.html +
    # 落地 oc-wallpaper.js + zwp junction 供流。零 Node、零 UAC；重复运行幂等（从备份重放）。
    $appDir   = Find-ReasonixAppDir
    $res      = Join-Path $appDir 'resources'
    $htmlPath = Join-Path $res $Cfg.RendererRel
    if (-not (Test-Path $htmlPath)) { throw "未找到主窗口 HTML（$($Cfg.RendererRel)），此版本结构可能不兼容。" }
    $htmlDir = Split-Path $htmlPath
    Write-Step "$App 激活版本目录: $appDir"
    $already = ([IO.File]::ReadAllText($htmlPath) -match 'oc-wallpaper')
    $run = (-not $already -or $Force)
    if ($already -and -not $Force) {
        Write-Ok "$App 已含壁纸补丁，无需重复安装（应用升级换版本目录后重新运行本脚本即可修复）"
    }
    if ($run) {
        $appProc = Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue
        if ($appProc) { throw "$App 正在运行，请先完全退出 $App 再执行补丁。" }
        $htmlBak = "$htmlPath.zwp-backup"
        if (-not (Test-Path $htmlBak)) {
            Write-Step "备份原版主窗口 HTML"
            Copy-Item $htmlPath $htmlBak
            Write-Ok "备份到 $htmlBak"
        } else {
            Write-Warn2 "已存在备份，从原版重放（避免补丁版覆盖原版备份）"
            Copy-Item $htmlBak $htmlPath -Force
        }
        # 落地注入脚本（__WALLPAPER_DIR__ → 同源相对路径 ./zwp）
        $wpContent = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles $Cfg.InjectSrc))
        Write-Utf8NoBom (Join-Path $htmlDir 'oc-wallpaper.js') ($wpContent.Replace('__WALLPAPER_DIR__', $Cfg.WallUrl))
        Write-Ok "壁纸注入脚本已落地（壁纸目录: $($Cfg.WallDir)，经 ./zwp 同源加载）"
        # 注入 script 标签（多锚点回退；全部落空退到第一个 <script 前，脚本兼容极早执行）
        $html = [IO.File]::ReadAllText($htmlPath)
        if ($html -match 'oc-wallpaper') {
            Write-Warn2 "HTML 已包含壁纸脚本（跳过重复注入）"
        } else {
            $marker = $null
            foreach ($mk in @('<script type="module" src="./assets/index-', '<script type="module"', '<script', '</head>')) {
                if ($html.IndexOf($mk) -ge 0) { $marker = $mk; break }
            }
            if (-not $marker) { throw "index.html 中未找到任何注入点，此版本可能不兼容。" }
            $html = $html.Replace($marker, '<script src="./oc-wallpaper.js"></script>' + $marker)
            Write-Utf8NoBom $htmlPath $html
            Write-Ok ("壁纸脚本标签已注入（锚点: " + $marker.Substring(0, [Math]::Min(40, $marker.Length)) + "…）")
        }
        # zwp junction：distRoot 内暴露壁纸目录（协议处理器服务 distRoot 下任意真实文件，
        # junction 对其透明）→ 壁纸/轮换标记/custom.css 全走同源 reasonix://app/zwp/...
        Write-Step "壁纸媒体 junction"
        $wallDir = $Cfg.WallDir
        New-Item -ItemType Directory -Path (Join-Path $wallDir 'rotate') -Force | Out-Null
        $junc = Join-Path $htmlDir 'zwp'
        if (Test-Path $junc) {
            $item = Get-Item $junc -Force
            if ($item.LinkType -eq 'Junction' -or $item.LinkType -eq 'SymbolicLink') {
                $null = & cmd /c ('rmdir "{0}" 2>nul' -f $junc)   # 只摘链接不动壁纸目录
            } else {
                throw "$junc 已存在且不是链接（疑似版本目录内容变化），请人工确认后删除重试。"
            }
        }
        $null = & cmd /c ('mklink /J "{0}" "{1}" 2>nul' -f $junc, $wallDir)
        if (-not (Test-Path (Join-Path $junc 'rotate'))) { throw "zwp junction 创建失败（$junc → $wallDir）" }
        Write-Ok "zwp → $wallDir（同源 ./zwp/... 供流）"
    }
} else {
$target = Find-Target
$res    = Join-Path $target 'resources'
$asar   = Join-Path $res 'app.asar'
if ($Cfg.Method -eq 'files') {
    # Trae 系：无 app.asar，备份对象是主窗口 HTML
    $bak = ''
} elseif ($Cfg.MsixId) {
    # MSIX：备份放包外（包内会被整包更新整体替换），并先临时授权写入
    $bak = Join-Path (Join-Path $env:LOCALAPPDATA ($Cfg.MsixId + '\zwp-backup')) 'app.asar'
    New-Item -ItemType Directory -Path (Split-Path $bak) -Force | Out-Null
    Write-Step "临时授权写入 MSIX 包（takeown + icacls，仅限 resources 目录）"
    & takeown /f $res | Out-Null
    & icacls $res /grant '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    & takeown /f $asar | Out-Null
    & icacls $asar /grant '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "授权写入失败（takeown/icacls）" }
} else {
    $bak = Join-Path $res 'app.asar.zwp-backup'
}
Write-Step "$App 目录: $target"

# 先判补丁是否仍在：补丁完好 → 直接跳过打补丁（幂等，应用不必关闭）；
# 补丁丢失（应用升级覆盖）→ 走完整安装流程重打
$already = Test-PatchPresent
$run = (-not $already -or $Force)
if ($already -and -not $Force) {
    Write-Ok "$App 已含壁纸补丁，无需重复安装（应用升级覆盖补丁后重新运行本脚本即可修复）"
}
if ($Cfg.Method -ne 'files' -and $run -and -not (Test-Node)) { throw "未检测到 Node.js，请先安装 Node.js。" }

$appProc = Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue
if ($run) {
    if ($appProc -and $Cfg.StopRunning) {
        # AutoClaw 等常驻应用：已在提权实例中 → 直接结束进程（非提权实例走不到这里，上面已 exit）
        Write-Step "结束运行中的 $App（$(@($appProc).Count) 个进程）"
        $appProc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
        $appProc = Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue
    }
    if ($appProc) { throw "$App 正在运行，请先完全退出 $App 再执行补丁。" }
    if ($already -and $Force) {
        # -Force 强制重打：patch-inplace 拒绝重复注入，先从原版备份还原
        Write-Step "-Force：先从原版备份还原"
        if ($Cfg.Method -eq 'files') {
            $htmlPath = Join-Path $res $Cfg.ProbeRel
            if (-not (Test-Path "$htmlPath.zwp-backup")) { throw "无原版备份（$htmlPath.zwp-backup），无法 -Force。" }
            Copy-Item "$htmlPath.zwp-backup" $htmlPath -Force
            if ($Cfg.MainBridge) {
                $mainJs = Join-Path $res $Cfg.BridgeRel
                if (Test-Path "$mainJs.zwp-backup") { Copy-Item "$mainJs.zwp-backup" $mainJs -Force }
            }
        } else {
            if (-not (Test-Path $bak)) { throw "无原版备份（$bak），无法 -Force。" }
            Copy-Item $bak $asar -Force
            if ($Cfg.ExeHash) {
                $exeBak = Join-Path $target ($Cfg.Process + '.exe.zwp-backup')
                if (Test-Path $exeBak) { Copy-Item $exeBak (Join-Path $target ($Cfg.Process + '.exe')) -Force }
            }
        }
    }
    if ($Cfg.Method -ne 'files') {
        if (-not (Test-Path $bak)) {
            if (Test-AsarPatched $asar) {
                Write-Warn2 "当前 app.asar 已是补丁版且无原版备份：跳过备份（不把补丁版当原版）"
            } else {
                Write-Step "备份原版 app.asar"
                Copy-Item $asar $bak
                Write-Ok "备份到 $bak"
            }
        } else {
            Write-Warn2 "已存在备份 $bak（跳过备份，避免补丁版覆盖原版备份）"
        }
    }
}

# 生成注入脚本（替换壁纸目录占位符；OpenCode 走 wp:// 协议桥）
if ($run) {
    if ($Cfg.WallUrl) {
        $wallpaperDir = $Cfg.WallUrl
    } else {
        $wallpaperDir = ('file:///' + ($env:USERPROFILE -replace '\\', '/') + ($Cfg.WallDir.Substring($env:USERPROFILE.Length) -replace '\\', '/')).TrimEnd('/')
    }
    $wpContent = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles $Cfg.InjectSrc))
    $wpContent = $wpContent.Replace('__WALLPAPER_DIR__', $wallpaperDir)
    $injectFile = Join-Path $env:TEMP ("zwp-inject-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".js")
    Write-Utf8NoBom $injectFile $wpContent
    Write-Ok "注入脚本已生成（壁纸目录: $wallpaperDir）"
}

if ($run -and $Cfg.Method -eq 'files') {
    # Trae 系：散装 resources\app 目录，直接备份/改写主窗口 HTML + 落地注入脚本
    $htmlPath = Join-Path $res $Cfg.ProbeRel
    if (-not (Test-Path $htmlPath)) { throw "未找到主窗口 HTML（$($Cfg.ProbeRel)），此版本结构可能不兼容。" }
    $htmlDir  = Split-Path $htmlPath
    $htmlBak  = "$htmlPath.zwp-backup"
    if (-not (Test-Path $htmlBak)) {
        Write-Step "备份原版主窗口 HTML"
        Copy-Item $htmlPath $htmlBak
        Write-Ok "备份到 $htmlBak"
    } else {
        Write-Warn2 "已存在备份 $htmlBak（跳过备份，避免补丁版覆盖原版备份）"
    }

    Write-Step "落地壁纸注入脚本"
    Write-Utf8NoBom (Join-Path $htmlDir 'oc-wallpaper.js') $wpContent

    $html = [IO.File]::ReadAllText($htmlPath)
    if ($html -match 'oc-wallpaper') {
        Write-Warn2 "HTML 已包含壁纸脚本（跳过重复注入）"
    } else {
        # 多锚点回退：依次尝试候选注入点；全部落空退到"第一个 <script 标签前"
        # （壁纸脚本本身兼容 body 未就绪，极早注入无害）
        $marker = $null
        foreach ($mk in (@($Cfg.InjectBefore) + @('<script'))) {
            if ($mk -and $html.IndexOf($mk) -ge 0) { $marker = $mk; break }
        }
        if (-not $marker) {
            throw "HTML 中未找到任何注入点（候选: $($Cfg.InjectBefore -join ' / ')），此版本可能不兼容。"
        }
        $html = $html.Replace($marker, '<script src="./oc-wallpaper.js"></script>' + $marker)
        Write-Ok ("壁纸脚本标签已注入（锚点: " + $marker.Substring(0, [Math]::Min(40, $marker.Length)) + "…）")
    }
    if ($Cfg.RelaxCsp -and $html -match 'Content-Security-Policy') {
        # 允许壁纸子资源：wp:// 协议桥（custom.css 样式表、图片/视频、refresh 标记探测）+ file: 兜底
        $html = [regex]::Replace($html, '(?s)(\b(img-src|media-src|style-src)\b)([^;]*?)(;)', {
            param($m)
            $body = $m.Groups[3].Value
            if ($body -notmatch '(?<![a-zA-Z-])wp:(?![a-zA-Z-])')   { $body += ' wp:' }
            if ($body -notmatch '(?<![a-zA-Z-])file:(?![a-zA-Z-])') { $body += ' file:' }
            return $m.Groups[1].Value + $body + $m.Groups[4].Value
        })
        Write-Ok "CSP 已放宽（img/media/style-src 允许 wp: 与 file:）"
    }
    Write-Utf8NoBom $htmlPath $html
    Write-Ok "主窗口 HTML 已更新"

    if ($Cfg.MainBridge) {
        # 主进程桥：wp:// 协议服务壁纸目录，绕过 vscode-file:// 页面对 file:// 子资源的拦截
        $mainJs  = Join-Path $res $Cfg.BridgeRel
        if (-not (Test-Path $mainJs)) { throw "未找到主进程 bundle（$($Cfg.BridgeRel)），此版本结构可能不兼容。" }
        $mainBak = "$mainJs.zwp-backup"
        if (-not (Test-Path $mainBak)) {
            Write-Step "备份原版主进程 bundle"
            Copy-Item $mainJs $mainBak
            Write-Ok "备份到 $mainBak"
        }
        $mainText = [IO.File]::ReadAllText($mainJs)
        if ($mainText -match 'zcode-wallpaper bridge') {
            Write-Warn2 "主进程已含 wp:// 协议桥（跳过）"
        } else {
            # 1) 在首个 registerSchemesAsPrivileged 调用里注册 wp 特权协议（必须在 app ready 前）
            $find    = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'wp-scheme-find.txt'))
            $replace = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'wp-scheme-replace.txt'))
            $rx = [regex]::new($find.Trim())
            if (-not $rx.IsMatch($mainText)) { throw "主进程中未找到特权协议注册点（$find），此版本可能不兼容。" }
            $mainText = $rx.Replace($mainText, $replace.Replace('$', '$$'), 1)
            # 2) 末尾追加协议处理器（壁纸目录占位符 → 各应用实际目录）
            $homeRel   = $Cfg.WallDir.Substring($env:USERPROFILE.Length).TrimStart('\', '/').Replace('\', '/')
            $bridgeTxt = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'wp-bridge-append.js'))
            $mainText = $mainText.TrimEnd() + "`r`n" + $bridgeTxt.Replace('__WP_HOME_REL__', $homeRel)
            Write-Utf8NoBom $mainJs $mainText
            Write-Ok "wp:// 协议桥已注入（壁纸目录: %USERPROFILE%\$homeRel）"
        }
    }
} elseif ($run -and $Cfg.Method -eq 'inplace') {
    # WorkBuddy / OpenCode：原地补丁（数据区与 .unpacked 原样保留，脚本内置全量 SHA256 自校验）
    $nodeArgs = @((Join-Path $Script:RepoFiles 'patch-inplace.js'), $asar, $Cfg.RendererDir,
                  'index.html', 'oc-wallpaper.js', $injectFile, $Cfg.BundleName)
    if ($Cfg.ExeHash) {
        # 主程序内嵌 app.asar 头部哈希（Electron asar 完整性 fuse），需一并备份与更新
        $exePath = Join-Path $target ($Cfg.Process + '.exe')
        $exeBak  = Join-Path $target ($Cfg.Process + '.exe.zwp-backup')
        if (-not (Test-Path $exeBak)) {
            Write-Step "备份原版主程序"
            Copy-Item $exePath $exeBak
            Write-Ok "备份到 $exeBak"
        }
        $nodeArgs += @('--exe', $exePath)
        Write-Step "原地补丁 app.asar + 更新主程序内嵌头部哈希"
    } else {
        Write-Step "原地补丁 app.asar"
    }
    if ($Cfg.MainBridge) {
        # 主进程桥（OpenCode / Codex）：wp:// 协议服务壁纸目录，绕过自定义协议页面对 file:// 的拦截
        $bridgeRel = 'out/main/index.js'
        if ($Cfg.BridgeChunk) {
            # 多锚点回退：rolldown 产物里协议注册 chunk 的命名前缀依次试探。
            # 提权控制台代码页常为 GBK，node 输出经乱码后可能与状态行黏成一段 → 在整段输出里搜子串
            $chunks = @($Cfg.BridgeChunk)
            $resolved = ''
            foreach ($ch in $chunks) {
                $raw = (& node (Join-Path $Script:RepoFiles 'patch-inplace.js') --resolve $asar $Cfg.BridgeDir $ch 2>&1 |
                        Out-String)
                if ($LASTEXITCODE -ne 0) { continue }
                $m = [regex]::Match([string]$raw, [regex]::Escape($ch) + '[A-Za-z0-9._\-]*\.js')
                if ($m.Success) { $resolved = ($Cfg.BridgeDir + '/' + $m.Value); break }
            }
            if (-not $resolved) { throw "未能定位主进程 bundle（候选前缀: $($chunks -join ' / ')）" }
            $bridgeRel = $resolved
            Write-Ok "主进程 bundle: $bridgeRel"
        }
        $findFile    = Join-Path $Script:RepoFiles $(if ($Cfg.SchemeFind)    { $Cfg.SchemeFind }    else { 'wp-scheme-find.txt' })
        $replaceFile = Join-Path $Script:RepoFiles $(if ($Cfg.SchemeReplace) { $Cfg.SchemeReplace } else { 'wp-scheme-replace.txt' })
        # 桥接代码里的壁纸目录占位符 → 各应用实际目录（OpenCode 仍为 .opencode/wallpaper）
        $homeRel   = $Cfg.WallDir.Substring($env:USERPROFILE.Length).TrimStart('\', '/').Replace('\', '/')
        $bridgeSrc = Join-Path $env:TEMP ("zwp-bridge-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".js")
        $bridgeText = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'wp-bridge-append.js'))
        Write-Utf8NoBom $bridgeSrc ($bridgeText.Replace('__WP_HOME_REL__', $homeRel))
        $nodeArgs += @('--also-patch', $bridgeRel, $findFile, $replaceFile, $bridgeSrc)
    }
    $outAsar = $null
    if ($Cfg.MsixId) {
        # MSIX：包目录内新建/改名文件会被系统拒绝 → 产物写到 %TEMP%，再覆写原 asar 的文件内容
        $outAsar = Join-Path $env:TEMP ("zwp-out-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".asar")
        $nodeArgs += @('--out', $outAsar)
    }
    & node @nodeArgs
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $injectFile -Force -ErrorAction SilentlyContinue
        if ($outAsar) { Remove-Item $outAsar -Force -ErrorAction SilentlyContinue }
        throw "原地补丁失败"
    }
    if ($outAsar) {
        Write-Step "覆写原版 app.asar（文件内容替换）"
        # 预检：确认当前提权上下文真能写包内文件（WindowsApps 可能被安全软件/包完整性保护拦截）
        try {
            $w = [IO.File]::Open($asar, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
            $w.Close()
        } catch {
            Remove-Item $outAsar -Force -ErrorAction SilentlyContinue
            throw "无法以写模式打开 app.asar（$($_.Exception.Message)）。多为安全软件保护包目录：请暂时退出其防护（如火绒「系统防护」）后重试。"
        }
        $overwritten = $false
        foreach ($method in 1, 2, 3) {
            try {
                switch ($method) {
                    1 { Copy-Item $outAsar $asar -Force }
                    2 { [IO.File]::Copy($outAsar, $asar, $true) }
                    3 {
                        # 最后手段：删掉原文件再拷回（目录新建可能被拒；失败立即从原版备份恢复）
                        [IO.File]::SetAttributes($asar, [IO.FileAttributes]::Normal)
                        Remove-Item $asar -Force
                        try { Copy-Item $outAsar $asar } catch {
                            Copy-Item $bak $asar -Force
                            throw
                        }
                    }
                }
                $overwritten = $true
                break
            } catch { Write-Warn2 ("覆写方式 {0} 失败：{1}" -f $method, $_.Exception.Message) }
        }
        if (-not $overwritten) {
            Remove-Item $outAsar -Force -ErrorAction SilentlyContinue
            throw "覆写 app.asar 失败：包目录写入被保护。请暂时退出安全软件（如火绒）防护后重试。"
        }
        Remove-Item $outAsar -Force -ErrorAction SilentlyContinue
        Write-Ok "已覆写（$([math]::Round((Get-Item $asar).Length/1MB)) MB）"
    }
} elseif ($run) {
    # ZCode：解包 → 注入 → 重打包 → 校验原生模块外置清单
    $tmp = Join-Path $env:TEMP ("zwp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Write-Step "解包 app.asar"
    & npx --yes @electron/asar extract $asar $tmp | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "asar 解包失败" }

    $renderer = Join-Path $tmp $Cfg.RendererDir
    if (-not (Test-Path (Join-Path $renderer 'index.html'))) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "未找到 $($Cfg.RendererDir)\index.html，此版本结构可能不兼容。"
    }

    Write-Step "注入壁纸脚本"
    Write-Utf8NoBom (Join-Path $renderer 'oc-wallpaper.js') $wpContent

    $indexPath = Join-Path $renderer 'index.html'
    $html = [IO.File]::ReadAllText($indexPath)
    if ($html -match 'oc-wallpaper') {
        Write-Warn2 "index.html 已包含壁纸脚本（跳过重复注入）"
    } else {
        # 多锚点回退：应用升级改版后逐个尝试候选正则
        $patterns = @($Cfg.BundleRegex)
        if (-not $patterns[0]) { $patterns = @('(<script[^>]+src="\./assets/index-[^"]+\.js"[^>]*></script>)') }
        $pattern = $null
        foreach ($p0 in $patterns) { if ($html -match $p0) { $pattern = $p0; break } }
        if (-not $pattern) {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            throw "index.html 中未找到主 bundle script 标签（已尝试 $($patterns.Count) 个锚点），此版本可能不兼容。"
        }
        $html = [regex]::Replace($html, $pattern, '<script src="./oc-wallpaper.js"></script>$1', 'IgnoreCase')
        Write-Utf8NoBom $indexPath $html
        Write-Ok "index.html 已注入"
    }

    $newAsar = Join-Path $env:TEMP ("zwp-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".asar")
    Write-Step "重新打包 asar"
    & npx --yes @electron/asar pack $tmp $newAsar --unpack '**/*.{node,dll,exe}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "asar 打包失败" }

    Write-Step "校验原生模块外置清单"
    $oldList = Get-ChildItem (Join-Path $res 'app.asar.unpacked') -Recurse -File |
        ForEach-Object { $_.FullName.Substring($res.Length + 1) } | Sort-Object
    $newUnpacked = "$newAsar.unpacked"
    $newList = Get-ChildItem $newUnpacked -Recurse -File |
        ForEach-Object { $_.FullName.Substring($newUnpacked.Length + 1) } | Sort-Object
    $diff = Compare-Object $oldList $newList
    if ($diff) {
        $detail = ($diff | ForEach-Object { $_.InputObject }) -join ', '
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $newAsar -Force -ErrorAction SilentlyContinue
        Remove-Item $newUnpacked -Recurse -Force -ErrorAction SilentlyContinue
        throw "unpacked 清单不一致，已中止：$detail"
    }
    Write-Ok "一致（$($oldList.Count) 个文件）"

    Write-Step "替换 app.asar"
    Copy-Item $newAsar $asar -Force
    Write-Ok "已替换（$([math]::Round((Get-Item $asar).Length/1MB)) MB）"

    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $newAsar -Force -ErrorAction SilentlyContinue
    Remove-Item $newUnpacked -Recurse -Force -ErrorAction SilentlyContinue
}
if ($injectFile -and (Test-Path $injectFile)) { Remove-Item $injectFile -Force -ErrorAction SilentlyContinue }
Get-ChildItem "$env:TEMP\zwp-bridge-*.js" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}  # end: 非 agent / 非 marvis（asar/文件型）应用的安装流程

# 壁纸目录 + custom.css 模板
$wallDir = $Cfg.WallDir
New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
$customCss = Join-Path $wallDir 'custom.css'
if (-not (Test-Path $customCss)) {
    $css = @"
/* $App 皮肤自定义样式（可选），改完重启 $App 生效，删除本文件恢复默认。 */

/* 壁纸上的暗色遮罩（0 = 无遮罩，调大文字更清楚） */
#oc-wallpaper .oc-wp-shade { background: rgba(0, 0, 0, 0.18) !important; }

/* 壁纸不透明度 */
#oc-wallpaper video { opacity: 0.9 !important; }
#oc-wallpaper img   { opacity: 0.9 !important; }

/* 界面面板透明度示例（alpha 越小越透）。
   ZCode 覆盖 Tailwind 语义变量，WorkBuddy 覆盖 VS Code 主题变量，
   OpenCode 覆盖 --v2-background-* 设计令牌（暗色写在 :root[data-color-scheme="dark"]），
   Codex 覆盖 --color-surface-* / --color-background-* 两族（暗色写在 .electron-dark），例如：
:root, body {
  --vscode-editor-background: rgba(255, 255, 255, 0.55) !important;
  --vscode-sideBar-background: rgba(255, 255, 255, 0.50) !important;
  --v2-background-bg-base: rgba(255, 255, 255, 0.60) !important;
  --v2-background-bg-deep: rgba(250, 250, 250, 0.45) !important;
  --color-background-surface: rgba(255, 255, 255, 0.62) !important;
}
.dark {
  --color-background: rgba(23, 23, 23, 0.62) !important;
  --color-sidebar:    rgba(10, 10, 10, 0.60) !important;
}
.electron-dark {
  --color-background-surface: rgba(23, 23, 23, 0.60) !important;
}
*/
"@
    [IO.File]::WriteAllText($customCss, $css, [Text.UTF8Encoding]::new($true))
    Write-Ok "壁纸目录已创建: $wallDir"
}

# 统一选择器：装到中心目录 %USERPROFILE%\.ai-wallpaper，单一「AI壁纸设置」快捷方式，
# 可同时管理多个已打补丁的应用（同步/独立模式）
$hub        = Join-Path $env:USERPROFILE '.ai-wallpaper'
$hubLib     = Join-Path $hub 'library'
if (-not (Test-Path $hubLib)) { New-Item -ItemType Directory -Path $hubLib -Force | Out-Null }

# 修复工具链：把本脚本和 files\ 依赖复制到中心目录，「AI壁纸设置」的一键修复离线可用
# （应用升级覆盖补丁后，用户无需找回本仓库，直接在选择器里点「一键修复」）
Write-Step "部署修复工具链（$hub\repair）"
$repairDir   = Join-Path $hub 'repair'
$repairFiles = Join-Path $repairDir 'files'
foreach ($d in @($repairDir, $repairFiles)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
# 一键修复链路（health-check / 选择器）运行的正是 repair 里的这份副本：源=目标时复制必抛错
# （EAP=Stop 下中断收尾，补丁已好却被报失败），files 自拷自同样炸 → 检测到已运行于 repair 时跳过部署
$repairSelf = [IO.Path]::GetFullPath($PSCommandPath) -eq [IO.Path]::GetFullPath((Join-Path $repairDir 'apply-patch.ps1'))
if (-not $repairSelf) {
    Copy-Item $PSCommandPath (Join-Path $repairDir 'apply-patch.ps1') -Force
    Copy-Item (Join-Path $Script:RepoFiles '*') $repairFiles -Recurse -Force
} else {
    Write-Ok "修复工具链已在位（当前即运行于 repair 目录，跳过自部署）"
}
Write-Ok "已就绪：选择器「一键修复」自动识别安装目录并重打补丁"

# 升级自愈：部署体检脚本 + 注册登录时静默体检的计划任务。
# 体检本身只读（补丁完好零改动零 UAC）；失效时默认弹窗确认，health-check.ps1 -Silent 可全自动
$hcSrc = Join-Path $Script:RepoFiles 'health-check.ps1'
if (Test-Path $hcSrc) {
    $vbsPath = Join-Path $hub 'health-check.vbs'
    Write-Utf8NoBom $vbsPath (@'
' AI壁纸体检 - 登录时静默运行补丁体检；补丁失效时弹窗询问是否重打
Set sh = CreateObject("WScript.Shell")
hub = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.ai-wallpaper"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & hub & "\repair\files\health-check.ps1""", 0, False
'@)
    Write-Ok "体检脚本已部署: $hub\repair\files\health-check.ps1"
    if (-not $NoShortcut) {
        $tn = 'AI壁纸体检'
        $existing = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                $action  = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbsPath + '"')
                $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
                $trigger.Delay = 'PT2M'
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
                Register-ScheduledTask -TaskName $tn -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null
                Write-Ok "已注册登录体检任务「$tn」（移除：schtasks /Delete /TN $tn /F）"
            } catch { Write-Warn2 "计划任务注册失败（$($_.Exception.Message)），体检仍可手动运行" }
        }
    }
}

if (-not $NoShortcut) {
    Write-Step "部署「AI壁纸设置」统一选择器"
    # app.ico 被占用（选择器正开着，窗口图标握着句柄）不致命：hub 里已有同名文件
    try {
        Copy-Item (Join-Path $Script:RepoFiles 'app.ico') (Join-Path $hub 'app.ico') -Force -ErrorAction Stop
    } catch { Write-Warn2 "app.ico 复制跳过（被运行中的选择器占用，不影响使用）" }
    $pickerPath = Join-Path $hub 'wallpaper-picker.ps1'
    $pickerContent = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'wallpaper-picker.ps1'))
    # 带 BOM 写出：选择器由 Windows PowerShell 5.1 运行，无 BOM 的 UTF-8 中文会乱码
    [IO.File]::WriteAllText($pickerPath, $pickerContent, [Text.UTF8Encoding]::new($true))
    $launcher = Join-Path $hub 'AI壁纸设置.cmd'
    [IO.File]::WriteAllText($launcher,
        "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$pickerPath`"`r`n",
        [Text.Encoding]::Default)
    # exe 启动器（无黑窗 + 任务栏图标正确；csc 编译产物，源码 picker-launcher.cs）
    $exeSrc = Join-Path $Script:RepoFiles 'AI壁纸设置.exe'
    $exeHub = Join-Path $hub 'AI壁纸设置.exe'
    if (Test-Path $exeSrc) {
        Copy-Item $exeSrc $exeHub -Force
        $lnkTarget = $exeHub
    } else {
        Write-Warn2 "未找到 exe 启动器（AI壁纸设置.exe），快捷方式退回 cmd 入口"
        $lnkTarget = $launcher
    }
    foreach ($base in @([Environment]::GetFolderPath('Desktop'), "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
        # 清理旧版分应用选择器快捷方式
        foreach ($old in @('ZCode壁纸选择器', 'WorkBuddy壁纸选择器', 'OpenCode壁纸选择器')) {
            $oldLnk = Join-Path $base ($old + '.lnk')
            if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force -ErrorAction SilentlyContinue }
        }
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut((Join-Path $base 'AI壁纸设置.lnk'))
        $lnk.TargetPath = $lnkTarget
        $lnk.WorkingDirectory = $hub
        $lnk.IconLocation = "$hub\app.ico,0"
        $lnk.Save()
    }
    Write-Ok "桌面 + 开始菜单快捷方式已创建（AI壁纸设置）"
}

Write-Host ""
if ($run) {
    if ($Cfg.Method -eq 'marvis') {
        Write-Host "OK 补丁安装完成！重启 Marvis 即生效（壁纸直接可见；其窗口标题不显示 ✦ 属正常）。" -ForegroundColor Green
    } elseif ($Cfg.Method -eq 'dsh') {
        Write-Host "OK 补丁安装完成！重启 DeepSeek Harness 即生效（壁纸直接可见；窗口标题若被外壳固定则不显示 ✦，以壁纸可见为准）。" -ForegroundColor Green
    } else {
        Write-Host "OK 补丁安装完成！启动 $App，窗口标题出现 ✦ 即生效。" -ForegroundColor Green
    }
} else {
    Write-Host "OK $App 壁纸补丁完好，未做改动。" -ForegroundColor Green
}
Write-Host "   换壁纸：桌面「AI壁纸设置」（统一管理所有应用），或把文件改名为 wallpaper.扩展名 放入 $wallDir" -ForegroundColor Green
Write-Host "   应用升级后壁纸失效：打开「AI壁纸设置」→ 一键修复（自动识别安装目录重打补丁）" -ForegroundColor Green
if ($Elevated) { Write-Host ''; Read-Host '按回车关闭窗口' | Out-Null }
