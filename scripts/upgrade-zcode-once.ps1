# upgrade-zcode-once — 等待 ZCode 完全退出后，把壁纸补丁重打为当前版注入脚本并重启 ZCode。
#
# 背景（2026-09-16）：ZCode asar 里部署的还是 9/13 初版脚本（不消费 --ocwp-ui-alpha、
# 不热重载 custom.css）→ 选择器「界面不透明度」滑杆对 ZCode 一直无效。而 ZCode 正在运行时
# 无法重打 asar；本脚本以独立进程常驻，用户随时关闭 ZCode 即自动完成升级并拉回 ZCode。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File upgrade-zcode-once.ps1
#       [-Apply <apply-patch.ps1 路径>] [-TimeoutHours 24]
# 日志：~\.ai-wallpaper\upgrade-zcode.log；重复运行安全（新版已部署即直接退出）。

param(
    [string]$Apply,
    [int]$TimeoutHours = 24
)
$ErrorActionPreference = 'Continue'
$Hub     = Join-Path $env:USERPROFILE '.ai-wallpaper'
$LogPath = Join-Path $Hub 'upgrade-zcode.log'
$Lnk     = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ZCode.lnk'
$Asar    = 'F:\Program files\ZCode\resources\app.asar'
if (-not $Apply) {
    # 兼容两种部署位置：仓库 scripts\ 下（apply-patch 在上级目录）与 hub 根（apply-patch 在 repair\ 子目录）
    $cand = Join-Path (Split-Path $PSScriptRoot -Parent) 'apply-patch.ps1'
    if (-not (Test-Path $cand)) { $cand = Join-Path (Join-Path $PSScriptRoot 'repair') 'apply-patch.ps1' }
    $Apply = $cand
}

function Log([string]$msg) {
    try {
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {}
}

# asar 里是否已是新版脚本：新版头部带 zwp-ver: 标记，且以文件内容形式存于归档前部
# （patch-inplace 追加数据区在归档末尾，但小 index.html/oc-wallpaper.js 重打后仍靠前；
#  稳妥起见全文搜标记，275MB 单次顺序读约 1-2 秒，只在启动时跑一次）
function Test-UpToDate {
    if (-not (Test-Path $Asar)) { return $false }
    try {
        $text = [IO.File]::ReadAllText($Asar)
        return $text.Contains('zwp-ver:2')
    } catch { return $false }
}

Log ("等待式升级启动 (apply=" + $Apply + ")")
if (Test-UpToDate) { Log 'ZCode 已是新版脚本，无需升级，退出'; exit 0 }

$deadline = (Get-Date).AddHours($TimeoutHours)
while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Start-Sleep -Seconds 5
}
if (Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue) { Log '等待超时（ZCode 仍在运行），退出'; exit 1 }
Start-Sleep -Seconds 3   # 留出文件句柄释放时间

if (Test-UpToDate) { Log 'ZCode 退出后发现已是新版（可能被其他实例升级），退出'; exit 0 }
if (-not (Test-Path $Apply)) { Log ('找不到 apply-patch.ps1：' + $Apply + '，退出'); exit 1 }

Log 'ZCode 已退出，开始重打补丁（-Force）'
& powershell -NoProfile -ExecutionPolicy Bypass -File $Apply -App ZCode -Force *>> $LogPath
if ($LASTEXITCODE -ne 0) {
    Log ('重打失败（退出码 ' + $LASTEXITCODE + '）。不自动重启 ZCode；可回滚后重试：copy /y "resources\app.asar.zwp-backup" 覆盖 app.asar')
    exit 1
}

Log '重打完成，启动 ZCode'
if (Test-Path $Lnk) { Start-Process $Lnk }
else { Start-Process (Join-Path (Split-Path $Asar -Parent) '..\ZCode.exe') }
Log '等待式升级结束'
