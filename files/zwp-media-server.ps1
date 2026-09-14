# zwp-media-server.ps1 - 壁纸媒体服务（本机回环 HTTP，固定端口 19399）
#
# 页面侧注入脚本（zwp-wallpaper-marvis.js / zwp-wallpaper-dsh.js）从 127.0.0.1 回环
# 加载壁纸 / 轮换标记 / custom.css——127.0.0.1 是 Chromium 认定的安全来源，适用于
# 页面本身无 file:// 能力或来源受限的应用（Marvis 离线页、DSH Desktop 回环前端）。
# 路由：/ 与 /marvis/... → %USERPROFILE%\.marvis\wallpaper（根路径兼容已部署的
# Marvis 脚本）；/dsh/... → %USERPROFILE%\.dsh\wallpaper。各根支持 /<根>/__ping
# 供 apply-patch 探测该应用根是否可用（旧版服务只认根 __ping，借此识别并热重启）。
# 只服务映射目录下的文件（拒绝 .. 与子目录穿越），支持 Range（视频可拖动）。
# 单实例：端口被占（已在运行）则直接退出；由计划任务「AI壁纸媒体服务」登录自启，apply-patch 也会拉起。

$ErrorActionPreference = 'SilentlyContinue'
$Port = 19399
$Roots = @{
    marvis = Join-Path $env:USERPROFILE '.marvis\wallpaper'
    dsh    = Join-Path $env:USERPROFILE '.dsh\wallpaper'
}
$DefaultRoot = 'marvis'   # 无前缀的历史路径（/wallpaper.*、/rotate/...）归 Marvis
$LogDir = $Roots[$DefaultRoot]
$Log = Join-Path $LogDir 'media-server.log'

function Log([string]$m) {
    try {
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $m
        $tail = @((Get-Content -LiteralPath $Log -ErrorAction SilentlyContinue) + $line) | Select-Object -Last 200
        [IO.File]::WriteAllLines($Log, $tail)
    } catch {}
}

# 已在运行？（端口能通即认为在运行）
try {
    $null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/__ping' -f $Port) -TimeoutSec 2
    exit 0
} catch {}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
foreach ($root in $Roots.Values) {
    if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
}
Log 'media server starting'

$mimes = @{ mp4 = 'video/mp4'; webm = 'video/webm'; gif = 'image/gif'; webp = 'image/webp'; png = 'image/png'; jpg = 'image/jpeg'; jpeg = 'image/jpeg'; css = 'text/css' }

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$ok = $false
try { $listener.Start(); $ok = $true } catch { Log ('listen fail: ' + $_.Exception.Message) }
if (-not $ok) { exit 1 }
Log ('listening on 127.0.0.1:' + $Port)

while ($true) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
        $client.NoDelay = $true
        $st = $client.GetStream()
        $st.ReadTimeout = 8000
        $buf = New-Object byte[] 8192
        $sb = New-Object System.Text.StringBuilder
        while ($true) {
            $n = $st.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buf, 0, $n))
            if ($sb.ToString().IndexOf("`r`n`r`n") -ge 0 -or $sb.Length -gt 16384) { break }
        }
        $req = $sb.ToString()
        if (-not $req) { continue }
        $headOnly = (($req -split "`r`n")[0] -match '^HEAD')
        $rStart = [int64]0; $rEnd = [int64]-1
        if ($req -match '(?mi)^Range:\s*bytes=(\d*)-(\d*)\s*\r?$') {
            if ($matches[1] -ne '') { $rStart = [int64]$matches[1] }
            if ($matches[2] -ne '') { $rEnd = [int64]$matches[2] }
        }
        # 请求行：GET /name、/rotate/name（历史根=Marvis）或 /<app>/name、/<app>/rotate/name
        # （不能用 [Uri].AbsolutePath——相对路径会得到空串）
        $path = '/'
        if ($req -match '^[A-Z]+\s+(\S+)') { $path = $matches[1] }
        $path = [Uri]::UnescapeDataString($path)
        $rel = $path.TrimStart('/')
        $segs = @($rel -split '/') | Where-Object { $_ -ne '' }
        if ($rel -like '*..*') {
            $hb = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 403 Forbidden`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
            $st.Write($hb, 0, $hb.Length); continue
        }
        # 按首段选根：/dsh|marvis/... 走对应虚拟根，其余落到默认根（兼容无前缀的历史请求）
        $rootName = $DefaultRoot
        if ($segs.Count -gt 0 -and $Roots.ContainsKey($segs[0])) {
            $rootName = $segs[0]
            $segs = @($segs | Select-Object -Skip 1)
        }
        $rootDir = $Roots[$rootName]
        # 只允许根文件与一层子目录（rotate/xxx），拒绝更深层级
        if ($segs.Count -gt 2) {
            $hb = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 403 Forbidden`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
            $st.Write($hb, 0, $hb.Length); continue
        }
        if ($segs.Count -eq 0) { $rel = '__ping' } else { $rel = $segs -join '/' }
        if ($rel -eq '__ping') {
            $hb = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`nok")
            $st.Write($hb, 0, $hb.Length); continue
        }
        $file = Join-Path $rootDir ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            $hb = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
            $st.Write($hb, 0, $hb.Length); continue
        }
        $fi = Get-Item -LiteralPath $file
        $ext = $fi.Extension.TrimStart('.').ToLower()
        $mime = 'application/octet-stream'
        if ($mimes.ContainsKey($ext)) { $mime = $mimes[$ext] }
        $len = $fi.Length
        $end = $len - 1
        if ($rEnd -ge 0 -and $rEnd -lt $end) { $end = $rEnd }
        $partial = ($rStart -gt 0 -or ($rEnd -ge 0 -and $rEnd -lt ($len - 1)))
        $status = '200 OK'; if ($partial) { $status = '206 Partial Content' }
        $cl = $end - $rStart + 1
        $hs = "HTTP/1.1 $status`r`nContent-Type: $mime`r`nContent-Length: $cl`r`nAccept-Ranges: bytes`r`nCache-Control: no-store`r`nConnection: close`r`n"
        if ($partial) { $hs += "Content-Range: bytes $rStart-$end/$len`r`n" }
        $hs += "`r`n"
        $hb = [System.Text.Encoding]::ASCII.GetBytes($hs)
        $st.Write($hb, 0, $hb.Length)
        if (-not $headOnly) {
            # FileShare ReadWrite：选择器覆写文件进行中也不崩
            $fs = New-Object System.IO.FileStream($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $null = $fs.Seek($rStart, [System.IO.SeekOrigin]::Begin)
                $chunk = New-Object byte[] (1024 * 1024)
                $pos = $rStart
                while ($pos -le $end) {
                    $want = [int][Math]::Min($chunk.Length, $end - $pos + 1)
                    $read = 0
                    while ($read -lt $want) {
                        $r = $fs.Read($chunk, $read, $want - $read)
                        if ($r -le 0) { break }
                        $read += $r
                    }
                    if ($read -le 0) { break }
                    $st.Write($chunk, 0, $read)
                    $pos += $read
                }
            } finally { $fs.Close() }
        }
    } catch {} finally { if ($client) { try { $client.Close() } catch {} } }
}
