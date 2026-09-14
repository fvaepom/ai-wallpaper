# codex-launcher.ps1 - Codex desktop (loose copy) wallpaper launcher + CDP injection agent
#
# Codex desktop (OpenAI.Codex MSIX -> loose copy at CodexPatched) renders its UI on an
# app:// page. Serving wallpapers via wp:// protocol bridge is blocked by the newer
# Chromium media URL safety check, so this agent uses the proven Doubao approach:
#   1. Starts CodexPatched\app\ChatGPT.exe with a loopback-only DevTools port
#   2. Runs a loopback media server for the wallpaper file (Range supported)
#   3. Injects wallpaper layer + transparency CSS over CDP into app:// pages
#   4. Watches the wallpaper folder - changes apply live (no restart)
#   5. Exits automatically when Codex exits
#
# Wallpaper folder: %USERPROFILE%\.codex\wallpaper\
# NOTE: file is ASCII-only on purpose (PS 5.1 no-BOM safe). Chinese strings are
#       stored base64-encoded and decoded at runtime.

param([int]$Port = 0)
$ErrorActionPreference = 'Stop'

$Hub           = Join-Path $env:USERPROFILE '.ai-wallpaper'
$WallDir       = Join-Path $env:USERPROFILE '.codex\wallpaper'
$LogFile       = Join-Path $WallDir 'agent.log'
$ExeCandidates = @(
    'C:\Users\FVAEP\CodexPatched\app\ChatGPT.exe',
    'C:\Users\FVAEP\CodexPatched\app\ChatGPT.exe')
$AllowedPorts  = @(19330, 19331, 19332, 19333, 19334)
# Codex 的媒体加载器有 URL 安全检查（http://127.0.0.1 与 wp:// 均被拒，实测 2026-09-15），
# 仅 app://fs/@fs/<路径> 直通可用，且只对图片可靠（视频流挂起）→ Codex 暂只支持图片壁纸
$Exts          = @('gif', 'webp', 'png', 'jpg', 'jpeg')
$Cfg           = @{ videoOpacity = 0.9; imageOpacity = 0.9; darkOverlay = 0.18 }

$ZHTitle  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6LGG5YyF5aOB57q4'))
$ZHBody   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5qOA5rWL5Yiw6LGG5YyF5q2j5Zyo6L+Q6KGM77yM5L2G5pya5Yqg6L295aOB57q444CCDuW9seW9seW9seW9seW9sQ=='))
$ZHLogW   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5b2T5YmN5aOB57q4OiA='))
$ZHLogNo  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pyq5om+5Yiw5aOB57q45paH5Lu277yM5pi+56S65YWc5bqV5p6B5YWJ5riQ5Y+Y'))
$ZHWatch  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5q2j5Zyo55uR6KeG5aOB57q455uu5b2VOiA='))
$ZHInject = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5rOo5YWl5aOB57q45bGCIC0+IA=='))
$ZHChange = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5aOB57q455uu5b2V5Y+Y5YyW77yM6YeN5paw5rOo5YWlOiA='))
$ZHClear  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('KOW3sua4heepuu+8iOWbnuWIsOaegeWFieWFnOW6lSk='))
$ZHExit   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6LGG5YyF5bey6YCA5Ye677yI6LCD6K+V56uv5Y+j5aSx6IGU77yJ77yM5Luj55CG6YCA5Ye6'))
$ZHNoExe  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pyq5om+5Yiw6LGG5YyF5a6J6KOF55uu5b2V77yIQ2hhdEdQVC5leGXvvInvvIzpo77lvYXjgII='))
$Mark     = [string][char]0x2726

function Log([string]$msg) {
    try {
        if (-not (Test-Path $WallDir)) { New-Item -ItemType Directory -Path $WallDir -Force | Out-Null }
        $line = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') + ' ' + $msg
        $cur = ''
        if (Test-Path $LogFile) { $cur = Get-Content -LiteralPath $LogFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue }
        $tail = ($cur + $line + "`n") -split "`n" | Select-Object -Last 500
        [IO.File]::WriteAllText($LogFile, ($tail -join "`n"), [Text.UTF8Encoding]::new($false))
    } catch {}
}

function Test-DebugPort([int]$p) {
    if ($AllowedPorts -notcontains $p) { return $false }
    try {
        $null = Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/version" -f $p) -TimeoutSec 2
        return $true
    } catch { return $false }
}

function Find-Wallpaper {
    foreach ($ext in $Exts) {
        $p = Join-Path $WallDir ('wallpaper.' + $ext)
        if (Test-Path $p -PathType Leaf) {
            $len = (Get-Item $p).Length
            if ($len -gt 0) { return @{ file = $p; ext = $ext } }
        }
    }
    return $null
}

function Get-CurrentWallpaper {
    $rot = Join-Path $WallDir 'rotate'
    $r1 = Get-ChildItem $rot -Filter 'rotate-1.*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($r1) {
        $all = Get-ChildItem $rot -Filter 'rotate-*.*' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match '^rotate-\d+$' } |
            Sort-Object { [int]($_.BaseName -replace 'rotate-', '') }
        if ($all.Count -gt 0) {
            $interval = 15
            $iv = Get-ChildItem $rot -Filter 'interval-*.gif' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($iv) { try { $interval = [Math]::Max(1, [int]($iv.BaseName -replace 'interval-', '')) } catch {} }
            $slot = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / ($interval * 60)) % $all.Count
            $f = $all[$slot]
            return @{ file = $f.FullName; ext = $f.Extension.TrimStart('.') }
        }
    }
    return Find-Wallpaper
}

# ---------- CSS + bootstrap injected into the app:// page ----------
$LAYER_CSS = @'
html,body{background:transparent!important;}
#root{background:transparent!important;}
:root,:host,.electron-light{
--color-background-surface:rgba(255,255,255,var(--ocwp-ui-alpha,.62))!important;
--color-background-surface-under:rgba(250,250,250,var(--ocwp-ui-alpha,.5))!important;
--color-surface:rgba(255,255,255,var(--ocwp-ui-alpha,.62))!important;
--color-surface-secondary:rgba(245,245,245,var(--ocwp-ui-alpha,.55))!important;
--color-surface-tertiary:rgba(250,250,250,var(--ocwp-ui-alpha,.78))!important;
--main-surface-secondary:rgba(245,245,245,var(--ocwp-ui-alpha,.5))!important;
--app-shell-panel-background:rgba(250,250,250,var(--ocwp-ui-alpha,.55))!important;
--color-background-application-menu:rgba(250,250,250,.94)!important;
--color-background-composer-primary:rgba(255,255,255,.75)!important;
--color-background-composer-action-bar:rgba(255,255,255,.8)!important;
--color-token-bg-primary:rgba(255,255,255,var(--ocwp-ui-alpha,.6))!important;
--color-token-bg-secondary:rgba(245,245,245,var(--ocwp-ui-alpha,.55))!important;
--color-token-side-bar-background:rgba(250,250,250,var(--ocwp-ui-alpha,.55))!important;
--color-token-main-surface-primary:rgba(255,255,255,var(--ocwp-ui-alpha,.62))!important;}
.electron-dark{
--color-background-surface:rgba(23,23,23,var(--ocwp-ui-alpha,.6))!important;
--color-background-surface-under:rgba(16,16,16,var(--ocwp-ui-alpha,.52))!important;
--color-surface:rgba(23,23,23,var(--ocwp-ui-alpha,.6))!important;
--color-surface-secondary:rgba(32,32,32,var(--ocwp-ui-alpha,.55))!important;
--color-surface-tertiary:rgba(28,28,28,var(--ocwp-ui-alpha,.78))!important;
--main-surface-secondary:rgba(32,32,32,var(--ocwp-ui-alpha,.5))!important;
--app-shell-panel-background:rgba(28,28,28,var(--ocwp-ui-alpha,.55))!important;
--color-background-application-menu:rgba(38,38,38,.94)!important;
--color-background-composer-primary:rgba(30,30,30,.75)!important;
--color-background-composer-action-bar:rgba(30,30,30,.8)!important;
--color-token-bg-primary:rgba(23,23,23,var(--ocwp-ui-alpha,.6))!important;
--color-token-bg-secondary:rgba(32,32,32,var(--ocwp-ui-alpha,.55))!important;
--color-token-side-bar-background:rgba(28,28,28,var(--ocwp-ui-alpha,.55))!important;
--color-token-main-surface-primary:rgba(23,23,23,var(--ocwp-ui-alpha,.62))!important;}
[data-codex-window-type=browser]:not(.electron-light):not(.electron-dark){
--color-background-surface:rgba(255,255,255,var(--ocwp-ui-alpha,.62))!important;
--color-background-application-menu:rgba(250,250,250,.94)!important;}
#oc-wallpaper{position:fixed;inset:0;z-index:-1;overflow:hidden;pointer-events:none;
background:linear-gradient(160deg,#0b0f1a 0%,#101828 50%,#0b1120 100%);}
#oc-wallpaper img,#oc-wallpaper video{width:100%;height:100%;object-fit:cover;display:block;}
#oc-wallpaper .oc-wp-shade{position:absolute;inset:0;}
#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{
content:"";position:absolute;width:90vmax;height:90vmax;border-radius:50%;will-change:transform;}
#oc-wallpaper.aurora::before{
background:radial-gradient(circle at 50% 50%,rgba(59,130,246,.6) 0%,rgba(29,78,216,.32) 32%,transparent 68%);
top:-30%;left:-20%;animation:ocwp-a 26s ease-in-out infinite alternate;}
#oc-wallpaper.aurora::after{
background:radial-gradient(circle at 50% 50%,rgba(168,85,247,.55) 0%,rgba(109,40,217,.3) 34%,transparent 68%);
bottom:-35%;right:-25%;animation:ocwp-b 32s ease-in-out infinite alternate;}
@keyframes ocwp-a{0%{transform:translate(0,0) scale(1)}50%{transform:translate(12vw,8vh) scale(1.15) rotate(20deg)}100%{transform:translate(4vw,16vh) scale(.95) rotate(-10deg)}}
@keyframes ocwp-b{0%{transform:translate(0,0) scale(1)}50%{transform:translate(-10vw,-10vh) scale(1.2)}100%{transform:translate(-4vw,-4vh) scale(.9)}}
@media (prefers-reduced-motion: reduce){#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{animation:none;}}
'@

function Esc-Json([string]$s) {
    $s = $s -replace '\\', '\\'
    $s = $s -replace '"', '\"'
    $s = $s -replace "`r", '\r'
    $s = $s -replace "`n", '\n'
    $s = $s -replace "`t", '\t'
    return $s
}

$BOOTSTRAP_TEMPLATE = @'
(function(){
window.__ocwpAgent=true;
if(!window.__ocwpApply){
window.__ocwpApply=function(url,isVideo,opacity,shade){
var l=document.getElementById("oc-wallpaper");
if(!l)return"no-layer";
l.className="";
while(l.firstChild)l.removeChild(l.firstChild);
var el;
if(isVideo){el=document.createElement("video");el.autoplay=true;el.loop=true;el.muted=true;el.playsInline=true;el.play().catch(function(){});}
else{el=document.createElement("img");}
el.style.opacity=opacity;
el.src=url;
l.appendChild(el);
var sh=document.createElement("div");sh.className="oc-wp-shade";sh.style.background="rgba(0,0,0,"+shade+")";l.appendChild(sh);
return"applied";};}
var s=document.getElementById("ocwp-style");
if(!s){s=document.createElement("style");s.id="ocwp-style";document.documentElement.appendChild(s);}
s.textContent="__OCWP_CSS__";
var c=document.getElementById("ocwp-custom-style");
if(!c){c=document.createElement("style");c.id="ocwp-custom-style";document.documentElement.appendChild(c);}
c.textContent="__OCWP_CUSTOM_CSS__";
var l=document.getElementById("oc-wallpaper");
if(!l){l=document.createElement("div");l.id="oc-wallpaper";(document.body||document.documentElement).appendChild(l);
try{document.title+=" __MARK__";}catch(e){}}
return"ready";})()
'@
$BOOTSTRAP_TEMPLATE = $BOOTSTRAP_TEMPLATE.Replace('__MARK__', $Mark)

# ---------- CDP over ClientWebSocket (loopback whitelist only) ----------
$script:CdpId = 1

function Send-CdpMessage([string]$wsUrl, [string]$method, [string]$paramsJson, [int]$timeoutSec) {
    $uri = $null
    try { $uri = [Uri]$wsUrl } catch { return $null }
    if ($uri.Scheme -ne 'ws' -or $uri.Host -ne '127.0.0.1' -or $AllowedPorts -notcontains $uri.Port) { return $null }
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        $ct = [System.Threading.CancellationToken]::None
        $null = $ws.ConnectAsync($uri, $ct)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            if ($sw.ElapsedMilliseconds -gt 5000) { return $null }
            Start-Sleep -Milliseconds 20
        }
        $id = $script:CdpId++
        $json = '{"id":' + $id + ',"method":"' + $method + '","params":' + $paramsJson + '}'
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $off = 0
        while ($off -lt $bytes.Length) {
            $n = [Math]::Min(65536, $bytes.Length - $off)
            $seg = New-Object System.ArraySegment[byte] -ArgumentList $bytes, $off, $n
            $end = ($off + $n) -ge $bytes.Length
            $null = $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $end, $ct).GetAwaiter().GetResult()
            $off += $n
        }
        $deadline = [Diagnostics.Stopwatch]::StartNew()
        $buf = New-Object byte[] 65536
        $ms = New-Object IO.MemoryStream
        while ($true) {
            if ($deadline.ElapsedMilliseconds -gt ($timeoutSec * 1000)) { return $null }
            $segIn = New-Object System.ArraySegment[byte] -ArgumentList (, $buf)
            $res = $ws.ReceiveAsync($segIn, $ct)
            if (-not $res.Wait(2000)) { return $null }
            $r = $res.Result
            if ($r.Count -gt 0) { $ms.Write($buf, 0, $r.Count) }
            if ($r.EndOfMessage) {
                $txt = [Text.Encoding]::UTF8.GetString($ms.ToArray())
                $ms.SetLength(0)
                if (-not $txt) { continue }
                try { $msg = $txt | ConvertFrom-Json } catch { continue }
                if ($msg.id -eq $id) { return $msg.result.result.value }
            }
        }
    } catch { return $null }
    finally { try { $ws.Dispose() } catch {} }
}

function Send-CdpEval([string]$wsUrl, [string]$expression, [int]$timeoutSec = 30, [switch]$AwaitPromise) {
    $params = '{"expression":"' + (Esc-Json $expression) + '","returnByValue":true'
    if ($AwaitPromise) { $params += ',"awaitPromise":true' }
    $params += '}'
    return Send-CdpMessage $wsUrl 'Runtime.evaluate' $params $timeoutSec
}

function Get-CdpTargets([int]$p) {
    if ($AllowedPorts -notcontains $p) { return $null }
    try { return Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/json/list" -f $p) -TimeoutSec 3 } catch { return $null }
}

# ---------- loopback media server ----------
$MediaServerScript = @'
$mimes = @{ mp4 = 'video/mp4'; webm = 'video/webm'; gif = 'image/gif'; webp = 'image/webp'; png = 'image/png'; jpg = 'image/jpeg'; jpeg = 'image/jpeg' }
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$state.Port = ([int]$listener.LocalEndpoint.Port)
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
        $path = [string]$state.File
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $hb = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 9`r`nConnection: close`r`n`r`nnot found")
            $st.Write($hb, 0, $hb.Length)
            continue
        }
        $fi = Get-Item -LiteralPath $path
        $ext = $fi.Extension.TrimStart('.').ToLower()
        $mime = 'application/octet-stream'
        if ($mimes.ContainsKey($ext)) { $mime = $mimes[$ext] }
        $len = $fi.Length
        $end = $len - 1
        if ($rEnd -ge 0 -and $rEnd -lt $end) { $end = $rEnd }
        $partial = ($rStart -gt 0 -or ($rEnd -ge 0 -and $rEnd -lt ($len - 1)))
        $status = '200 OK'; if ($partial) { $status = '206 Partial Content' }
        $cl = $end - $rStart + 1
        $hs = "HTTP/1.1 $status`r`nContent-Type: $mime`r`nContent-Length: $cl`r`nAccept-Ranges: bytes`r`nAccess-Control-Allow-Origin: *`r`nCache-Control: no-store`r`nConnection: close`r`n"
        if ($partial) { $hs += "Content-Range: bytes $rStart-$end/$len`r`n" }
        $hs += "`r`n"
        $hb = [System.Text.Encoding]::ASCII.GetBytes($hs)
        $st.Write($hb, 0, $hb.Length)
        if (-not $headOnly) {
            $fs = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
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
'@

function Send-Wallpaper([string]$wsUrl, $wp, [string]$customCss) {
    # setBypassCSP 会触发页面自动重载：必须先开旁路等重载完成，再注入（否则注入结果被重载清掉）
    if (-not $script:Bypassed[$wsUrl]) {
        $null = Send-CdpMessage $wsUrl 'Page.setBypassCSP' '{"enabled":true}' 10
        $script:Bypassed[$wsUrl] = $true
        Start-Sleep -Seconds 2
    }
    $boot = $BOOTSTRAP_TEMPLATE.Replace('__OCWP_CSS__', (Esc-Json $LAYER_CSS)).Replace('__OCWP_CUSTOM_CSS__', (Esc-Json $customCss))
    $r1 = Send-CdpEval $wsUrl $boot 60
    if ($r1 -ne 'ready') { return 'bootstrap-failed: ' + $r1 }
    # 壁纸经主进程 app://fs/@fs 文件直通供给（同 scheme，不触发媒体 URL 安全检查；http://127.0.0.1 会被拒）
    $fsUrl = 'app://fs/@fs/' + ($wp.file -replace '\\', '/')
    $r2 = Send-CdpEval $wsUrl ('window.__ocwpApply("' + $fsUrl + '",false,' + $Cfg.imageOpacity + ',' + $Cfg.darkOverlay + ')') 30
    if ($r2 -ne 'applied') { return 'apply-failed: ' + $r2 }
    $probe = 'new Promise(function(res){setTimeout(function(){var l=document.getElementById("oc-wallpaper");if(!l){res("no-layer");return}var m=l.querySelector("img");if(!m){res("no-media");return}res(m.complete&&m.naturalWidth>0?("ok "+m.naturalWidth+"x"+m.naturalHeight):"loading")},1500)})'
    $health = Send-CdpEval $wsUrl $probe 15 -AwaitPromise
    return ('apply: ' + $r2 + ' (' + $wp.ext + ', app://fs, health=' + $health + ')')
}

# ---------- 0. single instance ----------
$script:Bypassed = @{}
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\ai-wallpaper-codex')
if (-not $script:Mutex.WaitOne(0)) { Log 'another launcher instance already running, exit'; exit 0 }

# ---------- 1. resolve Codex exe / debug port ----------
if (-not (Test-Path $WallDir)) { New-Item -ItemType Directory -Path $WallDir -Force | Out-Null }

$exe = $null
foreach ($c in $ExeCandidates) { if (Test-Path $c) { $exe = $c; break } }
if (-not $exe) { Log $ZHNoExe; exit 1 }

$appUp = $false
try { $appUp = ($null -ne (Get-Process -Name ChatGPT -ErrorAction SilentlyContinue)) } catch {}

$port = 0
if ($appUp) {
    foreach ($p in $AllowedPorts) { if (Test-DebugPort $p) { $port = $p; break } }
    if ($port -eq 0) {
        Log 'Codex running without debug port - restarting it'
        Stop-Process -Name ChatGPT -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $appUp = $false
    } else {
        Log ('reusing existing debug port ' + $port)
    }
}
if ($port -eq 0) {
    foreach ($p in $AllowedPorts) {
        $l = $null
        try { $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p); $l.Start() } catch { continue }
        $l.Stop()
        $port = $p
        break
    }
    if ($port -eq 0) { Log 'no free debug port'; exit 1 }
    Log ('starting Codex with debug port ' + $port + ': ' + $exe)
    Start-Process -FilePath $exe -ArgumentList ("-remote-debugging-port={0}" -f $port) -WorkingDirectory (Split-Path $exe) | Out-Null
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 1500
        if (Test-DebugPort $port) { $ready = $true; break }
    }
    if (-not $ready) { Log 'debug port did not come up'; exit 1 }
}
Log ('connected to CDP port ' + $port)

# ---------- 2. injection agent loop ----------
$customCss = ''
if (Test-Path (Join-Path $WallDir 'custom.css')) { $customCss = Get-Content (Join-Path $WallDir 'custom.css') -Raw -Encoding UTF8 }
$wp = Get-CurrentWallpaper
if ($wp) { Log ($ZHLogW + $wp.file) } else { Log $ZHLogNo }
Log ($ZHWatch + $WallDir)

$misses = 0
$lastSig = ''
while ($true) {
    $targets = Get-CdpTargets $port
    if (-not $targets) {
        $misses++
        if ($misses -ge 5) { Log $ZHExit; exit 0 }
        Start-Sleep -Seconds 2
        continue
    }
    $misses = 0

    $wp2 = Get-CurrentWallpaper
    $css2 = ''
    if (Test-Path (Join-Path $WallDir 'custom.css')) { $css2 = Get-Content (Join-Path $WallDir 'custom.css') -Raw -Encoding UTF8 }
    $sig = ''
    if ($wp2) { $sig = $wp2.file + '|' + (Get-Item $wp2.file).LastWriteTimeUtc.Ticks + '|' + (Get-Item $wp2.file).Length }
    $sig = $sig + '|css:' + ($css2.GetHashCode())
    $changed = $false
    if ($sig -ne $lastSig) {
        $first = ($lastSig -eq '')
        $lastSig = $sig
        $wp = $wp2; $customCss = $css2
        if (-not $first) {
            $changed = $true
            if ($wp) { Log ($ZHChange + $wp.file) } else { Log ($ZHChange + $ZHClear) }
        }
    }

    foreach ($t in $targets) {
        if ($t.type -ne 'page') { continue }
        if ($t.url -notmatch '^app://') { continue }
        if (-not $changed) {
            # asar 里可能还驻留旧版注入脚本（会先建一个 aurora 层）→ 用代理专属标记判断是否已由本代理注入
            $guard = Send-CdpEval $t.webSocketDebuggerUrl 'window.__ocwpAgent===true' 8
            if ($guard -eq $true) { continue }
        }
        Log ($ZHInject + $t.url)
        try {
            if ($wp) { Log (Send-Wallpaper $t.webSocketDebuggerUrl $wp $customCss) }
            else {
                $boot = $BOOTSTRAP_TEMPLATE.Replace('__OCWP_CSS__', (Esc-Json $LAYER_CSS)).Replace('__OCWP_CUSTOM_CSS__', (Esc-Json $customCss))
                $null = Send-CdpEval $t.webSocketDebuggerUrl $boot 60
                $null = Send-CdpEval $t.webSocketDebuggerUrl 'var l=document.getElementById("oc-wallpaper");l.innerHTML="";l.className="aurora";"aurora-on"' 30
            }
        } catch { Log ('inject error: ' + $_.Exception.Message) }
    }
    Start-Sleep -Milliseconds 2000
}
