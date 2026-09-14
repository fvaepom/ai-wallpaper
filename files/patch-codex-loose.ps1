# patch-codex-loose.ps1 — 对散装 Codex 副本（C:\Users\FVAEP\CodexPatched）打/重打 asar 补丁
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\patch-codex-loose.ps1 [-Reset]
#   -Reset: 先从 WindowsApps 原版把 app.asar 拷回来再打（重打/换桥接代码时用）
param([switch]$Reset)
$ErrorActionPreference = 'Stop'
$CopyAsar  = 'C:\Users\FVAEP\CodexPatched\app\resources\app.asar'
$OrigAsar  = 'C:\Program Files\WindowsApps\OpenAI.Codex_26.908.4834.0_x64__2p2nqsd0c76g0\app\resources\app.asar'
$RepoFiles = 'H:\zcode改造\zcode-wallpaper\files'

if ($Reset) {
    Write-Host "==> 从原版恢复 app.asar（26.908.4834.0）"
    Copy-Item $OrigAsar $CopyAsar -Force
}

$wp = [IO.File]::ReadAllText((Join-Path $RepoFiles 'oc-wallpaper-codex.js')).Replace('__WALLPAPER_DIR__', 'wp://local')
$inject = Join-Path $env:TEMP 'zwp-inject-codexloose.js'
[IO.File]::WriteAllText($inject, $wp, [Text.UTF8Encoding]::new($false))
$br = [IO.File]::ReadAllText((Join-Path $RepoFiles 'wp-bridge-append.js')).Replace('__WP_HOME_REL__', '.codex/wallpaper')
$bridge = Join-Path $env:TEMP 'zwp-bridge-codexloose.js'
[IO.File]::WriteAllText($bridge, $br, [Text.UTF8Encoding]::new($false))

& node (Join-Path $RepoFiles 'patch-inplace.js') $CopyAsar 'webview' 'index.html' 'oc-wallpaper.js' $inject 'index' --also-patch '.vite/build/window-all-closed-BxbCP6YG.js' (Join-Path $RepoFiles 'wp-scheme-find-codex.txt') (Join-Path $RepoFiles 'wp-scheme-replace-codex.txt') $bridge
if ($LASTEXITCODE -ne 0) { throw "patch failed (exit $LASTEXITCODE)" }
Remove-Item $inject, $bridge -Force -ErrorAction SilentlyContinue
Write-Host "OK loose copy patched: $CopyAsar"
