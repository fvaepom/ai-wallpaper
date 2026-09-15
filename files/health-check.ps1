# ai-wallpaper health-check — 各应用壁纸补丁体检 + 失效修复
#
# 由计划任务「AI壁纸体检」在登录时静默调用；也可手动运行：
#   powershell -NoProfile -ExecutionPolicy Bypass -File health-check.ps1 -Report   # 只打印各应用状态
#   powershell -NoProfile -ExecutionPolicy Bypass -File health-check.ps1           # 失效时弹窗询问是否重打
#   powershell -NoProfile -ExecutionPolicy Bypass -File health-check.ps1 -Silent   # 失效直接关闭应用重打并重启
#
# 设计：本脚本只做只读探测（不跑 apply-patch），补丁完好时零改动零 UAC；
# 只有确认失效才调用 repair\apply-patch.ps1 -Force（AutoClaw 需结束管理员进程时才会提权）。
# 注意：应用档案字段与 apply-patch.ps1 的 $Apps 表保持同步。

param([switch]$Silent, [switch]$Report)
$ErrorActionPreference = 'Continue'

$Hub    = Join-Path $env:USERPROFILE '.ai-wallpaper'
$Repair = Join-Path $Hub 'repair'
$Log    = Join-Path $Hub 'health.log'
$Apply  = Join-Path $Repair 'apply-patch.ps1'

# 已还原档案：用户主动还原过的应用记录在 restored.txt（一行一个应用 ID，# 后为注释）——
# 对其而言「补丁丢失」是期望状态，跳过体检与修复，否则登录体检会把还原当成补丁失效
# 再次自动重打。重新安装时 apply-patch 会自动从档案移除。
$RestoredFile = Join-Path $Hub 'restored.txt'
$Restored = @()
if (Test-Path $RestoredFile) {
    try {
        $Restored = @(Get-Content $RestoredFile -Encoding UTF8 |
            ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
            Where-Object { $_ })
    } catch { $Restored = @() }
}

$Apps = @(
    @{ App = 'ZCode';      Kind = 'asar';  Process = 'ZCode';        Candidates = @('F:\Program files\ZCode', 'C:\Program files\ZCode', "$env:LOCALAPPDATA\Programs\zcode", "$env:LOCALAPPDATA\Programs\ZCode") },
    @{ App = 'OpenCode';   Kind = 'asar';  Process = 'OpenCode';     Candidates = @("$env:LOCALAPPDATA\Programs\@opencode-aidesktop", 'F:\Program files\OpenCode', 'C:\Program files\OpenCode', "$env:LOCALAPPDATA\Programs\OpenCode") },
    @{ App = 'WorkBuddy';  Kind = 'asar';  Process = 'WorkBuddy';    Candidates = @('F:\Program files\WorkBuddy', 'C:\Program files\WorkBuddy', "$env:LOCALAPPDATA\Programs\WorkBuddy") },
    # Codex（2026-09-15 起）：散装副本 + CDP 代理（与豆包同架构）。补丁 = hub 里的启动器文件；
    # InstallDir 用于「未安装」判定（散装目录不存在且进程不在 → 视为未安装，避免无谓报 broken）
    @{ App = 'Codex';      Kind = 'agent'; Process = 'ChatGPT';      AgentFiles = @('codex-launcher.ps1', 'codex-launcher.vbs'); InstallDir = "$env:USERPROFILE\CodexPatched" },
    @{ App = 'TraeCN';     Kind = 'files'; Process = 'Trae CN';      Html = 'app\out\vs\code\electron-browser\workbench\workbench.html'; Candidates = @('F:\AIcodeprogram\Trae CN', "$env:LOCALAPPDATA\Programs\Trae CN") },
    @{ App = 'TraeWorkCN'; Kind = 'files'; Process = 'TRAE SOLO CN'; Html = 'app\out\vs\code\electron-browser\solo\solo-lite.html';      Candidates = @('F:\AIcodeprogram\TRAE SOLO CN', "$env:LOCALAPPDATA\Programs\TRAE SOLO CN") },
    @{ App = 'AutoClaw';   Kind = 'asar';  Process = 'AutoClaw';     Candidates = @('F:\AIcodeprogram\AUTOCLAW', 'C:\Program files\AutoClaw', "$env:LOCALAPPDATA\Programs\AutoClaw") },
    @{ App = 'Doubao';     Kind = 'agent'; Process = 'Doubao';       AgentFiles = @('doubao-launcher.ps1', 'doubao-launcher.vbs') },
    @{ App = 'Marvis';     Kind = 'marvis'; Process = 'Marvis';      OfflineIndex = "$env:APPDATA\Tencent\Marvis\marvis-offline-page\using\index.html" },
    @{ App = 'Reasonix';   Kind = 'reasonix'; Process = 'Reasonix';  Html = 'app\index.html'; Candidates = @('F:\AIcodeprogram\Reasonix', 'C:\Program files\Reasonix', "$env:LOCALAPPDATA\Programs\Reasonix") },
    @{ App = 'DeepSeekHarness'; Kind = 'dsh'; Process = 'DSH Desktop'; Html = 'app\node_modules\@deepseek-ai\dsh-web-frontend\dist\index.html'; Candidates = @("$env:LOCALAPPDATA\Programs\DSH Desktop") }
)

function Log([string]$msg) {
    try {
        $line = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') + ' ' + $msg
        $cur = ''
        if (Test-Path $Log) { $cur = Get-Content -LiteralPath $Log -Raw -Encoding UTF8 -ErrorAction SilentlyContinue }
        $tail = ($cur + $line + "`n") -split "`n" | Select-Object -Last 300
        [IO.File]::WriteAllText($Log, ($tail -join "`n"), [Text.UTF8Encoding]::new($false))
    } catch {}
}

function Test-AsarPatched([string]$path) {
    # 与 apply-patch.ps1 同款判定：补丁存在 ⇒ asar 头部必含 oc-wallpaper 条目，只读前 8MB
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

function Resolve-Asar($a) {
    if ($a.MsixId) {
        $pkg = Get-AppxPackage -Name $a.MsixId -ErrorAction SilentlyContinue
        if (-not $pkg -or -not $pkg.InstallLocation) { return $null }
        $p = Join-Path (Join-Path $pkg.InstallLocation 'app') 'resources\app.asar'
        if (Test-Path $p) { return $p }
        return $null
    }
    foreach ($c in $a.Candidates) {
        $p = Join-Path (Join-Path $c 'resources') 'app.asar'
        if (Test-Path $p) { return $p }
    }
    $proc = Get-Process -Name $a.Process -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($proc) {
        $p = Join-Path (Join-Path (Split-Path $proc.Path) 'resources') 'app.asar'
        if (Test-Path $p) { return $p }
    }
    return $null
}

# 返回 ok（补丁在）/ missing（未安装，跳过）/ broken（已安装但补丁失效）
function Test-AppHealth($a) {
    try {
        if ($a.Kind -eq 'agent') {
            # 安装判定（仅 Codex 这类带 InstallDir 的目标）：散装目录与进程都不在 → 未安装，跳过
            if ($a.InstallDir) {
                $installed = (Test-Path $a.InstallDir) -or [bool](Get-Process -Name $a.Process -ErrorAction SilentlyContinue)
                if (-not $installed) { return 'missing' }
            }
            foreach ($f in $a.AgentFiles) { if (-not (Test-Path (Join-Path $Hub $f))) { return 'broken' } }
            return 'ok'
        }
        if ($a.Kind -eq 'marvis') {
            if (-not (Test-Path $a.OfflineIndex)) { return 'missing' }
            if ([IO.File]::ReadAllText($a.OfflineIndex) -notmatch 'oc-wallpaper') { return 'broken' }
            return 'ok'
        }
        if ($a.Kind -eq 'dsh') {
            # DeepSeek Harness：补丁 = 安装目录回环前端 dist\index.html 含内联壁纸脚本
            $htmlPath = $null
            foreach ($c in $a.Candidates) {
                $p = Join-Path (Join-Path $c 'resources') $a.Html
                if (Test-Path $p) { $htmlPath = $p; break }
            }
            $proc = Get-Process -Name $a.Process -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
            if (-not $htmlPath -and $proc) {
                $p = Join-Path (Join-Path (Split-Path $proc.Path) 'resources') $a.Html
                if (Test-Path $p) { $htmlPath = $p }
            }
            if (-not $htmlPath) { return 'missing' }
            if ([IO.File]::ReadAllText($htmlPath) -notmatch 'oc-wallpaper') { return 'broken' }
            return 'ok'
        }
        if ($a.Kind -eq 'reasonix') {
            # Reasonix：launcher+versions 布局，候选为 launcher 根，经 current.json 解析激活版本
            $htmlPath = $null
            foreach ($c in $a.Candidates) {
                $cj = Join-Path $c 'current.json'
                if (-not (Test-Path $cj)) { continue }
                try { $meta = Get-Content $cj -Raw | ConvertFrom-Json } catch { continue }
                if (-not $meta.activeDir) { continue }
                $p = Join-Path (Join-Path (Join-Path $c $meta.activeDir) 'app') ('resources\' + $a.Html)
                if (Test-Path $p) { $htmlPath = $p; break }
            }
            if (-not $htmlPath) { return 'missing' }
            if ([IO.File]::ReadAllText($htmlPath) -notmatch 'oc-wallpaper') { return 'broken' }
            return 'ok'
        }
        if ($a.Kind -eq 'files') {
            $htmlPath = $null; $root = $null
            foreach ($c in $a.Candidates) {
                $p = Join-Path (Join-Path $c 'resources') $a.Html
                if (Test-Path $p) { $htmlPath = $p; $root = $c; break }
            }
            if (-not $htmlPath) { return 'missing' }
            if ([IO.File]::ReadAllText($htmlPath) -notmatch 'oc-wallpaper') { return 'broken' }
            $mainJs = Join-Path (Join-Path $root 'resources') 'app\out\main.js'
            if (-not (Test-Path $mainJs)) { return 'broken' }
            if ([IO.File]::ReadAllText($mainJs) -notmatch 'zcode-wallpaper bridge') { return 'broken' }
            return 'ok'
        }
        $asarPath = Resolve-Asar $a
        if (-not $asarPath) { return 'missing' }
        if (Test-AsarPatched $asarPath) { return 'ok' }
        return 'broken'
    } catch { Log ('probe ' + $a.App + ' error: ' + $_.Exception.Message); return 'unknown' }
}

function Repair-App($a) {
    if (-not (Test-Path $Apply)) { Log ($a.App + ' 无法修复：找不到 ' + $Apply); return $false }
    Log ($a.App + ' 修复开始：关闭应用 → 重打补丁')
    Get-Process -Name $a.Process -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Apply -App $a.App -Force
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok) { Log ($a.App + ' 补丁已重打') } else { Log ($a.App + ' 重打失败（退出码 ' + $LASTEXITCODE + '）') }
    return $ok
}

function Restart-App($a) {
    try {
        if ($a.ShellApp) { Start-Process $a.ShellApp; Log ($a.App + ' 已启动'); return }
        if ($a.Lnk -and (Test-Path $a.Lnk)) { Start-Process $a.Lnk; Log ($a.App + ' 已启动（' + $a.Lnk + '）'); return }
        $lnk = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like "*$($a.Process)*" } | Select-Object -First 1
        if ($lnk) { Start-Process $lnk.FullName; Log ($a.App + ' 已启动（' + $lnk.FullName + '）'); return }
        Log ($a.App + ' 已修复但未找到启动快捷方式，请手动启动')
    } catch { Log ($a.App + ' 启动失败: ' + $_.Exception.Message) }
}

$results = @()
foreach ($a in $Apps) {
    if ($Restored -contains $a.App) {
        Log ($a.App + ' -> restored (已还原，跳过体检)')
        if ($Report) { Write-Host ($a.App + ': restored') }
        continue
    }
    $st = Test-AppHealth $a
    $results += @{ App = $a.App; Status = $st; Cfg = $a }
    Log ($a.App + ' -> ' + $st)
}
if ($Report) { $results | ForEach-Object { Write-Host ($_.App + ': ' + $_.Status) }; exit 0 }

$broken = @($results | Where-Object { $_.Status -eq 'broken' })
if ($broken.Count -eq 0) { exit 0 }

$names = ($broken | ForEach-Object { $_.App }) -join '、'
if (-not $Silent) {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = "检测到以下应用的壁纸补丁失效：`n$names`n`n是否关闭对应应用并重新打补丁？（完成后可自动重启应用）"
    $ans = [System.Windows.Forms.MessageBox]::Show($msg, 'AI壁纸体检', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { Log '用户取消修复'; exit 0 }
}
foreach ($b in $broken) {
    $a = $b.Cfg
    if (Repair-App $a) {
        if ($Silent) { Restart-App $a }
        else {
            $r2 = [System.Windows.Forms.MessageBox]::Show(($a.App + " 补丁已重打，现在启动应用吗？"), 'AI壁纸体检', 'YesNo', 'Information')
            if ($r2 -eq 'Yes') { Restart-App $a }
        }
    }
}
