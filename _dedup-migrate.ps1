# 壁纸去重迁移（一次性）：各组视频的已编码 canonical 放在 hub\wallpaper\，
# 各应用目录的 wallpaper.mp4 替换为指向 canonical 的 NTFS 硬链接（同内容共享一份磁盘空间）。
# 运行中的应用若文件被占用则跳过（留给下次关闭后重跑）；替换成功且应用在运行时写 refresh 标记热生效。
$ErrorActionPreference = 'Continue'
$hub = Join-Path $env:USERPROFILE '.ai-wallpaper'
$groups = @(
    @{ Canonical = Join-Path $hub 'wallpaper\dedup-a.mp4'
       Members   = @(
           @{ Name='ZCode';   Dir="$env:USERPROFILE\.zcode\wallpaper";           Process='ZCode' },
           @{ Name='Codex';   Dir="$env:USERPROFILE\.codex\wallpaper";           Process='ChatGPT' },
           @{ Name='AutoClaw';Dir="$env:APPDATA\autoclaw\wallpaper";             Process='AutoClaw' },
           @{ Name='Doubao';  Dir="$env:USERPROFILE\.doubao\wallpaper";          Process='Doubao' }
       ) },
    @{ Canonical = Join-Path $hub 'wallpaper\dedup-b.mp4'
       Members   = @(
           @{ Name='WorkBuddy';  Dir="$env:USERPROFILE\.workbuddy\wallpaper";      Process='WorkBuddy' },
           @{ Name='TraeCN';     Dir="$env:USERPROFILE\.trae-cn\wallpaper";        Process='Trae CN' },
           @{ Name='TraeWorkCN'; Dir="$env:USERPROFILE\.trae-cn\wallpaper-solo";   Process='TRAE SOLO CN' }
       ) }
)

function Write-RefreshMarker([string]$dir) {
    # 新标记必须与现存标记不同才会被应用察觉；先写新再删旧，避免轮询间隙出现空位导致双重重载
    $rot = Join-Path $dir 'rotate'
    New-Item -ItemType Directory -Path $rot -Force | Out-Null
    $counter = 0
    $cf = Join-Path $dir '.marker-counter'
    try { $counter = [int](Get-Content $cf -Raw -ErrorAction Stop).Trim() } catch { $counter = 0 }
    $gif = [Convert]::FromBase64String('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')
    for ($try = 0; $try -lt 4; $try++) {
        $counter++
        $n = ($counter % 3) + 1
        $target = Join-Path $rot ("refresh-" + $n + ".gif")
        if (Test-Path $target) { continue }
        [IO.File]::WriteAllBytes($target, $gif)
        Set-Content -Path $cf -Value $counter -NoNewline
        Get-ChildItem $rot -Filter 'refresh-*.gif' | Where-Object { $_.Name -ne ("refresh-" + $n + ".gif") } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        return $n
    }
    return 0
}

foreach ($g in $groups) {
    $canon = $g.Canonical
    if (-not (Test-Path $canon)) { Write-Host "跳过：canonical 不存在 $canon"; continue }
    foreach ($m in $g.Members) {
        $wp = Join-Path $m.Dir 'wallpaper.mp4'
        $running = $null -ne (Get-Process -Name $m.Process -ErrorAction SilentlyContinue)
        if (-not (Test-Path $wp)) { Write-Host ("{0}: 无 wallpaper.mp4，跳过" -f $m.Name); continue }
        # 已是硬链接（同 inode）则无需处理
        $wpId = (Get-Item $wp).Target
        if ($wpId -and ($wpId -contains $canon)) { Write-Host ("{0}: 已是硬链接" -f $m.Name); continue }
        $old = "$wp.zwp-old"
        try {
            if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
            Move-Item $wp $old -Force -ErrorAction Stop
        } catch {
            Write-Host ("{0}: 文件被占用，本次跳过（应用关闭后重跑本脚本即可）" -f $m.Name)
            continue
        }
        try {
            New-Item -ItemType HardLink -Path $wp -Target $canon -ErrorAction Stop | Out-Null
        } catch {
            Move-Item $old $wp -Force -ErrorAction SilentlyContinue   # 回滚
            Write-Host ("{0}: 建硬链接失败，已回滚（{1}）" -f $m.Name, $_.Exception.Message)
            continue
        }
        try { Remove-Item $old -Force -ErrorAction SilentlyContinue } catch { Write-Host ("{0}: 旧文件暂不能删（应用占用中，句柄释放后可手动删）" -f $m.Name) }
        Write-Host ("{0}: 已替换为硬链接（canonical: {1}）" -f $m.Name, $canon)
        if ($running) {
            $n = Write-RefreshMarker $m.Dir
            if ($n -gt 0) { Write-Host ("{0}: 运行中，已写 refresh-{1} 标记热生效" -f $m.Name, $n) }
        }
    }
}
Write-Host "---- 迁移完成 ----"
