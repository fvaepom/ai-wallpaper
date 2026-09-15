# ai-wallpaper 发布构建：产出 release\ 下的自解压安装器 exe + 便携 zip
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-setup.ps1 [-Version 2.1.0]
# 产物：
#   release\ai-wallpaper-setup-v<版本>.exe   双击安装器（解压到 ~\.ai-wallpaper 并可选立即打补丁）
#   release\ai-wallpaper-v<版本>.zip         便携包（解压后手动运行 install-all.ps1）
param([string]$Version = '2.1.0')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$dist = Join-Path $repo 'release'
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "未找到 csc.exe（.NET Framework 4.x）" }

New-Item -ItemType Directory -Path $dist -Force | Out-Null
$stage = Join-Path $env:TEMP ("aiwp-payload-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage | Out-Null

try {
    # ── 组装 payload：运行时需要的仓库根脚本 + files\ 全部（排除源码/探测残留） ──
    foreach ($f in @('apply-patch.ps1', 'install-all.ps1', 'upgrade-all.ps1', '_dedup-migrate.ps1', '安装补丁.cmd')) {
        Copy-Item (Join-Path $repo $f) $stage -Force
    }
    $stageFiles = Join-Path $stage 'files'
    New-Item -ItemType Directory -Path $stageFiles | Out-Null
    Get-ChildItem (Join-Path $repo 'files') -File | Where-Object {
        $_.Name -notlike '*.cs' -and                  # exe 源码
        $_.Name -notlike '*-codex.txt' -and           # 开发机专用（patch-codex-loose 的探测残留）
        $_.Name -ne 'patch-codex-loose.ps1' -and      # 开发机一次性脚本（硬编码 MSIX 版本号）
        $_.Name -ne 'fix-bridge-guard.js' -and        # 开发机一次性脚本（硬编码本机 asar 路径）
        # ⚠ wp-scheme-find.txt / wp-scheme-replace.txt 不是残留：OpenCode/Trae 系运行时读取（协议桥载荷）
        $_.Name -ne 'wallpaper-picker.cmd'
    } | Copy-Item -Destination $stageFiles -Force

    # 使用说明（UTF-8 BOM，记事本直接可读）
    $readme = @"
ai-wallpaper — 给 AI 桌面应用注入动态壁纸
==========================================

【已双击 ai-wallpaper-setup-v$Version.exe 安装的情况】
  1. 安装器会把工具部署到 %USERPROFILE%\.ai-wallpaper\
  2. 在弹出的询问框点「是」，自动为本机已安装的应用打补丁
     （也可以后手动运行：同目录下的 install-all.ps1）
  3. 打完补丁后，桌面会出现「AI壁纸设置」快捷方式，双击即可换壁纸

【便携包（zip）用户】
  1. 解压到任意目录
  2. 以 PowerShell 运行：powershell -NoProfile -ExecutionPolicy Bypass -File .\install-all.ps1
     （自动跳过本机未安装的应用；也可用 apply-patch.ps1 -App <名称> 单独安装）

【日常使用】
  · 桌面「AI壁纸设置」：选择图片/视频、壁纸库、自动轮换、AI 生成、界面不透明度
  · 换壁纸免重启（标记热切换）；个别应用需重启一次才见新壁纸，详见仓库 README
  · 应用升级后补丁失效：重新打开「AI壁纸设置」，顶部警告条一键修复

【还原默认（撤销某个应用的壁纸补丁）】
  · 「AI壁纸设置」→「当前壁纸」页 → 选中应用 → 点「还原默认」：
    程序文件从原版备份还原、壁纸数据清除，回到打补丁前的最初状态
  · PowerShell / CMD 为清除 Windows Terminal 背景图，恢复默认纯色

【回滚】
  powershell -NoProfile -ExecutionPolicy Bypass -File apply-patch.ps1 -App <名称> -Rollback

开源仓库与详细文档：见 GitHub 仓库 ai-wallpaper（中文为主，含英文简介）
"@
    [IO.File]::WriteAllText((Join-Path $stage '使用说明.txt'), $readme, [Text.UTF8Encoding]::new($true))

    # ── 便携 zip ──
    $zipPath = Join-Path $dist ("ai-wallpaper-v$Version.zip")
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "OK 便携包: $zipPath ($([math]::Round((Get-Item $zipPath).Length/1KB)) KB)"

    # ── 自解压安装器 ──
    $payload = Join-Path $stage 'payload.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payload -CompressionLevel Optimal
    $exePath = Join-Path $dist ("ai-wallpaper-setup-v$Version.exe")
    & $csc /nologo /codepage:65001 /target:winexe /out:"$exePath" /win32icon:"$repo\files\app.ico" `
        /resource:"$payload,ai-wallpaper.payload.zip" `
        /r:System.IO.Compression.FileSystem.dll /r:System.IO.Compression.dll `
        (Join-Path $PSScriptRoot 'setup.cs')
    if ($LASTEXITCODE -ne 0) { throw "csc 编译失败" }
    Write-Host "OK 安装器: $exePath ($([math]::Round((Get-Item $exePath).Length/1MB, 2)) MB)"
} finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
