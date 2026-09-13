# zcode-wallpaper — ZCode / OpenCode / WorkBuddy Desktop 动态壁纸补丁
# 用法：
#   ZCode:     powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1
#   OpenCode:  powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App OpenCode
#   WorkBuddy: powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -App WorkBuddy
#   回滚:      powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 [-App OpenCode|WorkBuddy] -Rollback
# 需要: Node.js（ZCode/OpenCode 用 npx @electron/asar；WorkBuddy 用内置 patch-inplace.js，零依赖），目标应用处于关闭状态。

param(
    [string]$App = 'ZCode',
    [string]$InstallDir = '',
    [switch]$Rollback,
    [switch]$NoShortcut
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
        BundleRegex = '(<script type="module" crossorigin src="\./assets/index-[^"]+\.js"></script>)'
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
}
if (-not $Apps.ContainsKey($App)) {
    throw "未知应用 '$App'，支持：$($Apps.Keys -join ' / ')"
}
$Cfg = $Apps[$App]

function Find-Target {
    if ($InstallDir) { return $InstallDir }
    foreach ($c in $Cfg.Candidates) {
        if (Test-Path (Join-Path $c 'resources\app.asar')) { return $c }
    }
    # 通过开始菜单快捷方式反查
    if (Test-Path $Cfg.Lnk) {
        $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($Cfg.Lnk)
        $dir = Split-Path $sh.TargetPath
        if (Test-Path (Join-Path $dir 'resources\app.asar')) { return $dir }
    }
    throw "未找到 $App 安装目录，请用 -InstallDir 参数指定。"
}

function Test-Node {
    try { $null = & node --version 2>$null; return $LASTEXITCODE -eq 0 } catch { return $false }
}

function Write-Utf8NoBom($path, $content) {
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
}

# ── 回滚 ────────────────────────────────────────────────
if ($Rollback) {
    $target = Find-Target
    $res = Join-Path $target 'resources'
    $bak = Join-Path $res 'app.asar.zwp-backup'
    if (-not (Test-Path $bak)) { throw "未找到备份文件 $bak，无法回滚。" }
    Write-Step "恢复原版 app.asar"
    Copy-Item $bak (Join-Path $res 'app.asar') -Force
    $exeBak = Join-Path $target ($Cfg.Process + '.exe.zwp-backup')
    if (Test-Path $exeBak) {
        Write-Step "恢复原版主程序（内嵌头部哈希）"
        Copy-Item $exeBak (Join-Path $target ($Cfg.Process + '.exe')) -Force
        Write-Ok "已恢复 $exeBak 对应的原版主程序"
    }
    Write-Ok "已恢复。确认正常后可删除 $bak 释放空间。"
    exit 0
}

# ── 安装 ────────────────────────────────────────────────
if (-not (Test-Node)) { throw "未检测到 Node.js，请先安装 Node.js。" }
$target = Find-Target
$res    = Join-Path $target 'resources'
$asar   = Join-Path $res 'app.asar'
$bak    = Join-Path $res 'app.asar.zwp-backup'
Write-Step "$App 目录: $target"

$appProc = Get-Process -Name $Cfg.Process -ErrorAction SilentlyContinue
if ($appProc) { throw "$App 正在运行，请先完全退出 $App 再执行补丁。" }

if (-not (Test-Path $bak)) {
    Write-Step "备份原版 app.asar"
    Copy-Item $asar $bak
    Write-Ok "备份到 $bak"
} else {
    Write-Warn2 "已存在备份 $bak（跳过备份，避免补丁版覆盖原版备份）"
}

# 生成注入脚本（替换壁纸目录占位符；OpenCode 走 wp:// 协议桥）
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

if ($Cfg.Method -eq 'inplace') {
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
        # 主进程桥（OpenCode）：wp:// 协议服务壁纸目录，绕过 oc:// 页面对 file:// 的拦截
        $nodeArgs += @('--also-patch', 'out/main/index.js',
            (Join-Path $Script:RepoFiles 'wp-scheme-find.txt'),
            (Join-Path $Script:RepoFiles 'wp-scheme-replace.txt'),
            (Join-Path $Script:RepoFiles 'wp-bridge-append.js'))
    }
    & node @nodeArgs
    if ($LASTEXITCODE -ne 0) { Remove-Item $injectFile -Force -ErrorAction SilentlyContinue; throw "原地补丁失败" }
} else {
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
        $pattern = $Cfg.BundleRegex
        if (-not $pattern) { $pattern = '(<script type="module" crossorigin src="\./assets/index-[^"]+\.js"></script>)' }
        if ($html -notmatch $pattern) {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            throw "index.html 中未找到主 bundle script 标签，此版本可能不兼容。"
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
Remove-Item $injectFile -Force -ErrorAction SilentlyContinue

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
   OpenCode 覆盖 --background-* 变量（暗色写在 :root[data-color-scheme="dark"]），例如：
:root, body {
  --vscode-editor-background: rgba(255, 255, 255, 0.55) !important;
  --vscode-sideBar-background: rgba(255, 255, 255, 0.50) !important;
  --background-base: rgba(248, 248, 248, 0.66) !important;
}
.dark {
  --color-background: rgba(23, 23, 23, 0.62) !important;
  --color-sidebar:    rgba(10, 10, 10, 0.60) !important;
}
*/
"@
    [IO.File]::WriteAllText($customCss, $css, [Text.UTF8Encoding]::new($true))
    Write-Ok "壁纸目录已创建: $wallDir"
}

# 快捷方式（选择器脚本按应用名生成对应文案/目录/进程名）
if (-not $NoShortcut) {
    Write-Step "创建「$App 壁纸选择器」快捷方式"
    Copy-Item (Join-Path $Script:RepoFiles 'app.ico') (Join-Path $wallDir 'app.ico') -Force
    $pickerContent = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'wallpaper-picker.ps1'))
    if ($App -ne 'ZCode') {
        # 选择器脚本中的 'ZCode' 文案/进程名与 '.zcode' 壁纸目录一并替换为目标应用
        $pickerContent = ($pickerContent -creplace 'ZCode', $App) -creplace '\.zcode', ('.' + $App.ToLower())
    }
    $pickerPath = Join-Path $wallDir 'wallpaper-picker.ps1'
    # 带 BOM 写出：选择器由 Windows PowerShell 5.1 运行，无 BOM 的 UTF-8 中文会乱码
    [IO.File]::WriteAllText($pickerPath, $pickerContent, [Text.UTF8Encoding]::new($true))
    $launcher = Join-Path $wallDir ($App + '壁纸选择器.cmd')
    [IO.File]::WriteAllText($launcher,
        "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$pickerPath`"`r`n",
        [Text.Encoding]::Default)
    foreach ($base in @([Environment]::GetFolderPath('Desktop'), "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut((Join-Path $base ($App + '壁纸选择器.lnk')))
        $lnk.TargetPath = $launcher
        $lnk.WorkingDirectory = $wallDir
        $lnk.IconLocation = "$wallDir\app.ico,0"
        $lnk.Save()
    }
    Write-Ok "桌面 + 开始菜单快捷方式已创建"
}

Write-Host ""
Write-Host "OK 补丁安装完成！启动 $App，窗口标题出现 ✦ 即生效。" -ForegroundColor Green
Write-Host "   换壁纸：桌面「$App 壁纸选择器」，或把文件改名为 wallpaper.扩展名 放入 $wallDir" -ForegroundColor Green
