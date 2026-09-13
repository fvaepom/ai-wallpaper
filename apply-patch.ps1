# zcode-wallpaper — ZCode Desktop 动态壁纸补丁
# 用法：
#   安装:   powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1
#   回滚:   powershell -NoProfile -ExecutionPolicy Bypass -File .\apply-patch.ps1 -Rollback
# 需要: Node.js（npx @electron/asar），ZCode 处于关闭状态。

param(
    [string]$InstallDir = '',
    [switch]$Rollback,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
$Script:RepoFiles = Join-Path $PSScriptRoot 'files'

function Write-Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

function Find-ZCode {
    if ($InstallDir) { return $InstallDir }
    $candidates = @(
        'F:\Program files\ZCode',
        'C:\Program files\ZCode',
        "$env:LOCALAPPDATA\Programs\zcode",
        "$env:LOCALAPPDATA\Programs\ZCode"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'resources\app.asar')) { return $c }
    }
    # 通过开始菜单快捷方式反查
    $lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ZCode.lnk"
    if (Test-Path $lnk) {
        $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $dir = Split-Path $sh.TargetPath
        if (Test-Path (Join-Path $dir 'resources\app.asar')) { return $dir }
    }
    throw "未找到 ZCode 安装目录，请用 -InstallDir 参数指定。"
}

function Test-Node {
    try { $null = & npx --version 2>$null; return $LASTEXITCODE -eq 0 } catch { return $false }
}

function Write-Utf8NoBom($path, $content) {
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
}

# ── 回滚 ────────────────────────────────────────────────
if ($Rollback) {
    $zcode = Find-ZCode
    $res = Join-Path $zcode 'resources'
    $bak = Join-Path $res 'app.asar.zwp-backup'
    if (-not (Test-Path $bak)) { throw "未找到备份文件 $bak，无法回滚。" }
    Write-Step "恢复原版 app.asar"
    Copy-Item $bak (Join-Path $res 'app.asar') -Force
    Write-Ok "已恢复。确认正常后可删除 $bak 释放空间。"
    exit 0
}

# ── 安装 ────────────────────────────────────────────────
if (-not (Test-Node)) { throw "未检测到 Node.js / npx，请先安装 Node.js。" }
$zcode = Find-ZCode
$res   = Join-Path $zcode 'resources'
$asar  = Join-Path $res 'app.asar'
$bak   = Join-Path $res 'app.asar.zwp-backup'
Write-Step "ZCode 目录: $zcode"

$zcodeProc = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
if ($zcodeProc) { throw "ZCode 正在运行，请先完全退出 ZCode 再执行补丁。" }

if (-not (Test-Path $bak)) {
    Write-Step "备份原版 app.asar"
    Copy-Item $asar $bak
    Write-Ok "备份到 $bak"
} else {
    Write-Warn2 "已存在备份 $bak（跳过备份，避免补丁版覆盖原版备份）"
}

# 解包
$tmp = Join-Path $env:TEMP ("zwp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
Write-Step "解包 app.asar"
& npx --yes @electron/asar extract $asar $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw "asar 解包失败" }

$renderer = Join-Path $tmp 'out\renderer'
if (-not (Test-Path (Join-Path $renderer 'index.html'))) {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    throw "未找到 out\renderer\index.html，此版本结构可能不兼容。"
}

# 注入 oc-wallpaper.js（替换壁纸目录占位符）
Write-Step "注入壁纸脚本"
$wallpaperDir = ('file:///' + ($env:USERPROFILE -replace '\\', '/') + '/.zcode/wallpaper').TrimEnd('/')
$wpContent = [IO.File]::ReadAllText((Join-Path $Script:RepoFiles 'oc-wallpaper.js'))
$wpContent = $wpContent.Replace('__WALLPAPER_DIR__', $wallpaperDir)
Write-Utf8NoBom (Join-Path $renderer 'oc-wallpaper.js') $wpContent
Write-Ok "oc-wallpaper.js 已写入（壁纸目录: $wallpaperDir）"

# 注入 index.html
$indexPath = Join-Path $renderer 'index.html'
$html = [IO.File]::ReadAllText($indexPath)
if ($html -match 'oc-wallpaper') {
    Write-Warn2 "index.html 已包含壁纸脚本（跳过重复注入）"
} else {
    $pattern = '(<script type="module" crossorigin src="\./assets/index-[^"]+\.js"></script>)'
    if ($html -notmatch $pattern) {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "index.html 中未找到主 bundle script 标签，此版本可能不兼容。"
    }
    $html = [regex]::Replace($html, $pattern, '<script src="./oc-wallpaper.js"></script>$1', 'IgnoreCase')
    Write-Utf8NoBom $indexPath $html
    Write-Ok "index.html 已注入"
}

# 重新打包
$newAsar = Join-Path $env:TEMP ("zwp-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".asar")
Write-Step "重新打包 asar"
& npx --yes @electron/asar pack $tmp $newAsar --unpack '**/*.{node,dll,exe}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "asar 打包失败" }

# 校验原生模块外置清单与原包一致
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

# 替换
Write-Step "替换 app.asar"
Copy-Item $newAsar $asar -Force
Write-Ok "已替换（$([math]::Round((Get-Item $asar).Length/1MB)) MB）"

# 壁纸目录 + custom.css 模板
$wallDir = Join-Path $env:USERPROFILE '.zcode\wallpaper'
New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
$customCss = Join-Path $wallDir 'custom.css'
if (-not (Test-Path $customCss)) {
    $css = @'
/* ZCode 皮肤自定义样式（可选），改完重启 ZCode 生效，删除本文件恢复默认。 */

/* 壁纸上的暗色遮罩（0 = 无遮罩，调大文字更清楚） */
#oc-wallpaper .oc-wp-shade { background: rgba(0, 0, 0, 0.18) !important; }

/* 壁纸不透明度 */
#oc-wallpaper video { opacity: 0.9 !important; }
#oc-wallpaper img   { opacity: 0.9 !important; }

/* 界面面板透明度示例（alpha 越小越透）：
.dark {
  --color-background: rgba(23, 23, 23, 0.62) !important;
  --color-sidebar:    rgba(10, 10, 10, 0.60) !important;
}
*/
'@
    [IO.File]::WriteAllText($customCss, $css, [Text.UTF8Encoding]::new($true))
    Write-Ok "壁纸目录已创建: $wallDir"
}

# 快捷方式
if (-not $NoShortcut) {
    Write-Step "创建「ZCode壁纸选择器」快捷方式"
    Copy-Item (Join-Path $Script:RepoFiles 'app.ico') (Join-Path $wallDir 'app.ico') -Force
    Copy-Item (Join-Path $Script:RepoFiles 'wallpaper-picker.ps1') (Join-Path $wallDir 'wallpaper-picker.ps1') -Force
    $launcher = Join-Path $wallDir 'ZCode壁纸选择器.cmd'
    [IO.File]::WriteAllText($launcher,
        "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$wallDir\wallpaper-picker.ps1`"`r`n",
        [Text.Encoding]::Default)
    foreach ($base in @([Environment]::GetFolderPath('Desktop'), "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut((Join-Path $base 'ZCode壁纸选择器.lnk'))
        $lnk.TargetPath = $launcher
        $lnk.WorkingDirectory = $wallDir
        $lnk.IconLocation = "$wallDir\app.ico,0"
        $lnk.Save()
    }
    Write-Ok "桌面 + 开始菜单快捷方式已创建"
}

# 清理
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $newAsar -Force -ErrorAction SilentlyContinue
Remove-Item $newUnpacked -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "OK 补丁安装完成！启动 ZCode，窗口标题出现 ✦ 即生效。" -ForegroundColor Green
Write-Host "   换壁纸：桌面「ZCode壁纸选择器」，或把文件改名为 wallpaper.扩展名 放入 $wallDir" -ForegroundColor Green
