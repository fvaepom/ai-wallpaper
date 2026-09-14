# ai-wallpaper 一键升级：把全部应用的壁纸补丁重打为当前版本（注入脚本有更新时使用）
#
# 用法（建议关闭所有打过补丁的应用后运行；运行中的应用会被跳过并在最后提示）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File upgrade-all.ps1
# 说明：
#   - 各应用补丁完好也会 -Force 重打（部署新版注入脚本）；不想强制的应用从清单里删掉即可
#   - Codex 为 MSIX 包，会弹 UAC 提权；AutoClaw 若在运行会请求提权结束进程
#   - 最后自动重跑壁纸去重迁移（运行中的应用文件被占用时会自动跳过）

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$apps = @('ZCode', 'OpenCode', 'WorkBuddy', 'Codex', 'TraeCN', 'TraeWorkCN', 'AutoClaw', 'Doubao', 'Marvis', 'Reasonix', 'DeepSeekHarness')
$procNames = @{
    ZCode = 'ZCode'; OpenCode = 'OpenCode'; WorkBuddy = 'WorkBuddy'; Codex = 'ChatGPT'
    TraeCN = 'Trae CN'; TraeWorkCN = 'TRAE SOLO CN'; AutoClaw = 'AutoClaw'; Doubao = 'Doubao'; Marvis = 'Marvis'; Reasonix = 'Reasonix'; DeepSeekHarness = 'DSH Desktop'
}

$skipped = @()
foreach ($a in $apps) {
    $pn = $procNames[$a]
    $running = $null -ne (Get-Process -Name $pn -ErrorAction SilentlyContinue)
    if ($running -and $a -notin @('Doubao', 'Marvis')) {
        Write-Host "== 跳过 $a（正在运行；关闭后重跑本脚本）" -ForegroundColor Yellow
        $skipped += $a
        continue
    }
    if ($running) { Write-Host "== $a 在运行：仅更新代理文件（下次启动生效）" -ForegroundColor Yellow }
    else { Write-Host "== 重打 $a ..." -ForegroundColor Cyan }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'apply-patch.ps1') -App $a -Force
    Write-Host ""
}

Write-Host "== 壁纸去重迁移（被占用的文件会自动跳过）..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo '_dedup-migrate.ps1')

Write-Host ""
if ($skipped.Count -gt 0) {
    Write-Host ("以下应用因正在运行被跳过，关闭后重跑本脚本即可：{0}" -f ($skipped -join '、')) -ForegroundColor Yellow
}
Write-Host "完成。启动各应用验证：标题出现 ✦ 即新版注入脚本已生效。" -ForegroundColor Green
