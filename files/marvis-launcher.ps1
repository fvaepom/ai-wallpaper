# marvis-launcher.ps1 - Marvis desktop wallpaper launcher + CDP injection agent
#
# Marvis (Tencent, "C:\Program Files\Tencent\Marvis") is a Qt5 + CEF app whose main
# window loads https://yyb-ai-launcher-offline.qq.com/index.html (served from the
# local marvis-offline-page dir by a CEF interceptor). asar patching does not apply.
# This script:
#   1. Starts Marvis.exe with a loopback-only DevTools port (127.0.0.1, whitelisted
#      range). Marvis.exe manifest is requireAdministrator, so launching goes through
#      -Verb RunAs (one UAC prompt - same as starting Marvis the normal way).
#   2. Injects a wallpaper layer + transparency CSS into the launcher page over CDP
#      (the agent itself stays non-elevated; loopback TCP crosses the boundary fine).
#   3. Watches the wallpaper folder - changing the wallpaper applies live (no restart)
#   4. Exits automatically when Marvis exits
#
# Wallpaper folder: %USERPROFILE%\.marvis\wallpaper\
#   wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg  (priority order)
#   custom.css  (optional extra styles)
# Managed by the "AI Wallpaper Picker"; no need to touch this file manually.
#
# NOTE: Chinese UI strings are stored base64-encoded and decoded at runtime; the file
#       itself carries a UTF-8 BOM (required by PS 5.1 to read the Chinese comments).

param([int]$Port = 0, [switch]$Restart)
$ErrorActionPreference = 'Stop'

$Hub          = Join-Path $env:USERPROFILE '.ai-wallpaper'
$WallDir      = Join-Path $env:USERPROFILE '.marvis\wallpaper'
$LogFile      = Join-Path $WallDir 'agent.log'
$AppRoot      = 'C:\Program Files\Tencent\Marvis\Application'
$AllowedPorts = @(19232, 19233, 19234, 19235, 19236)
$Exts         = @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg', 'jpeg')
$VideoMime    = @{ mp4 = 'video/mp4'; webm = 'video/webm' }
$ImageMime    = @{ gif = 'image/gif'; webp = 'image/webp'; png = 'image/png'; jpg = 'image/jpeg'; jpeg = 'image/jpeg' }
$Cfg          = @{ videoOpacity = 0.9; imageOpacity = 0.9; darkOverlay = 0.18 }

# base64(UTF-8) Chinese strings (decoded once, kept ASCII-safe in this file)
$ZHTitle  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5aOB57q46K6+572u'))
$ZHBody   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('TWFydmlzIOato+WcqOi/kOihjO+8jOS9huacrOasoeacquW4puWjgee6uOiwg+ivleerr+WPo+OAgumcgOimgemHjeWQr+S4gOasoSBNYXJ2aXMg5omN6IO95Yqg6L295aOB57q477yI5Lya5by55Ye6IFVBQyDnoa7orqTvvInjgIIKCueOsOWcqOmHjeWQr+WQl++8nw=='))
$ZHLogW   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5b2T5YmN5aOB57q4OiA='))
$ZHLogNo  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pyq5om+5Yiw5aOB57q45paH5Lu277yM5LuF5rOo5YWl5p6B5YWJ6IOM5pmv'))
$ZHWatch  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5q2j5Zyo55uR6KeG5aOB57q455uu5b2VOiA='))
$ZHInject = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5rOo5YWl5aOB57q45bGCIC0+IA=='))
$ZHChange = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5aOB57q45bey5Y+Y5YyW77yM6YeN5paw5rOo5YWlOiA='))
$ZHClear  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('77yI5riF6Zmk77yM5oGi5aSN5p6B5YWJ6IOM5pmv77yJ'))
$ZHExit   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('TWFydmlzIOW3sumAgOWHuu+8iOi/nue7reaOoua1i+Wksei0pe+8ie+8jOS7o+eQhumAgOWHug=='))
$ZHConn   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5bey6L+e5o6lIE1hcnZpcyDosIPor5Xnq6/lj6Mg'))
$ZHNoExe  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5pyq5om+5YiwIE1hcnZpcyDkuLvnqIvluo/vvIhNYXJ2aXMuZXhl77yJ77yM6YCA5Ye6'))
$ZHUacFail = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('VUFDIOaOiOadg+iiq+WPlua2iOaIluWksei0pe+8jOaXoOazlee7p+e7rQ=='))
$ZHRestart = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5q2j5Zyo5o+Q5p2D6YeN5ZCvIE1hcnZpc+KApg=='))
$ZHNoPort = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6LCD6K+V56uv5Y+j5pyq6IO95bu656uL77yI5q2k54mI5pys5Y+v6IO95LiN5pSv5oyB6K+l5byA5YWz77yJ77yM5aOB57q45LiN5Y+v55So77ybTWFydmlzIOacrOS9k+S4jeWPl+W9seWTjQ=='))
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

function Find-MarvisExe {
    # Marvis installs one dir per version (e.g. Application\1.60.2500.198\Marvis.exe);
    # pick the highest version so the launcher survives silent updates.
    $best = $null; $bestVer = $null
    if (Test-Path $AppRoot) {
        foreach ($d in (Get-ChildItem $AppRoot -Directory -ErrorAction SilentlyContinue)) {
            $exe = Join-Path $d.FullName 'Marvis.exe'
            if (-not (Test-Path $exe)) { continue }
            $v = $null
            try { $v = [version]$d.Name } catch { continue }
            if ($null -eq $bestVer -or $v -gt $bestVer) { $bestVer = $v; $best = $exe }
        }
    }
    if ($best) { return $best }
    # registry fallback (uninstall entry DisplayIcon points at Uninstall.exe)
    try {
        $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Marvis' -ErrorAction Stop
        if ($k.DisplayIcon) {
            $exe = Join-Path (Split-Path ($k.DisplayIcon -replace ',\d*$','')) 'Marvis.exe'
            if (Test-Path $exe) { return $exe }
        }
    } catch {}
    return $null
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
    # 轮换模式：rotate\rotate-1.* 存在即启用，interval-N.gif 指示间隔（分钟，缺省 15）
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

# ---------- CSS + bootstrap script injected into the Marvis page ----------
# Marvis offline-page is a light-themed React app (CSS-module hashed classes change per
# build; [class*=...] attribute matching keeps working across versions). v1 scope:
# transparent root + known white surfaces get an alpha; refine later via live CDP.
$LAYER_CSS = @'
html,body{background:transparent!important;}
#root,#app,#wrapper{background:transparent!important;}
:root{--default-bg-color:rgba(247,247,247,.55)!important;}
#mvwp-wallpaper{position:fixed;inset:0;z-index:-1;overflow:hidden;pointer-events:none;
background:radial-gradient(55% 70% at 62% 38%,rgba(14,165,233,.22) 0%,transparent 70%),linear-gradient(160deg,#0b0f1a 0%,#101828 50%,#0b1120 100%);}
#mvwp-wallpaper img,#mvwp-wallpaper video{width:100%;height:100%;object-fit:cover;display:block;}
#mvwp-wallpaper .mvwp-shade{position:absolute;inset:0;}
#mvwp-wallpaper.aurora::before,#mvwp-wallpaper.aurora::after{
content:"";position:absolute;width:90vmax;height:90vmax;border-radius:50%;will-change:transform;}
#mvwp-wallpaper.aurora::before{
background:radial-gradient(circle at 50% 50%,rgba(59,130,246,.6) 0%,rgba(29,78,216,.32) 32%,transparent 68%);
top:-30%;left:-20%;animation:mvwp-a 26s ease-in-out infinite alternate;}
#mvwp-wallpaper.aurora::after{
background:radial-gradient(circle at 50% 50%,rgba(168,85,247,.55) 0%,rgba(109,40,217,.3) 34%,transparent 68%);
bottom:-35%;right:-25%;animation:mvwp-b 32s ease-in-out infinite alternate;}
@keyframes mvwp-a{0%{transform:translate(0,0) scale(1)}50%{transform:translate(12vw,8vh) scale(1.15) rotate(20deg)}100%{transform:translate(4vw,16vh) scale(.95) rotate(-10deg)}}
@keyframes mvwp-b{0%{transform:translate(0,0) scale(1)}50%{transform:translate(-10vw,-10vh) scale(1.2)}100%{transform:translate(-4vw,-4vh) scale(.9)}}
@media (prefers-reduced-motion: reduce){#mvwp-wallpaper.aurora::before,#mvwp-wallpaper.aurora::after{animation:none;}}
'@

# optional pass: soften known white panels (CSS-module names from the shipped build;
# harmless no-op when a class does not exist). Applied after the base layer so
# custom.css can still override everything.
$PANEL_CSS = @'
[class*="_inputBar_"]{background:rgba(255,255,255,.72)!important;}
[class*="_question_"]{background:rgba(251,251,251,.6)!important;}
[class*="_question_"]:hover{background:rgba(255,255,255,.78)!important;}
[class*="_header_1w6zc"]{background:rgba(255,255,255,.6)!important;}
[class*="_dropdown_"]{background:rgba(255,255,255,.94)!important;}
'@

function Esc-Json([string]$s) {
    $s = $s -replace '\\', '\\'   # regex pattern \\ = one backslash; replacement inserts two
    $s = $s -replace '"', '\"'
    $s = $s -replace "`r", '\r'
    $s = $s -replace "`n", '\n'
    $s = $s -replace "`t", '\t'
    return $s
}

$BOOTSTRAP_TEMPLATE = @'
(function(){
if(!window.__mvwpApply){
window.__mvwpApply=function(url,isVideo,opacity,shade){
var l=document.getElementById("mvwp-wallpaper");
if(!l)return"no-layer";
l.className="";
while(l.firstChild)l.removeChild(l.firstChild);
var el;
if(isVideo){el=document.createElement("video");el.autoplay=true;el.loop=true;el.muted=true;el.playsInline=true;el.play().catch(function(){});}
else{el=document.createElement("img");}
el.style.opacity=opacity;
el.src=url;
l.appendChild(el);
var sh=document.createElement("div");sh.className="mvwp-shade";sh.style.background="rgba(0,0,0,"+shade+")";l.appendChild(sh);
return"applied";};}
var s=document.getElementById("mvwp-style");
if(!s){s=document.createElement("style");s.id="mvwp-style";document.documentElement.appendChild(s);}
s.textContent="__MVWP_CSS__";
var p=document.getElementById("mvwp-panel-style");
if(!p){p=document.createElement("style");p.id="mvwp-panel-style";document.documentElement.appendChild(p);}
p.textContent="__MVWP_PANEL_CSS__";
var c=document.getElementById("mvwp-custom-style");
if(!c){c=document.createElement("style");c.id="mvwp-custom-style";document.documentElement.appendChild(c);}
c.textContent="__MVWP_CUSTOM_CSS__";
var l=document.getElementById("mvwp-wallpaper");
if(!l){l=document.createElement("div");l.id="mvwp-wallpaper";(document.body||document.documentElement).appendChild(l);
try{document.title+=" __MARK__";}catch(e){}}
return"ready";})()
'@
$BOOTSTRAP_TEMPLATE = $BOOTSTRAP_TEMPLATE.Replace('__MARK__', $Mark)

# ---------- CDP over ClientWebSocket (loopback whitelist only) ----------
$script:CdpId = 1

function Send-CdpMessage([string]$wsUrl, [string]$method, [string]$paramsJson, [int]$timeoutSec) {
    # only loopback + whitelisted debug ports
    $uri = $null
    try { $uri = [Uri]$wsUrl } catch { return $null }
    if ($uri.Scheme -ne 'ws' -or $uri.Host -ne '127.0.0.1' -or $AllowedPorts -notcontains $uri.Port) { return $null }
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        $ct = [System.Threading.CancellationToken]::None
        # 注意：ConnectAsync 的返回 Task 不能赋给变量（PS 5.1 下赋值会让连接不启动），
        # 必须丢弃返回值，用状态轮询限时等待（豆包代理实测 2026-09-14）
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
        # receive until matching id
        $deadline = [Diagnostics.Stopwatch]::StartNew()
        $buf = New-Object byte[] 65536
        $ms = New-Object IO.MemoryStream
        while ($true) {
            if ($deadline.ElapsedMilliseconds -gt ($timeoutSec * 1000)) { return $null }
            $segIn = New-Object System.ArraySegment[byte] -ArgumentList (, $buf)
            $res = $ws.ReceiveAsync($segIn, $ct)
            if (-not $res.Wait(2000)) { Log 'cdp recv wait timeout'; return $null }
            $r = $res.Result
            if ($r.Count -gt 0) { $ms.Write($buf, 0, $r.Count) }
            if ($r.EndOfMessage) {
                $txt = [Text.Encoding]::UTF8.GetString($ms.ToArray())
                $ms.SetLength(0)
                if (-not $txt) { continue }
                try { $msg = $txt | ConvertFrom-Json } catch { Log ('cdp parse fail: ' + $txt.Substring(0, [Math]::Min(200, $txt.Length))); continue }
                if ($msg.id -eq $id) {
                    if ($null -eq $msg.result.result) { Log ('cdp resp: ' + $txt.Substring(0, [Math]::Min(200, $txt.Length))) }
                    elseif ($msg.result.result.subtype -eq 'error') { Log ('cdp jserr: ' + $msg.result.result.description) }
                    return $msg.result.result.value
                }
            }
        }
    } catch { Log ('cdp exc: ' + $_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage.Trim()); return $null }
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
# 壁纸经本机回环 HTTP 流式供给页面（视频可 Range 拖动），与豆包代理同款：
# 页面 CSP 不放行 file://（https 页面还会被 upgrade-insecure-requests 改写 http），
# 代理注入时先 Page.setBypassCSP，再走 127.0.0.1（Chromium 视为安全来源）流式加载。
# 用裸 TcpListener 而非 HttpListener：后者在非管理员下受 http.sys URLACL 限制。
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
        $hs = "HTTP/1.1 $status`r`nContent-Type: $mime`r`nContent-Length: $cl`r`nAccept-Ranges: bytes`r`nCache-Control: no-store`r`nConnection: close`r`n"
        if ($partial) { $hs += "Content-Range: bytes $rStart-$end/$len`r`n" }
        $hs += "`r`n"
        $hb = [System.Text.Encoding]::ASCII.GetBytes($hs)
        $st.Write($hb, 0, $hb.Length)
        if (-not $headOnly) {
            # FileShare ReadWrite：选择器覆写文件进行中也不崩，下个 Range 请求自然读到新内容
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
    $isVideo = $null -ne $VideoMime[$wp.ext]
    $boot = $BOOTSTRAP_TEMPLATE.Replace('__MVWP_CSS__', (Esc-Json $LAYER_CSS)).Replace('__MVWP_PANEL_CSS__', (Esc-Json $PANEL_CSS)).Replace('__MVWP_CUSTOM_CSS__', (Esc-Json $customCss))
    $r1 = Send-CdpEval $wsUrl $boot 60
    if ($r1 -ne 'ready') { return 'bootstrap-failed: ' + $r1 }
    # 页面 CSP（upgrade-insecure-requests）会把 http:// 媒体改写成 https → 经 CDP 关掉本页 CSP
    $null = Send-CdpMessage $wsUrl 'Page.setBypassCSP' '{"bypass":true}' 10
    if ($isVideo) { $op = $Cfg.videoOpacity } else { $op = $Cfg.imageOpacity }
    $boolLit = 'false'; if ($isVideo) { $boolLit = 'true' }
    $url = 'http://127.0.0.1:' + $script:Media.Port + '/wallpaper.' + $wp.ext
    $r2 = Send-CdpEval $wsUrl ('window.__mvwpApply("' + $url + '",' + $boolLit + ',' + $op + ',' + $Cfg.darkOverlay + ')') 30
    if ($r2 -ne 'applied') { return 'apply-failed: ' + $r2 }
    # 1.5 秒后问一次媒体健康度；加载失败会在日志可见，下一轮 sig 未变不会自动重试（可删 marker 触发）
    $probe = 'new Promise(function(res){setTimeout(function(){var l=document.getElementById("mvwp-wallpaper");if(!l){res("no-layer");return}var m=l.querySelector("video,img");if(!m){res("no-media");return}if(m.tagName==="VIDEO"){res(m.error?("video-error:"+m.error.code):(m.readyState>=1?"ok":"loading"))}else{res(m.complete?"ok":"loading")}},1500)})'
    $health = Send-CdpEval $wsUrl $probe 15 -AwaitPromise
    return ('apply: ' + $r2 + ' (' + $wp.ext + ', http stream, health=' + $health + ')')
}

# ---------- elevated restart helper ----------
# Marvis.exe 清单为 requireAdministrator：非提权的本代理结束不了它，也带不了参启动。
# 经 -Verb RunAs 跑一段内联助手（-EncodedCommand 内存传参，无临时文件竞态）：杀实例 →
# 带调试端口拉起 → 端口未起且实例又出现（MarvisSvr 看门狗拉回了无参实例）→ 连 Svr 一起结束再拉一次。
function Restart-MarvisElevated([string]$exe, [int]$p) {
    $body = @"
`$ErrorActionPreference = 'SilentlyContinue'
Get-Process -Name Marvis -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath '$exe' -ArgumentList ('--remote-debugging-port=$p')
`$up = `$false
for (`$i = 0; `$i -lt 12; `$i++) {
    Start-Sleep -Seconds 1
    try { `$null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/json/version' -f $p) -TimeoutSec 2; `$up = `$true; break } catch {}
}
if (`$up) { exit 0 }
# 看门狗可能抢先拉回了无参实例：连 MarvisSvr 一起结束，再试最后一次
Get-Process -Name Marvis,MarvisSvr -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath '$exe' -ArgumentList ('--remote-debugging-port=$p')
for (`$i = 0; `$i -lt 12; `$i++) {
    Start-Sleep -Seconds 1
    try { `$null = Invoke-RestMethod -Uri ('http://127.0.0.1:{0}/json/version' -f $p) -TimeoutSec 2; break } catch {}
}
exit 0
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc) | Out-Null
        Log $ZHRestart
    } catch {
        Log ($ZHUacFail + ' (' + $_.Exception.Message + ')')
        return $false
    }
    return $true
}

# ---------- 0. single instance ----------
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\ai-wallpaper-marvis')
if (-not $script:Mutex.WaitOne(0)) { Log 'another launcher instance already running, exit'; exit 0 }

# ---------- 1. resolve Marvis / debug port ----------
if (-not (Test-Path $WallDir)) { New-Item -ItemType Directory -Path $WallDir -Force | Out-Null }

$exe = Find-MarvisExe
if (-not $exe) { Log $ZHNoExe; exit 1 }

$marvisUp = $false
try { $marvisUp = ($null -ne (Get-Process -Name Marvis -ErrorAction SilentlyContinue)) } catch {}

$port = 0
if ($marvisUp) {
    foreach ($p in $AllowedPorts) { if (Test-DebugPort $p) { $port = $p; break } }
    if ($port -eq 0) {
        if ($Restart) {
            Log 'Marvis running without debug port (-Restart), restarting elevated'
            $null = Restart-MarvisElevated $exe $AllowedPorts[0]
            $port = $AllowedPorts[0]
            # 助手内部有两轮尝试（含看门狗竞态兜底），外层等足 60s
            for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 1; if (Test-DebugPort $port) { break } }
            if (-not (Test-DebugPort $port)) { Log $ZHNoPort; exit 1 }
        } else {
            Log 'Marvis running without debug port - asking to restart'
            Add-Type -AssemblyName System.Windows.Forms
            $ans = [System.Windows.Forms.MessageBox]::Show($ZHBody, $ZHTitle, 'YesNo', 'Question')
            if ($ans -ne 'Yes') { Log 'user cancelled'; exit 0 }
            if (-not (Restart-MarvisElevated $exe $AllowedPorts[0])) { exit 1 }
            $port = $AllowedPorts[0]
            $ready = $false
            for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 1; if (Test-DebugPort $port) { $ready = $true; break } }
            if (-not $ready) { Log $ZHNoPort; exit 1 }
        }
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
    Log ('starting Marvis with debug port ' + $port + ': ' + $exe)
    try {
        # Marvis.exe manifest = requireAdministrator：非提权直接 Start-Process 会报
        # “requires elevation”，必须 -Verb RunAs（UAC 弹窗与用户平时启动 Marvis 一致）
        Start-Process -FilePath $exe -ArgumentList ("--remote-debugging-port={0}" -f $port) -Verb RunAs | Out-Null
    } catch {
        Log ($ZHUacFail + ' (' + $_.Exception.Message + ')')
        exit 1
    }
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 1500
        if (Test-DebugPort $port) { $ready = $true; break }
    }
    if (-not $ready) { Log $ZHNoPort; exit 1 }
}
Log ($ZHConn + $port)

# ---------- 1.5. start loopback media server ----------
$script:Media = [hashtable]::Synchronized(@{ File = ''; Port = 0 })
$msRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
$msRs.Open()
$msRs.SessionStateProxy.SetVariable('state', $script:Media)
$msPs = [System.Management.Automation.PowerShell]::Create()
$msPs.Runspace = $msRs
$null = $msPs.AddScript($MediaServerScript).BeginInvoke()
for ($i = 0; $i -lt 60 -and $script:Media.Port -eq 0; $i++) { Start-Sleep -Milliseconds 50 }
Log ('media server ready on 127.0.0.1:' + $script:Media.Port)

# ---------- 2. inject agent loop ----------
    $customCss = ''
    if (Test-Path (Join-Path $WallDir 'custom.css')) { $customCss = Get-Content (Join-Path $WallDir 'custom.css') -Raw -Encoding UTF8 }
    $wp = Get-CurrentWallpaper
    if ($wp) { $script:Media.File = $wp.file }
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

    # wallpaper / custom.css / 轮换槽位变化？-> 本轮强制推送到所有主窗口
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
        if ($wp) { $script:Media.File = $wp.file } else { $script:Media.File = '' }
        if (-not $first) {
            $changed = $true
            if ($wp) { Log ($ZHChange + $wp.file) } else { Log ($ZHChange + $ZHClear) }
        }
    }

    foreach ($t in $targets) {
        if ($t.type -ne 'page') { continue }
        # 只注入主窗口（离线包加载器页面）；排除 offline 目录里的辅助页与 devtools
        if ($t.url -notmatch 'yyb-ai-launcher-offline\.qq\.com/index\.html|marvis-offline-page/index\.html') { continue }
        if ($t.url -match 'feedback|publish-case') { continue }
        if (-not $changed) {
            $guard = Send-CdpEval $t.webSocketDebuggerUrl '!!document.getElementById("mvwp-wallpaper")' 8
            if ($guard -ne $false) { continue }   # true = 已注入；null = 页面暂不可达
        }
        Log ($ZHInject + $t.url)
        try {
            if ($wp) { Log (Send-Wallpaper $t.webSocketDebuggerUrl $wp $customCss) }
            else {
                $boot = $BOOTSTRAP_TEMPLATE.Replace('__MVWP_CSS__', (Esc-Json $LAYER_CSS)).Replace('__MVWP_PANEL_CSS__', (Esc-Json $PANEL_CSS)).Replace('__MVWP_CUSTOM_CSS__', (Esc-Json $customCss))
                $null = Send-CdpEval $t.webSocketDebuggerUrl $boot 60
                $null = Send-CdpEval $t.webSocketDebuggerUrl 'var l=document.getElementById("mvwp-wallpaper");l.innerHTML="";l.className="aurora";"aurora-on"' 30
            }
        } catch { Log ('inject error: ' + $_.Exception.Message) }
    }
    Start-Sleep -Milliseconds 2000
}
