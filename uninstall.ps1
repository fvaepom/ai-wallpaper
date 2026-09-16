# ai-wallpaper 卸载：逐应用回滚壁纸补丁 → 移除快捷方式 / 计划任务 / 卸载注册信息
# 工具目录（本脚本所在目录）由 卸载.cmd 在本脚本结束后删除；各应用的壁纸图片文件保留。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 [-KeepPatches]
#   -KeepPatches：只移除工具本体与自启项，保留各应用已打的壁纸补丁（一般不需要）
param([switch]$KeepPatches)
$ErrorActionPreference = 'Continue'
$hub = $PSScriptRoot
$apps = @('ZCode', 'OpenCode', 'WorkBuddy', 'Codex', 'TraeCN', 'TraeWorkCN',
          'AutoClaw', 'Doubao', 'Marvis', 'Reasonix', 'DeepSeekHarness')

if (-not $KeepPatches) {
    $ok = @(); $skip = @(); $fail = @()
    foreach ($a in $apps) {
        Write-Host "== 回滚 $a ..." -ForegroundColor Cyan
        # 回滚不存在的应用 / 未打补丁的应用会报错退出（未找到安装目录 / 未找到备份）→ 归为跳过
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hub 'apply-patch.ps1') -App $a -Rollback 2>&1
        if ($LASTEXITCODE -eq 0) { $ok += $a }
        elseif (($out | Out-String) -match '未找到 .*(安装目录|激活版本目录)|MSIX 包|无法回滚') { $skip += $a }
        else { $fail += $a; Write-Host ($out | Select-Object -Last 4) -ForegroundColor Yellow }
    }
    Write-Host ("已回滚：{0}" -f ($ok -join '、')) -ForegroundColor Green
    if ($skip.Count) { Write-Host ("无需回滚（未安装/未打补丁）：{0}" -f ($skip -join '、')) -ForegroundColor DarkGray }
    if ($fail.Count) { Write-Host ("回滚失败（可单独重试 powershell -File apply-patch.ps1 -App <名称> -Rollback）：{0}" -f ($fail -join '、')) -ForegroundColor Yellow }
}

# 计划任务：登录体检 + 壁纸媒体服务（均为用户级，无需管理员）
foreach ($tn in @('AI壁纸体检', 'AI壁纸媒体服务')) {
    Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
}

# 快捷方式：桌面/开始菜单「AI壁纸设置」+ 开始菜单「卸载 ai-wallpaper」
foreach ($base in @([Environment]::GetFolderPath('Desktop'),
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
    Remove-Item (Join-Path $base 'AI壁纸设置.lnk') -Force -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" '卸载 ai-wallpaper.lnk') -Force -ErrorAction SilentlyContinue

# 「设置 → 应用」卸载注册信息
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ai-wallpaper' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($KeepPatches) {
    Write-Host "工具与自启项已移除，各应用壁纸补丁按要求保留。" -ForegroundColor Green
} else {
    Write-Host "应用补丁已回滚，自启项与快捷方式已移除。" -ForegroundColor Green
}
Write-Host "各应用的壁纸目录（壁纸图片文件）保留，可自行删除："
Write-Host "  %USERPROFILE%\.zcode\wallpaper  .opencode  .workbuddy  .trae-cn  .doubao  .marvis  等同名目录"
