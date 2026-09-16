# 重新编译 files\AI壁纸设置.exe（源码 files\picker-launcher.cs；改源码后重跑本脚本）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-picker-exe.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "未找到 csc.exe（.NET Framework 4.x）" }
& $csc /nologo /codepage:65001 /target:winexe /out:"$repo\files\AI壁纸设置.exe" `
    /win32icon:"$repo\files\app.ico" (Join-Path $repo 'files\picker-launcher.cs')
if ($LASTEXITCODE -ne 0) { throw "csc 编译失败" }
Write-Host ("OK files\AI壁纸设置.exe ({0} KB)" -f [math]::Round((Get-Item "$repo\files\AI壁纸设置.exe").Length/1KB))
