# ai-wallpaper 快捷方式与卸载注册（setup.exe 安装后 / 安装补丁.cmd 自动调用；幂等可重跑）
#  - 桌面 + 开始菜单「AI壁纸设置」→ hub 里的统一选择器（exe 优先，cmd 兜底）
#  - 开始菜单「卸载 ai-wallpaper」→ 卸载.cmd
#  - HKCU 注册卸载信息（设置 → 应用 列表可见、可一键卸载）
$ErrorActionPreference = 'Stop'
$hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
$ico = Join-Path $hub 'app.ico'
if (-not (Test-Path $ico)) { $ico = Join-Path $hub 'files\app.ico' }

# .lnk 刚写完可能被 Explorer/索引器瞬时握住（COMException）→ 删旧重写 + 重试
function Save-Shortcut([string]$path, [scriptblock]$fill) {
    for ($i = 1; $i -le 3; $i++) {
        try {
            if (Test-Path $path) { Remove-Item $path -Force -ErrorAction SilentlyContinue }
            $ws = New-Object -ComObject WScript.Shell
            $lnk = $ws.CreateShortcut($path)
            & $fill $lnk
            if ((Test-Path $ico) -and -not $lnk.IconLocation) { $lnk.IconLocation = "$ico,0" }
            $lnk.Save()
            return
        } catch {
            Write-Warning ("快捷方式写入失败（第 {0} 次，{1}）：{2}" -f $i, $path, $_.Exception.Message)
            Start-Sleep -Seconds 1
        }
    }
}

$target = Join-Path $hub 'AI壁纸设置.exe'
if (-not (Test-Path $target)) { $target = Join-Path $hub 'AI壁纸设置.cmd' }
foreach ($base in @([Environment]::GetFolderPath('Desktop'),
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
    Save-Shortcut (Join-Path $base 'AI壁纸设置.lnk') { param($lnk)
        $lnk.TargetPath = $target
        $lnk.WorkingDirectory = $hub
    }
}
Save-Shortcut (Join-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" '卸载 ai-wallpaper.lnk') { param($lnk)
    $lnk.TargetPath = (Join-Path $hub '卸载.cmd')
    $lnk.WorkingDirectory = $hub
}

$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ai-wallpaper'
$null = New-Item -Path $key -Force
Set-ItemProperty $key -Name DisplayName         -Value 'ai-wallpaper（AI 壁纸）'
Set-ItemProperty $key -Name DisplayVersion      -Value '1.0.6'
Set-ItemProperty $key -Name Publisher           -Value 'ai-wallpaper'
Set-ItemProperty $key -Name DisplayIcon         -Value (Join-Path $hub 'app.ico')
Set-ItemProperty $key -Name UninstallString     -Value ('cmd.exe /c "' + (Join-Path $hub '卸载.cmd') + '"')
Set-ItemProperty $key -Name NoModify            -Value 1 -Type DWord
Write-Host '快捷方式与卸载入口已就绪（桌面「AI壁纸设置」；开始菜单与系统设置里可卸载）'
