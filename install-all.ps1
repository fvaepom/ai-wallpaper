# ai-wallpaper 一键安装（新机器用）：逐个尝试为本机已安装的应用打壁纸补丁
#
# 用法（建议先关闭要打补丁的应用；脚本自动跳过本机未安装的应用）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install-all.ps1
# 说明：
#   - 对每个已安装的应用调用 apply-patch.ps1；未安装 / 不兼容的应用会报错并继续下一个
#   - Codex（商店 MSIX 散装副本方案）与 AutoClaw（常驻管理员进程）可能弹 UAC，请放行
#   - 打完补丁后双击桌面「AI壁纸设置」换壁纸；详读 使用说明.txt

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$apps = @('ZCode', 'OpenCode', 'WorkBuddy', 'Codex', 'TraeCN', 'TraeWorkCN',
          'AutoClaw', 'Doubao', 'Marvis', 'Reasonix', 'DeepSeekHarness')

$ok = @(); $skip = @(); $fail = @()
foreach ($a in $apps) {
    Write-Host "== 安装 $a ..." -ForegroundColor Cyan
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'apply-patch.ps1') -App $a 2>&1
    if ($LASTEXITCODE -eq 0) { $ok += $a }
    elseif (($out | Out-String) -match '未找到 .* 安装目录|MSIX 包') { $skip += $a; Write-Host "   本机未安装，跳过" -ForegroundColor DarkGray }
    else { $fail += $a; Write-Host ($out | Select-Object -Last 2) -ForegroundColor Yellow }
    Write-Host ""
}

Write-Host ("安装成功：{0}" -f ($ok -join '、')) -ForegroundColor Green
if ($skip.Count) { Write-Host ("本机未安装（跳过）：{0}" -f ($skip -join '、')) -ForegroundColor DarkGray }
if ($fail.Count) {
    Write-Host ("失败（可单独重试，如 powershell -File apply-patch.ps1 -App <名称>）：{0}" -f ($fail -join '、')) -ForegroundColor Yellow
}
Write-Host ""
Write-Host "完成。双击桌面「AI壁纸设置」即可换壁纸。" -ForegroundColor Green
