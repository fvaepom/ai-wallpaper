# ai-wallpaper — AI 壁纸设置中心（ZCode / WorkBuddy / OpenCode / Codex / Trae / AutoClaw / Marvis / PowerShell / CMD 统一选择器）
# 「当前壁纸」页按应用单独显示：顶部下拉框切换应用，预览与操作（选图/恢复极光/不透明度/重启）
#   只作用于所选应用。应用端实际显示优先级与注入脚本一致：rotate-1.* 存在 → 轮换集，
#   否则 wallpaper.*，否则内置极光（轮换位置由应用内 localStorage 决定，预览显示轮换集第 1 张）。
# 「壁纸库」页负责批量/同步管理与轮换：顶部应用芯片 + 同步开关（存于中心 config.json）。
# 共享壁纸库存放于 %USERPROFILE%\.ai-wallpaper\library，改动通过 refresh 标记免重启热切换。
# 「AI 生成」页调用豆包 Seedream（火山方舟 images/generations）文生图：描述 → 生成 → 自动入库 → 一键应用。
# PowerShell / CMD 为零补丁目标：壁纸写 Windows Terminal settings.json 对应 profile（热加载），
#   视频/webp 自动抽帧转 png；轮换降级为固定轮换集第 1 张；只要 WT 存在即自建目录常驻列表。

Add-Type -AssemblyName PresentationFramework, WindowsBase, System.Drawing, System.Windows.Forms

# 进程 AUMID：任务栏将使用开始菜单「AI壁纸设置」快捷方式的图标（不设则显示 powershell.exe 图标）
Add-Type -Namespace WpNative -Name AppId -MemberDefinition `
    '[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);'
[void][WpNative.AppId]::SetCurrentProcessExplicitAppUserModelID('AI.WallpaperPicker')

# ── Shell 视频缩略图（视频卡片静态帧） ───────────────────
if (-not ('ShellThumb' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public class ShellThumb {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    public static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, out IShellItemImageFactory ppv);
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemImageFactory {
        void GetImage(SIZE size, int flags, out IntPtr phbm);
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct SIZE { public int cx; public int cy; }
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr h);

    public static Bitmap GetThumb(string path, int cx, int cy) {
        Guid guid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
        IShellItemImageFactory factory;
        SHCreateItemFromParsingName(path, IntPtr.Zero, ref guid, out factory);
        SIZE size = new SIZE();
        size.cx = cx;
        size.cy = cy;
        IntPtr hbm;
        factory.GetImage(size, 0, out hbm);
        Bitmap copy;
        using (Bitmap raw = (Bitmap)Image.FromHbitmap(hbm)) {
            // WTS 现场生成的 32bpp 位图 alpha 通道为 0（缓存命中才正常），
            // 克隆为 24bpp 直接丢弃 alpha、保留 RGB 画面，否则 PNG 全透明导致卡片黑屏
            copy = raw.Clone(new Rectangle(0, 0, raw.Width, raw.Height),
                System.Drawing.Imaging.PixelFormat.Format24bppRgb);
        }
        DeleteObject(hbm);
        return copy;
    }
}
'@ -ReferencedAssemblies System.Drawing
}

# ── 中心目录与应用发现 ───────────────────────────────────
$hub    = Join-Path $env:USERPROFILE '.ai-wallpaper'
$hubLib = Join-Path $hub 'library'
$hubCfgPath = Join-Path $hub 'config.json'
foreach ($d in @($hub, $hubLib)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$AllApps = @(
    @{ Name = 'ZCode';     Dir = (Join-Path $env:USERPROFILE '.zcode\wallpaper');     Proc = 'ZCode';
       ExeCandidates = @('F:\Program files\ZCode\ZCode.exe', 'C:\Program files\ZCode\ZCode.exe');
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ZCode.lnk" },
    @{ Name = 'WorkBuddy'; Dir = (Join-Path $env:USERPROFILE '.workbuddy\wallpaper'); Proc = 'WorkBuddy';
       ExeCandidates = @('F:\Program files\WorkBuddy\WorkBuddy.exe', 'C:\Program files\WorkBuddy\WorkBuddy.exe');
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\WorkBuddy.lnk" },
    @{ Name = 'OpenCode';  Dir = (Join-Path $env:USERPROFILE '.opencode\wallpaper');  Proc = 'OpenCode';
       ExeCandidates = @("$env:LOCALAPPDATA\Programs\@opencode-aidesktop\OpenCode.exe");
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OpenCode.lnk" },
    @{ Name = 'Codex';     Dir = (Join-Path $env:USERPROFILE '.codex\wallpaper');     Proc = 'ChatGPT';
       ExeCandidates = @('C:\Users\FVAEP\CodexPatched\app\ChatGPT.exe');
       Lnk = '';
       # 散装副本 + CDP 代理（商店 MSIX 包已卸载）：重启 = 重新运行壁纸启动器，
       # 启动器带调试端口拉起 Codex 并经 CDP 注入壁纸；普通方式启动无壁纸
       Launcher = (Join-Path $hub 'codex-launcher.vbs');
       Agent = $true },
    @{ Name = 'Trae CN';   Dir = (Join-Path $env:USERPROFILE '.trae-cn\wallpaper');   Proc = 'Trae CN';
       ExeCandidates = @('F:\AIcodeprogram\Trae CN\Trae CN.exe');
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Trae CN\Trae CN.lnk";
       PatchId = 'TraeCN';
       # Trae 系为散装 resources\app 目录（无 app.asar），补丁探测点是主窗口 HTML
       ProbeRel = 'app\out\vs\code\electron-browser\workbench\workbench.html' },
    @{ Name = 'Trae Work CN'; Dir = (Join-Path $env:USERPROFILE '.trae-cn\wallpaper-solo'); Proc = 'TRAE SOLO CN';
       ExeCandidates = @('F:\AIcodeprogram\TRAE SOLO CN\TRAE SOLO CN.exe');
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\TRAE Work CN\TRAE Work CN.lnk";
       PatchId = 'TraeWorkCN';
       ProbeRel = 'app\out\vs\code\electron-browser\solo\solo-lite.html' },
    @{ Name = 'Doubao';    Dir = (Join-Path $env:USERPROFILE '.doubao\wallpaper');    Proc = 'Doubao';
       ExeCandidates = @('F:\Program files\Doubao\Doubao.exe', 'C:\Program files\Doubao\Doubao.exe');
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Doubao.lnk";
       # 豆包是 Chromium 壳（无 asar）：壁纸由 hub 里的 doubao-launcher 代理经 CDP 注入，换壁纸免重启
       Launcher = (Join-Path $hub 'doubao-launcher.vbs');
       Agent = $true },
    @{ Name = 'AutoClaw';  Dir = (Join-Path $env:APPDATA 'autoclaw\wallpaper');       Proc = 'AutoClaw';
       ExeCandidates = @('F:\AIcodeprogram\AUTOCLAW\AutoClaw.exe');
       Lnk = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AutoClaw.lnk';
       PatchId = 'AutoClaw' },
    @{ Name = 'Marvis';    Dir = (Join-Path $env:USERPROFILE '.marvis\wallpaper');    Proc = 'Marvis';
       # 腾讯 Marvis（Qt5+CEF）：壁纸脚本内联注入 Roaming 离线页 + zwp-media junction，
       # 换壁纸经 refresh 标记热生效。Marvis.exe 需管理员 → 重启走 -Verb RunAs
       ExeCandidates = @(
           Get-ChildItem 'C:\Program Files\Tencent\Marvis\Application' -Directory -ErrorAction SilentlyContinue |
               ForEach-Object { Join-Path $_.FullName 'Marvis.exe' } | Where-Object { Test-Path $_ }
       );
       Lnk = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Marvis.lnk';
       PatchId = 'Marvis';
       Elevate = $true;
       ProbeFile = "$env:APPDATA\Tencent\Marvis\marvis-offline-page\using\index.html" },
    @{ Name = 'Reasonix';  Dir = (Join-Path $env:USERPROFILE '.reasonix\wallpaper');  Proc = 'Reasonix';
       # Reasonix 桌面壳：launcher + versions\<激活版本>\app 布局（current.json 指向激活版本）。
       # 探测点在版本子目录里 → VersionLayout 走 current.json 解析；重启必须经官方 launcher
       # 快捷方式（直接启动 versions 里的 app exe 不保证带完整环境）
       ExeCandidates = @('F:\AIcodeprogram\Reasonix\Reasonix.exe', 'C:\Program files\Reasonix\Reasonix.exe');
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Reasonix.lnk";
       PatchId = 'Reasonix';
       VersionLayout = $true;
       RelaunchLnk = $true;
       ProbeRel = 'app\index.html' },
    @{ Name = 'DeepSeek Harness'; Dir = (Join-Path $env:USERPROFILE '.dsh\wallpaper'); Proc = 'DSH Desktop';
       # 开源 DeepSeek Harness 桌面端（DSH Desktop）：壁纸脚本内联注入回环前端
       # dsh-web-frontend\dist\index.html，媒体走回环服务 /dsh 根，换壁纸经 refresh 标记热生效。
       # 正常快捷方式启动即有壁纸（无需专用启动器）
       ExeCandidates = @("$env:LOCALAPPDATA\Programs\DSH Desktop\DSH Desktop.exe");
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DSH Desktop.lnk";
       PatchId = 'DeepSeekHarness';
       ProbeRel = 'app\node_modules\@deepseek-ai\dsh-web-frontend\dist\index.html' },
    @{ Name = 'PowerShell'; Dir = (Join-Path $env:USERPROFILE '.terminal\wallpaper-ps'); Proc = 'WindowsTerminal';
       ExeCandidates = @(); Lnk = '';
       # PowerShell / CMD 由 Windows Terminal 承载（零补丁）：壁纸写入 settings.json 对应 profile 的
       # background 三键（profile + profiles.defaults 双写，键名 backgroundImage 见 Set-WtBackground）
       # png/jpg/bmp/gif，gif 可动；视频/webp 由 ffmpeg 抽帧转 png。WT 监听 settings.json 改动自动热加载
       # → 换壁纸/调不透明度即时生效，免重启。guid 是 WT 动态 profile 的规范 GUID；找不到时按 name 锚定正则回退匹配
       Terminal = $true
       WtGuid = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'; WtNameMatch = '^(windows powershell|powershell)$' },
    @{ Name = 'CMD';        Dir = (Join-Path $env:USERPROFILE '.terminal\wallpaper-cmd'); Proc = 'WindowsTerminal';
       ExeCandidates = @(); Lnk = '';
       Terminal = $true
       WtGuid = '{0caa0dad-35be-5f56-a8ff-afceeeaa6101}'; WtNameMatch = '^(命令提示符|command prompt)$' }
)
# 终端目标自举：只要 Windows Terminal 的 settings.json 存在（商店版/预览版/散装版任一）就建好壁纸目录并常驻列表
$wtSettingsPath = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($wtSettingsPath) {
    foreach ($a in $AllApps) {
        if ($a.Terminal -and -not (Test-Path $a.Dir)) { New-Item -ItemType Directory -Path $a.Dir -Force | Out-Null }
    }
}
$Apps = @($AllApps | Where-Object { Test-Path $_.Dir })
if ($Apps.Count -eq 0) {
    [System.Windows.MessageBox]::Show(
            '未检测到可管理的应用（ZCode / WorkBuddy / OpenCode / Codex / Trae / AutoClaw / Marvis / Reasonix / DeepSeek Harness / PowerShell / CMD）。' + [char]10 +
        '请先在对应应用上执行 apply-patch.ps1 安装壁纸补丁。',
        'AI 壁纸设置', 'OK', 'Warning') | Out-Null
    exit
}
$AppMap = @{}
foreach ($a in $Apps) {
    if (-not (Test-Path (Join-Path $a.Dir 'rotate'))) { New-Item -ItemType Directory -Path (Join-Path $a.Dir 'rotate') -Force | Out-Null }
    $AppMap[$a.Name] = $a
}

# ── 补丁健康检测与修复（应用升级会覆盖补丁文件，这里负责发现失效并一键重装） ──
# 修复工具链由 apply-patch.ps1 部署到 %USERPROFILE%\.ai-wallpaper\repair\（含其 files\ 依赖）
$RepairTool = Join-Path $hub 'repair\apply-patch.ps1'

function Get-ProbeRel($app) {
    # 补丁探测点：asar 类应用是 resources\app.asar；Trae 系是主窗口 HTML 相对路径
    if ($app.ProbeRel) { return $app.ProbeRel }
    return 'app.asar'
}

function Test-AsarPatched([string]$path) {
    # asar 头部 JSON 明文列出归档内全部文件名，补丁存在 ⇒ 头部必含 oc-wallpaper 条目；
    # 只读前 8MB，几百 MB 的归档也能亚秒级判定，无需解包
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

# 自动识别应用安装目录（升级换目录也能跟上）：运行中进程 → 已知候选 → 开始菜单快捷方式
# → 注册表卸载信息 → MSIX 包。找到的目录必须包含该应用的补丁探测点。
function Find-InstallDir($app) {
    $probe = Get-ProbeRel $app
    $ok = { param($d) $d -and (Test-Path (Join-Path (Join-Path $d 'resources') $probe)) }
    # Reasonix 等 launcher+versions 布局：真目录在 <根>\versions\<激活版本>\app，
    # 由 current.json 解析；-Dir 给 appDir 本身或 launcher 根都接受
    if ($app.VersionLayout) {
        $resolve = {
            param($root)
            if (-not $root -or -not (Test-Path $root)) { return $null }
            if (Test-Path (Join-Path (Join-Path $root 'resources') $probe)) { return $root }
            $cj = Join-Path $root 'current.json'
            if (-not (Test-Path $cj)) { return $null }
            try { $meta = Get-Content $cj -Raw | ConvertFrom-Json } catch { return $null }
            if (-not $meta.activeDir) { return $null }
            $d = Join-Path (Join-Path $root $meta.activeDir) 'app'
            if (Test-Path (Join-Path (Join-Path $d 'resources') $probe)) { return $d }
            return $null
        }
        foreach ($p in (Get-Process -Name $app.Proc -ErrorAction SilentlyContinue)) {
            if (-not $p.Path) { continue }
            $dir = Split-Path $p.Path
            $d = if ($dir -match '\\versions\\') { $dir } else { & $resolve $dir }
            if ($d -and (Test-Path (Join-Path (Join-Path $d 'resources') $probe))) { return $d }
        }
        foreach ($cand in $app.ExeCandidates) {
            if (Test-Path $cand) { $d = & $resolve (Split-Path $cand); if ($d) { return $d } }
        }
        if ($app.Lnk -and (Test-Path $app.Lnk)) {
            try {
                $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($app.Lnk)
                $d = & $resolve (Split-Path $sh.TargetPath)
                if ($d) { return $d }
            } catch {}
        }
        foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
            foreach ($k in (Get-ItemProperty $root -ErrorAction SilentlyContinue)) {
                if ($k.DisplayName -match [regex]::Escape($app.Proc) -and $k.InstallLocation) {
                    $d = & $resolve $k.InstallLocation.TrimEnd('\')
                    if ($d) { return $d }
                }
            }
        }
        return $null
    }
    $p = Get-Process -Name $app.Proc -ErrorAction SilentlyContinue |
        Where-Object { $_.Path } | Select-Object -First 1
    if ($p -and (& $ok (Split-Path $p.Path))) { return (Split-Path $p.Path) }
    foreach ($cand in $app.ExeCandidates) {
        $d = Split-Path $cand
        if (& $ok $d) { return $d }
    }
    if ($app.Lnk -and (Test-Path $app.Lnk)) {
        try {
            $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($app.Lnk)
            $d = Split-Path $sh.TargetPath
            if (& $ok $d) { return $d }
        } catch {}
    }
    if ($app.MsixId) {
        try {
            $pkg = Get-AppxPackage -Name $app.MsixId -ErrorAction SilentlyContinue
            if ($pkg -and $pkg.InstallLocation) {
                $d = Join-Path $pkg.InstallLocation 'app'
                if (& $ok $d) { return $d }
            }
        } catch {}
        return $null
    }
    $pat = [regex]::Escape($app.Proc)
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($k in (Get-ItemProperty $root -ErrorAction SilentlyContinue)) {
            $d = $null
            if ($k.InstallLocation -and ($k.DisplayName -match $pat)) { $d = $k.InstallLocation }
            elseif ($k.DisplayIcon -match ($pat + '\.exe')) { $d = Split-Path ($k.DisplayIcon -replace ',\d*$','') }
            if (& $ok $d) { return $d }
        }
    }
    return $null
}

# 单应用健康状态：Dir=识别到的安装目录（$null=没找到）；Broken=补丁丢失可修复
function Get-AppHealth([string]$name) {
    $app = $AppMap[$name]
    $h = [pscustomobject]@{ Dir = $null; Broken = $false; Detail = '' }
    if ($app.Agent) {
        # 代理型应用（Doubao）：补丁 = hub 里的启动器/代理文件，无 asar 可查
        if ($app.Launcher -and (Test-Path $app.Launcher)) { return $h }
        $h.Broken = $true; $h.Detail = "壁纸代理缺失，重新运行 apply-patch.ps1 -App $name 安装"
        return $h
    }
    if ($app.ProbeFile) {
        # Marvis：补丁探测点 = Roaming 离线页 index.html（内联脚本被 Marvis 更新缓存覆盖即失效）
        if (-not (Test-Path $app.ProbeFile)) { $h.Detail = '离线页缓存不存在（启动一次 Marvis 后再试）'; return $h }
        if ([IO.File]::ReadAllText($app.ProbeFile) -notmatch 'oc-wallpaper') {
            $h.Broken = $true; $h.Detail = '壁纸补丁已丢失（多半是 Marvis 更新了离线页缓存）'
        }
        return $h
    }
    if ($app.Terminal) {
        # 终端目标（PowerShell / CMD）零补丁：只读写 WT 的 settings.json，没有会失效的补丁文件
        $h.Detail = if ($wtSettingsPath) { 'Windows Terminal 设置文件已就绪' } else { '未找到 Windows Terminal（商店版/预览版/散装版均未安装）' }
        return $h
    }
    $h.Dir = Find-InstallDir $app
    if (-not $h.Dir) { $h.Detail = '未找到安装目录（应用可能未安装或装在未知路径）'; return $h }
    if ($app.ProbeRel) {
        $htmlPath = Join-Path (Join-Path $h.Dir 'resources') $app.ProbeRel
        if (-not (Test-Path $htmlPath)) { $h.Detail = '主窗口 HTML 不存在（版本结构变了？）'; return $h }
        if ([IO.File]::ReadAllText($htmlPath) -notmatch 'oc-wallpaper') {
            $h.Broken = $true; $h.Detail = '壁纸补丁已丢失（多半是应用升级覆盖了文件）'
        }
        return $h
    }
    $asar = Join-Path $h.Dir 'resources\app.asar'
    if (-not (Test-Path $asar)) { $h.Detail = 'resources\app.asar 不存在（版本结构变了？）'; return $h }
    if (-not (Test-AsarPatched $asar)) {
        $h.Broken = $true; $h.Detail = '壁纸补丁已丢失（多半是应用升级覆盖了 app.asar）'
    }
    return $h
}

function Update-AppHealth {
    $script:Health = @{}
    foreach ($name in $Apps.Name) { $script:Health[$name] = Get-AppHealth $name }
    Update-HealthVisuals
}

# 失效应用在两处芯片上追加 ⚠ 标记
function Update-HealthVisuals {
    foreach ($name in @($Apps.Name)) {
        $h = $script:Health[$name]
        $warn = if ($h -and $h.Broken) { ' ⚠' } else { '' }
        if ($script:ChipMap -and $script:ChipMap.ContainsKey($name))    { $script:ChipMap[$name].Content    = $name + $warn }
        if ($script:NowComboMap -and $script:NowComboMap.ContainsKey($name)) { $script:NowComboMap[$name].Content = $name + $warn }
    }
    $broken = @($Apps.Name | Where-Object { $script:Health[$_].Broken })
    $bar = Ctrl 'FixBar'
    if (-not $bar) { return }
    if ($broken.Count -eq 0) {
        $bar.Visibility = 'Collapsed'
    } else {
        # 条上只放一行摘要；逐应用明细放 ToolTip（条内换行会把页面底部内容挤出窗口）
        $fixText = Ctrl 'FixText'
        $detail = (($broken | ForEach-Object { "$_ ：$($script:Health[$_].Detail)" }) -join "`n")
        $fixText.Text = "$($broken -join '、') 的壁纸补丁已失效（多为应用升级覆盖），点「一键修复」自动重打"
        $fixText.ToolTip = $detail
        $bar.Visibility = 'Visible'
    }
}
$script:Health = @{}

# ── 配置：中心 config.json（同步模式）+ 各应用 config.json（独立模式） ──
function Get-CfgFrom([string]$path) {
    if (Test-Path $path) {
        try {
            $c = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $iv = 0
            if ($c.interval) { $iv = [int]$c.interval }
            return [pscustomobject]@{
                sync     = [bool]$c.sync
                rotation = [bool]$c.rotation
                interval = $iv
                items    = @($c.items | Where-Object { $_ -ne $null })
                checked  = @($c.checked | Where-Object { $_ -ne $null })
            }
        } catch {}
    }
    return [pscustomobject]@{ sync = $true; rotation = $false; interval = 0; items = @(); checked = @() }
}
function Get-HubConfig { return Get-CfgFrom $hubCfgPath }
function Save-HubConfig($c) {
    $c | ConvertTo-Json -Depth 6 | Set-Content -Path $hubCfgPath -Encoding UTF8
}
function Get-AppConfigPath([string]$name) { Join-Path $AppMap[$name].Dir 'config.json' }
function Get-AppConfig([string]$name) {
    $c = Get-CfgFrom (Get-AppConfigPath $name)
    $c.sync = $false
    return $c
}
function Save-AppConfig([string]$name, $c) {
    $c | ConvertTo-Json -Depth 6 | Set-Content -Path (Get-AppConfigPath $name) -Encoding UTF8
}

$hubCfg = Get-HubConfig
$script:Sync = [bool]$hubCfg.sync
# 芯片单选 = 当前正在调整的应用（透明度永远按应用单独设置）
$script:Active = @($hubCfg.checked | Where-Object { $AppMap.ContainsKey($_) })[0]
if (-not $script:Active) { $script:Active = $Apps[0].Name }
# 同步模式的批量操作目标（Get-Targets / 提示文案都依赖它；不初始化的话
# 「应用」按钮拿到空目标列表，点了没有任何效果，提示里应用名也丢成空白）
$script:Checked = @($hubCfg.checked | Where-Object { $AppMap.ContainsKey($_) })
if ($script:Checked.Count -eq 0) { $script:Checked = @($script:Active) }

# ── 迁移：把各应用旧壁纸库并入中心库，应用配置指向中心文件名 ──
function Import-LegacyLibraries {
    $hubItems = @(($hubCfg.items) | ForEach-Object { $_ })
    foreach ($a in $Apps) {
        $appLib = Join-Path $a.Dir 'library'
        if (-not (Test-Path $appLib)) { continue }
        foreach ($f in (Get-ChildItem $appLib -File -ErrorAction SilentlyContinue)) {
            $hubFile = Join-Path $hubLib $f.Name
            if (-not (Test-Path $hubFile)) {
                Copy-Item $f.FullName $hubFile -Force
            } elseif ((Get-Item $hubFile).Length -ne $f.Length) {
                # 同名不同内容 → 按应用改名收编
                $newName = $a.Name + '-' + $f.Name
                Copy-Item $f.FullName (Join-Path $hubLib $newName) -Force
                $hubItems += [pscustomobject]@{ file = $newName; type = 'image'; rotate = $false; added = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
                continue
            }
            if (-not ($hubItems | Where-Object { $_.file -eq $f.Name })) {
                $hubItems += [pscustomobject]@{
                    file   = $f.Name
                    type   = $(if ($f.Name -match '\.(mp4|webm)$') { 'video' } else { 'image' })
                    rotate = $false
                    added  = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                }
            }
        }
        # 应用配置里的条目改指向中心库后原样保留 rotation/interval
        $ap = Get-AppConfigPath $a.Name
        if (Test-Path $ap) {
            try {
                $c = Get-AppConfig $a.Name
                $c.items = @($c.items | Where-Object { $_ -ne $null -and (Test-Path (Join-Path $hubLib $_.file)) })
                Save-AppConfig $a.Name $c
            } catch {}
        }
    }
    if ($hubCfg.items.Count -eq 0 -and $hubItems.Count -gt 0) {
        $hubCfg.items = $hubItems
    }
    Save-HubConfig $hubCfg
}
Import-LegacyLibraries

# ── 豆包 AI 生成配置（doubao.json：API Key / 模型 / 尺寸 / 张数，仅存本机） ──
$aiCfgPath = Join-Path $hub 'doubao.json'
function Get-AiConfig {
    if (Test-Path $aiCfgPath) {
        try {
            $c = Get-Content $aiCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return [pscustomobject]@{
                apiKey = [string]$c.apiKey
                model  = if ($c.model) { [string]$c.model } else { 'doubao-seedream-4-0-250828' }
                size   = if ($c.size)  { [string]$c.size }  else { '2K' }
                count  = if ($c.count) { [int]$c.count }    else { 1 }
            }
        } catch {}
    }
    return [pscustomobject]@{ apiKey = ''; model = 'doubao-seedream-4-0-250828'; size = '2K'; count = 1 }
}
function Save-AiConfig($c) { $c | ConvertTo-Json -Depth 3 | Set-Content -Path $aiCfgPath -Encoding UTF8 }
$script:Ai = Get-AiConfig

# ── 媒体探测/轮换重建（参数化到指定应用） ─────────────────
function Get-WallpaperFile([string]$appName) {
    foreach ($e in @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')) {
        $f = Join-Path $AppMap[$appName].Dir "wallpaper.$e"
        if (Test-Path $f) { return $f }
    }
    return $null
}

function Find-RotateFirst([string]$appName) {
    foreach ($e in @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')) {
        $cand = Join-Path (Join-Path $AppMap[$appName].Dir 'rotate') "rotate-1.$e"
        if (Test-Path $cand) { return $cand }
    }
    return $null
}

function Resolve-LibFile([string]$appName, [string]$fileName) {
    $hubFile = Join-Path $hubLib $fileName
    if (Test-Path $hubFile) { return $hubFile }
    $legacy = Join-Path (Join-Path $AppMap[$appName].Dir 'library') $fileName
    if (Test-Path $legacy) { return $legacy }
    return $null
}

function Touch-LiveMarker([string]$appName) {
    # 递增编号的 1x1 透明 GIF 标记：应用内壁纸脚本每 5~8 秒轮询，编号变化即免重启热切换。
    # 编号按「每应用独立计数、循环 1..3」写入，保证对同一应用相邻两次写入的编号必不同：
    #   - ZCode 实际部署的旧版注入脚本只探测 refresh-1..3，写到 4/5 它永远看不见（壁纸迟迟不切换）；
    #   - 新版脚本探测 1..5 位图，单个标记在 1..3 内移动同样每次都能识别。
    $rot = Join-Path $AppMap[$appName].Dir 'rotate'
    if (-not (Test-Path $rot)) { New-Item -ItemType Directory -Path $rot -Force | Out-Null }
    Get-ChildItem $rot -Filter 'refresh-*' -ErrorAction SilentlyContinue | Remove-Item -Force
    # 计数文件放在应用壁纸目录（rotate 目录会被 Rebuild-Rotate 整体清理，放那里计数会回绕撞号）
    $counterPath = Join-Path $AppMap[$appName].Dir '.marker-counter'
    $c = 0
    try { if (Test-Path $counterPath) { $c = [int](Get-Content $counterPath -Raw) } } catch {}
    $c++
    Set-Content -Path $counterPath -Value $c -Encoding ASCII
    $gif = [Convert]::FromBase64String('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')
    [IO.File]::WriteAllBytes((Join-Path $rot ("refresh-" + (($c % 3) + 1) + ".gif")), $gif)
}

function Rebuild-Rotate([string]$appName, $cfg) {
    if ($AppMap[$appName].Terminal) {
        # 终端没有轮换脚本可驱动：轮换集第 1 张固定为当前壁纸（关闭轮换则保持现状不动）
        if ($cfg.rotation) {
            $first = @($cfg.items) | Where-Object { $_ -ne $null -and $_.rotate } | Sort-Object added | Select-Object -First 1
            if ($first) {
                $src = Resolve-LibFile $appName $first.file
                if ($src) { Set-TerminalWallpaper $appName $src | Out-Null }
            }
        }
        return
    }
    $rot = Join-Path $AppMap[$appName].Dir 'rotate'
    Get-ChildItem $rot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'refresh-*' } | Remove-Item -Force
    if ($cfg.rotation) {
        $n = 1
        foreach ($it in (@($cfg.items) | Where-Object { $_.rotate } | Sort-Object added)) {
            $src = Resolve-LibFile $appName $it.file
            if ($src) {
                Copy-Item $src (Join-Path $rot ("rotate-$n" + [IO.Path]::GetExtension($it.file))) -Force
                $n++
            }
        }
        if ($cfg.interval -gt 0) {
            $gif = [Convert]::FromBase64String('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')
            [IO.File]::WriteAllBytes((Join-Path $rot "interval-$($cfg.interval).gif"), $gif)
        }
    }
    Touch-LiveMarker $appName
}

# 当前生效目标（壁纸库页批量操作）：同步=所有勾选应用；独立=当前应用
function Get-Targets {
    if ($script:Sync) { return @($script:Checked) } else { return @($script:Active) }
}
function TargetsText {
    if ($script:Sync) { return ($script:Checked -join '、') }
    return $script:Active
}
# 某应用当前生效的轮换配置：被同步勾选 → 中心配置；否则该应用自己的配置
function Get-AppRotCfg([string]$appName) {
    if ($script:Sync -and ($script:Checked -contains $appName)) { return Get-HubConfig }
    return Get-AppConfig $appName
}
# 读写"当前模式"的轮换配置（同步→中心；独立→当前应用）
function Get-Cfg {
    if ($script:Sync) { return Get-HubConfig } else { return Get-AppConfig $script:Active }
}
function Commit-Cfg($cfg) {
    if ($script:Sync) {
        $cfg.sync = $true
        $cfg.checked = @($script:Checked)
        Save-HubConfig $cfg
        foreach ($name in $script:Checked) {
            $c2 = [pscustomobject]@{
                sync     = $false
                rotation = [bool]$cfg.rotation
                interval = [int]$cfg.interval
                items    = @($cfg.items)
                checked  = @($script:Checked)
            }
            Save-AppConfig $name $c2
            Rebuild-Rotate $name $c2
        }
    } else {
        $cfg.sync = $false
        Save-AppConfig $script:Active $cfg
        Rebuild-Rotate $script:Active $cfg
        $hubCfg2 = Get-HubConfig
        $hubCfg2.checked = @($script:Checked)
        Save-HubConfig $hubCfg2
    }
}

# ── XAML 界面 ────────────────────────────────────────────
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI 壁纸设置" Height="727" Width="560"
        WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" Topmost="True" FontFamily="Microsoft YaHei UI"
        AllowDrop="True">
  <Window.Resources>
    <Style x:Key="BtnPrimary" TargetType="Button">
      <Setter Property="Background" Value="#3B82F6"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="9"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#4F8FF7"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2E6FE0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnGhost" TargetType="Button">
      <Setter Property="Background" Value="#262A35"/>
      <Setter Property="Foreground" Value="#C9CEDA"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Height" Value="36"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#313646"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnMini" TargetType="Button">
      <Setter Property="Background" Value="#262A35"/>
      <Setter Property="Foreground" Value="#C9CEDA"/>
      <Setter Property="FontSize" Value="10.5"/>
      <Setter Property="Height" Value="24"/>
      <!-- 模板 Border 不吃 Padding 的话文字会贴边裁字（如「保存 Key」） -->
      <Setter Property="Padding" Value="8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#333849"/>
                <Setter Property="Foreground" Value="#ECECEC"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CaptionBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#8A90A0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Width" Value="42"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2E3342"/>
                <Setter Property="Foreground" Value="#ECECEC"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TabPill" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#8A90A0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bd" Background="Transparent" CornerRadius="8" Padding="16,7" Margin="0,0,8,0">
              <ContentPresenter Content="{TemplateBinding Content}" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#313646"/>
                <Setter Property="Foreground" Value="#ECECEC"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#262A35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NowPill" TargetType="RadioButton">
      <!-- 已改用「当前查看」下拉框，此样式保留备用 -->
      <Setter Property="Foreground" Value="#8A90A0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bd" Background="#262A35" CornerRadius="12" Padding="14,5"
                    BorderBrush="#3A4050" BorderThickness="1">
              <ContentPresenter Content="{TemplateBinding Content}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#3B82F6"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#3B82F6"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#313646"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="AppChip" TargetType="ToggleButton">
      <Setter Property="Foreground" Value="#8A90A0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="bd" Background="#262A35" CornerRadius="13" Padding="13,5" BorderBrush="#3A4050" BorderThickness="1">
              <StackPanel Orientation="Horizontal">
                <Ellipse x:Name="dot" Width="7" Height="7" Fill="#4A5268" VerticalAlignment="Center"/>
                <ContentPresenter Margin="7,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#173156"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#3B82F6"/>
                <Setter Property="Foreground" Value="#ECECEC"/>
                <Setter TargetName="dot" Property="Fill" Value="#3B82F6"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2E3342"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Foreground" Value="#C9CEDA"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal">
              <Border x:Name="track" Width="40" Height="22" CornerRadius="11" Background="#313646"
                      VerticalAlignment="Center">
                <Ellipse x:Name="knob" Width="16" Height="16" Fill="#8A90A0"
                         HorizontalAlignment="Left" Margin="3,0,0,0"/>
              </Border>
              <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="#3B82F6"/>
                <Setter TargetName="knob" Property="Fill" Value="White"/>
                <Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="tb" Background="#3A4050" CornerRadius="4"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="tb" Property="Background" Value="#4A5268"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="IvPill" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#8A90A0"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bd" Background="#262A35" CornerRadius="12" Padding="11,4" Margin="0,0,6,0">
              <ContentPresenter Content="{TemplateBinding Content}" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#3B82F6"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#313646"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border CornerRadius="14" Background="#1B1D23" BorderBrush="#2A2E3B" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0" Background="Transparent" x:Name="DragBar">
        <StackPanel Orientation="Horizontal" Margin="20,0,0,0" VerticalAlignment="Center">
          <Ellipse Width="9" Height="9" Fill="#3B82F6" VerticalAlignment="Center"/>
          <TextBlock Text="AI 壁纸" Foreground="#ECECEC" FontSize="14.5" FontWeight="SemiBold"
                     Margin="10,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Text="多应用动态壁纸管理" Foreground="#5B6172" FontSize="12" Margin="8,2,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,10,0">
          <Button x:Name="BtnMin" Style="{StaticResource CaptionBtn}" Content="─"/>
          <Button x:Name="BtnClose" Style="{StaticResource CaptionBtn}" Content="✕"/>
        </StackPanel>
      </Grid>

      <Grid Grid.Row="1" Margin="20,2,20,16">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
          <RadioButton x:Name="TabNow" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="当前壁纸" IsChecked="True"/>
          <RadioButton x:Name="TabLib" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="壁纸库"/>
          <RadioButton x:Name="TabAi" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="AI 生成 · 豆包"/>
        </StackPanel>

        <!-- 补丁失效警告条：应用升级覆盖补丁后出现，一键重装（自动识别安装目录）。
             文本钉死单行（完整明细进 ToolTip），条高稳定，不再把页面底部内容挤出窗口 -->
        <Border Grid.Row="1" x:Name="FixBar" Visibility="Collapsed" Background="#2B2313"
                BorderBrush="#8A6A1F" BorderThickness="1" CornerRadius="10"
                Padding="14,7" Margin="0,0,0,8">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="⚠" Foreground="#FBBF24" FontSize="14" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock x:Name="FixText" Foreground="#E8D9AC" FontSize="11.5" TextTrimming="CharacterEllipsis"
                         VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0">
              <Button x:Name="BtnRecheck" Style="{StaticResource BtnMini}" Content="重新检测"
                      Height="30" FontSize="12" Padding="12,0" VerticalAlignment="Center"/>
              <Button x:Name="BtnFix" Style="{StaticResource BtnPrimary}" Content="一键修复"
                      Height="30" FontSize="12.5" Padding="14,0" Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>
        </Border>

        <Grid Grid.Row="2">
          <!-- 页 1：当前壁纸（按应用单独显示，顶部按钮切换应用） -->
          <Grid x:Name="PageNow">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#101218" CornerRadius="10" Padding="14,8" Margin="0,0,0,8"
                    BorderBrush="#242835" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="当前查看" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <!-- SelectedValuePath 指向 Tag（应用名）：默认 SelectedValue 是 ComboBoxItem 自身，
                     字符串化后是 "System.Windows.Controls.ComboBoxItem: xxx" 英文类型名，
                     会经 SelectionChanged 污染 $script:NowApp，把「重启 …」按钮等文案全带歪 -->
                <ComboBox Grid.Column="1" x:Name="NowAppCombo" Width="220" Height="28" FontSize="12"
                          SelectedValuePath="Tag"
                          VerticalContentAlignment="Center" ToolTip="选择要查看的应用（⚠ = 壁纸补丁失效）"/>
              </Grid>
            </Border>
            <Border Grid.Row="1" CornerRadius="10" Background="#0B0D12" Height="293"
                    BorderBrush="#242835" BorderThickness="1" ClipToBounds="True">
              <Grid x:Name="PreviewArea" Background="Transparent">
                <Image x:Name="Preview" Stretch="Uniform" Visibility="Collapsed"/>
                <MediaElement x:Name="PreviewVideo" Stretch="Uniform" Visibility="Collapsed"
                              LoadedBehavior="Manual" UnloadedBehavior="Close" IsMuted="True"
                              Volume="0" SpeedRatio="1"/>
                <StackPanel x:Name="PreviewEmpty" HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="48" Height="48" HorizontalAlignment="Center">
                    <Ellipse Width="48" Height="48">
                      <Ellipse.Fill>
                        <RadialGradientBrush>
                          <GradientStop Color="#663B82F6" Offset="0.4"/>
                          <GradientStop Color="#001B1D23" Offset="1"/>
                        </RadialGradientBrush>
                      </Ellipse.Fill>
                    </Ellipse>
                    <Ellipse Width="24" Height="24">
                      <Ellipse.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                          <GradientStop Color="#60A5FA" Offset="0"/>
                          <GradientStop Color="#7C3AED" Offset="1"/>
                        </LinearGradientBrush>
                      </Ellipse.Fill>
                    </Ellipse>
                  </Grid>
                  <TextBlock x:Name="EmptyText" Text="未设置壁纸 · 使用内置动态极光" Foreground="#6B7183" FontSize="12.5"
                             HorizontalAlignment="Center" Margin="0,10,0,0"/>
                </StackPanel>
                <Border x:Name="Badge" CornerRadius="6" Background="#CC101218" Padding="10,5"
                        HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="10,10,0,10" Visibility="Collapsed">
                  <TextBlock x:Name="BadgeText" Foreground="#C9CEDA" FontSize="11.5"/>
                </Border>
              </Grid>
            </Border>
            <StackPanel Grid.Row="2" Margin="0,12,0,0">
              <Button x:Name="BtnPick" Style="{StaticResource BtnPrimary}" Content="为当前应用选择图片 / 视频..."/>
              <UniformGrid Columns="3" Margin="0,10,0,0">
                <Button x:Name="BtnClear" Style="{StaticResource BtnGhost}" Content="恢复极光" Margin="0,0,5,0"/>
                <Button x:Name="BtnOpen"  Style="{StaticResource BtnGhost}" Content="壁纸文件夹" Margin="5,0"/>
                <Button x:Name="BtnRestart" Style="{StaticResource BtnGhost}" Content="重启应用" Margin="5,0,0,0"/>
              </UniformGrid>
              <Grid Margin="2,12,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="界面不透明度" Foreground="#8A90A0" FontSize="11.5"
                           VerticalAlignment="Center" Margin="0,0,10,0"/>
                <Slider Grid.Column="1" x:Name="UiAlpha" Minimum="0" Maximum="100" Value="55"
                        VerticalAlignment="Center" IsMoveToPointEnabled="True"
                        IsSnapToTickEnabled="True" TickFrequency="5"/>
                <TextBlock Grid.Column="2" x:Name="UiAlphaText" Text="55%" Foreground="#C9CEDA" FontSize="11.5"
                           Width="38" TextAlignment="Right" VerticalAlignment="Center"/>
              </Grid>
              <TextBlock x:Name="StatusText" Foreground="#8A90A0" FontSize="12" Margin="2,10,0,0" TextWrapping="Wrap"/>
              <TextBlock Foreground="#4E5464" FontSize="11" Margin="2,6,0,0"
                         Text="操作只作用于当前查看的应用 · 支持拖入文件 · 新壁纸自动存入壁纸库"/>
            </StackPanel>
          </Grid>

          <!-- 页 2：壁纸库（批量 / 同步管理 + 轮换） -->
          <Grid x:Name="PageLib" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#101218" CornerRadius="10" Padding="14,9" Margin="0,0,0,8"
                    BorderBrush="#242835" BorderThickness="1">
              <!-- 芯片独占一行（WrapPanel 在横向 StackPanel 里会拿到无限宽度，
                   永不换行、直接溢出窗口，后面的应用根本点不到） -->
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="应用" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
                  <TextBlock Grid.Column="1" Foreground="#4E5464" FontSize="10.5" VerticalAlignment="Center"
                             TextTrimming="CharacterEllipsis" Text="勾选作为壁纸库批量操作的目标应用"/>
                  <CheckBox Grid.Column="2" x:Name="SwSync" Style="{StaticResource Switch}" Content="同步设置"
                            VerticalAlignment="Center" ToolTip="开：一套壁纸与轮换设置应用到所有勾选的应用；关：只改当前勾选的应用"/>
                </Grid>
                <WrapPanel Grid.Row="1" x:Name="AppChips" Margin="0,8,0,0" VerticalAlignment="Top"/>
              </Grid>
            </Border>
            <Border Grid.Row="1" Background="#101218" CornerRadius="10" Padding="14,10" Margin="0,0,0,8"
                    BorderBrush="#242835" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                  <TextBlock Text="自动更换壁纸" Foreground="#ECECEC" FontSize="12.5"/>
                  <TextBlock x:Name="RotHint" Text="开启后每次打开应用自动换用下面勾选的下一张壁纸" Foreground="#6B7183" FontSize="10.5" Margin="0,2,0,0"/>
                </StackPanel>
                <CheckBox Grid.Column="1" x:Name="SwRotate" Style="{StaticResource Switch}" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <StackPanel Grid.Row="2" x:Name="IntervalRow" Orientation="Horizontal" Margin="4,0,0,10" Visibility="Collapsed">
              <TextBlock Text="换片间隔" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <RadioButton x:Name="Iv0"  Style="{StaticResource IvPill}" GroupName="iv" Content="仅打开时" Tag="0" IsChecked="True"/>
              <RadioButton x:Name="Iv1"  Style="{StaticResource IvPill}" GroupName="iv" Content="1分钟" Tag="1"/>
              <RadioButton x:Name="Iv5"  Style="{StaticResource IvPill}" GroupName="iv" Content="5分钟" Tag="5"/>
              <RadioButton x:Name="Iv15" Style="{StaticResource IvPill}" GroupName="iv" Content="15分钟" Tag="15"/>
              <RadioButton x:Name="Iv30" Style="{StaticResource IvPill}" GroupName="iv" Content="30分钟" Tag="30"/>
              <RadioButton x:Name="Iv60" Style="{StaticResource IvPill}" GroupName="iv" Content="1小时" Tag="60"/>
            </StackPanel>
            <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <WrapPanel x:Name="LibPanel"/>
                <TextBlock x:Name="LibEmpty" Text="壁纸库为空 · 在「当前壁纸」页选择或拖入文件即可收藏"
                           Foreground="#6B7183" FontSize="12" HorizontalAlignment="Center" Margin="0,40,0,0"/>
              </StackPanel>
            </ScrollViewer>
            <TextBlock Grid.Row="4" Foreground="#4E5464" FontSize="10.5" Margin="2,8,0,0"
                       Text="点「应用」换壁纸（同步模式作用于所有勾选应用）· 勾「轮换」参与自动更换 · 视频悬停即预览"/>
          </Grid>

          <!-- 页 3：AI 生成（豆包 Seedream 文生图，火山方舟 images/generations） -->
          <Grid x:Name="PageAi" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#101218" CornerRadius="10" Padding="14,9" Margin="0,0,0,8"
                    BorderBrush="#242835" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="火山方舟 API Key" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <TextBox Grid.Column="1" x:Name="AiKey" Height="28" VerticalContentAlignment="Center"
                         Background="#0B0D12" Foreground="#ECECEC" BorderBrush="#242835" CaretBrush="#ECECEC"
                         Padding="8,0" FontSize="12"
                         ToolTip="获取：火山引擎控制台 → 火山方舟 → API Key 管理。需在方舟开通豆包·图像生成（Seedream）模型。"/>
                <Button Grid.Column="2" x:Name="BtnAiKeySave" Style="{StaticResource BtnMini}" Content="保存 Key"
                        Height="28" Padding="12,0" Margin="8,0,0,0"/>
              </Grid>
            </Border>
            <Border Grid.Row="1" CornerRadius="10" Background="#0B0D12" BorderBrush="#242835" BorderThickness="1" Margin="0,0,0,8">
              <Grid>
                <TextBox x:Name="AiPrompt" AcceptsReturn="True" TextWrapping="Wrap" FontSize="13"
                         Foreground="#ECECEC" Background="Transparent" BorderThickness="0" CaretBrush="#ECECEC"
                         Padding="12,10" Height="82" VerticalScrollBarVisibility="Auto"/>
                <TextBlock x:Name="AiPromptHint" Foreground="#5B6172" FontSize="13" Margin="14,11,14,0"
                           IsHitTestVisible="False" TextTrimming="CharacterEllipsis"
                           Text="描述你想要的壁纸… 例：暮色雪山与湖泊，金色晚霞倒映水面，电影感构图，超高清细节（Ctrl+Enter 快速生成）"/>
              </Grid>
            </Border>
            <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="2,0,0,8">
              <TextBlock Text="模型" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <ComboBox x:Name="AiModel" Width="228" Height="28" IsEditable="True" FontSize="11.5"
                        VerticalContentAlignment="Center"
                        ToolTip="火山方舟模型 ID（可直接编辑）。新模型发布后粘贴新模型 ID 或推理接入点 ep-xxx 即可。"/>
              <TextBlock Text="张数" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="14,0,8,0"/>
              <RadioButton x:Name="AiCnt1" Style="{StaticResource IvPill}" GroupName="aicnt" Content="1 张" Tag="1" IsChecked="True"/>
              <RadioButton x:Name="AiCnt2" Style="{StaticResource IvPill}" GroupName="aicnt" Content="2 张" Tag="2"/>
              <RadioButton x:Name="AiCnt4" Style="{StaticResource IvPill}" GroupName="aicnt" Content="4 张" Tag="4"/>
            </StackPanel>
            <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="2,0,0,10">
              <TextBlock Text="尺寸" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <RadioButton x:Name="AiSize2K" Style="{StaticResource IvPill}" GroupName="aisize" Content="2K 自适应" Tag="2K" IsChecked="True"
                           ToolTip="模型按提示词内容自适应构图，约 2K 分辨率"/>
              <RadioButton x:Name="AiSize4K" Style="{StaticResource IvPill}" GroupName="aisize" Content="4K 高清" Tag="4K"/>
              <RadioButton x:Name="AiSizeW" Style="{StaticResource IvPill}" GroupName="aisize" Content="2560×1600" Tag="2560x1600"
                           ToolTip="与本机屏幕同比例（16:10）的固定尺寸"/>
              <RadioButton x:Name="AiSizeHD" Style="{StaticResource IvPill}" GroupName="aisize" Content="2048×1152" Tag="2048x1152"
                           ToolTip="16:9 固定尺寸"/>
            </StackPanel>
            <StackPanel Grid.Row="4" Margin="0,0,0,4">
              <Button x:Name="BtnAiGen" Style="{StaticResource BtnPrimary}" Content="✨ 生成壁纸"/>
              <TextBlock x:Name="AiStatus" Foreground="#8A90A0" FontSize="12" Margin="2,8,0,0" TextWrapping="Wrap"/>
            </StackPanel>
            <ScrollViewer Grid.Row="5" VerticalScrollBarVisibility="Auto" Margin="0,4,0,0">
              <WrapPanel x:Name="AiPanel"/>
            </ScrollViewer>
            <TextBlock Grid.Row="6" Foreground="#4E5464" FontSize="10.5" Margin="2,8,0,0"
                       TextWrapping="Wrap"
                       Text="生成结果自动存入共享壁纸库（ai- 开头）· 点卡片「应用」立即换上（同步模式作用于所有勾选应用）· API Key 仅保存在本机 doubao.json"/>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# 任务栏 / 窗口图标（不设的话运行时显示 PowerShell 默认图标）
$icoPath = Join-Path $PSScriptRoot 'app.ico'
if (Test-Path $icoPath) {
    $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $icoPath))
    # WPF 不主动发 WM_SETICON，任务栏会退回 powershell.exe 图标，句柄创建时手动推一次
    Add-Type -Namespace WpNative -Name IconPush -MemberDefinition `
        '[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);' `
        -ReferencedAssemblies System.Windows.Forms
    $script:pickerIcon = New-Object System.Drawing.Icon $icoPath
    $window.Add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        [WpNative.IconPush]::SendMessage($hwnd, 0x80, [IntPtr]1, $script:pickerIcon.Handle) | Out-Null
        [WpNative.IconPush]::SendMessage($hwnd, 0x80, [IntPtr]0, $script:pickerIcon.Handle) | Out-Null
    })
}

function Ctrl($name) { $window.FindName($name) }
$preview      = Ctrl 'Preview'
$previewVideo = Ctrl 'PreviewVideo'
$previewEmpty = Ctrl 'PreviewEmpty'
$emptyText    = Ctrl 'EmptyText'
$badge        = Ctrl 'Badge'
$badgeText    = Ctrl 'BadgeText'
$statusText   = Ctrl 'StatusText'
$previewArea  = Ctrl 'PreviewArea'
$libPanel     = Ctrl 'LibPanel'
$libEmpty     = Ctrl 'LibEmpty'
$swRotate     = Ctrl 'SwRotate'
$swSync       = Ctrl 'SwSync'
$uiAlphaText  = Ctrl 'UiAlphaText'
$uiSlider     = Ctrl 'UiAlpha'

$previewVideo.Add_MediaEnded({
    $previewVideo.Position = [TimeSpan]::Zero
    $previewVideo.Play()
})

# ── 应用芯片（壁纸库页：批量/同步的目标应用） ────────────
$script:ChipMap = @{}
foreach ($a in $Apps) {
    $chip = New-Object System.Windows.Controls.Primitives.ToggleButton
    $chip.Content = $a.Name
    $chip.Style = $window.Resources['AppChip']
    $chip.Tag = $a.Name
    $chip.Add_Click({
        $name = $this.Tag
        if ($script:Sync) {
            # 同步模式：多选；至少保留一个
            if ($this.IsChecked) {
                if (-not ($script:Checked -contains $name)) { $script:Checked += $name }
            } else {
                if ($script:Checked.Count -gt 1) {
                    $script:Checked = @($script:Checked | Where-Object { $_ -ne $name })
                } else { $this.IsChecked = $true; return }
            }
        } else {
            # 独立模式：单选（当前操作对象）
            if (-not $this.IsChecked) { $this.IsChecked = $true; return }
            $script:Active = $name
            $script:Checked = @($name)
        }
        $hub = Get-HubConfig
        $hub.checked = @($script:Checked)
        $hub.sync = $script:Sync
        Save-HubConfig $hub
        Update-ChipVisual
        Update-Library
        Update-NowView
    })
    (Ctrl 'AppChips').Children.Add($chip) | Out-Null
    $script:ChipMap[$a.Name] = $chip
}
function Update-ChipVisual {
    foreach ($name in $script:ChipMap.Keys) {
        $chip = $script:ChipMap[$name]
        if ($script:Sync) { $chip.IsChecked = ($script:Checked -contains $name) }
        else { $chip.IsChecked = ($name -eq $script:Active) }
    }
}

# ── 工具函数 ─────────────────────────────────────────────
$script:ImgCache = @{}
function Get-ImageSource([string]$path) {
    # 带文件签名键的内存缓存：重建库网格时不再重复解码大图；Freeze 后渲染开销更低
    $fi = Get-Item $path
    $key = 'i|' + $fi.FullName + '|' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks
    if ($script:ImgCache.ContainsKey($key)) { return $script:ImgCache[$key] }
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'
    $bi.UriSource = [Uri]$fi.FullName
    $bi.EndInit()
    if ($bi.CanFreeze) { $bi.Freeze() }
    if ($script:ImgCache.Count -gt 80) { $script:ImgCache.Clear() }
    $script:ImgCache[$key] = $bi
    return $bi
}

function Get-ThumbSource([string]$path) {
    $fi = Get-Item $path
    $key = 't|' + $fi.FullName + '|' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks
    if ($script:ImgCache.ContainsKey($key)) { return $script:ImgCache[$key] }
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'
    $thumb = [ShellThumb]::GetThumb($path, 480, 270)
    $ms = New-Object IO.MemoryStream
    $thumb.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $thumb.Dispose()
    $bi.StreamSource = $ms
    $bi.EndInit()
    if ($bi.CanFreeze) { $bi.Freeze() }
    if ($script:ImgCache.Count -gt 80) { $script:ImgCache.Clear() }
    $script:ImgCache[$key] = $bi
    return $bi
}

function Stop-PreviewVideo {
    $previewVideo.Stop()
    $previewVideo.Source = $null
    $previewVideo.Visibility = 'Collapsed'
}

function Show-Empty([string]$appName) {
    $preview.Source = $null
    $preview.Visibility = 'Collapsed'
    Stop-PreviewVideo
    $previewEmpty.Visibility = 'Visible'
    $emptyText.Text = if ($AppMap[$appName].Terminal) { "$appName 未设置壁纸 · Windows Terminal 默认纯色背景" } else { "$appName 未设置壁纸 · 显示内置动态极光" }
    $badge.Visibility = 'Collapsed'
}

function Show-NowMedia([string]$f) {
    $previewEmpty.Visibility = 'Collapsed'
    $badge.Visibility = 'Visible'
    if ($f -match '\.(mp4|webm)$') {
        $preview.Source = $null
        $preview.Visibility = 'Collapsed'
        $previewVideo.Visibility = 'Visible'
        $previewVideo.Source = [Uri]$f
        $previewVideo.Play()
    } else {
        Stop-PreviewVideo
        $preview.Source = Get-ImageSource $f
        $preview.Visibility = 'Visible'
    }
}

# ── 「当前壁纸」页：按应用单独显示真实状态 ────────────────
function Update-NowView {
    $app = $script:NowApp
    if (-not $app -or -not $AppMap.ContainsKey($app)) { return }
    Stop-PreviewVideo
    $preview.Source = $null
    $rot1 = Find-RotateFirst $app
    if ($rot1) {
        $rc = Get-AppRotCfg $app
        $n = @(Get-ChildItem (Join-Path $AppMap[$app].Dir 'rotate') -Filter 'rotate-*' -File -ErrorAction SilentlyContinue).Count
        $iv = $rc.interval
        $ivText = if ($iv -gt 0) { "每 $iv 分钟" } else { '打开应用时' }
        $badgeText.Text = "$app · 自动轮换中 $n 张 · $ivText 换一张"
        Show-NowMedia $rot1
        $statusText.Text = "$app 正在自动轮换壁纸（预览为轮换集第 1 张，应用内显示其中一张）。本页操作只作用于 $app。"
        return
    }
    $f = Get-WallpaperFile $app
    if (-not $f) { Show-Empty $app; return }
    $badgeText.Text = "$app · {0}  ({1:N1} MB)" -f (Split-Path $f -Leaf), ((Get-Item $f).Length / 1MB)
    Show-NowMedia $f
}

# ── Windows Terminal 壁纸（PowerShell / CMD 目标）─────────
# WT 的 settings.json 是 JSONC（允许注释）；写回后 WT 监听改动自动热加载，已开窗口即时生效。
function ConvertFrom-JsonLoose([string]$text) {
    try { return ConvertFrom-Json $text } catch {}
    # 带注释时逐字符剥离（字符串内部的 // 与 /* 不受影响），剥离结果再进标准解析
    $sb = New-Object Text.StringBuilder
    $inStr = $false; $esc = $false
    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($inStr) {
            [void]$sb.Append($ch)
            if ($esc) { $esc = $false } elseif ($ch -eq '\') { $esc = $true } elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"') { $inStr = $true; [void]$sb.Append($ch); continue }
        if ($ch -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '/') {
            while ($i -lt $text.Length -and $text[$i] -ne "`n") { $i++ }
            [void]$sb.Append("`n"); continue
        }
        if ($ch -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '*') {
            $i += 2
            while ($i + 1 -lt $text.Length -and -not ($text[$i] -eq '*' -and $text[$i + 1] -eq '/')) { $i++ }
            $i++; continue
        }
        [void]$sb.Append($ch)
    }
    return ConvertFrom-Json $sb.ToString()
}

function Get-WtSettings {
    if (-not $wtSettingsPath) { return $null }
    try { return ConvertFrom-JsonLoose ([IO.File]::ReadAllText($wtSettingsPath)) } catch { return $null }
}

function Save-WtSettings($root) {
    if (-not $wtSettingsPath) { return }
    # 保留原文件的 BOM 状态；PS 5.1 ConvertTo-Json 的输出是合法 JSON，WT 热加载无压力
    $hasBom = $false
    try {
        $bytes = [IO.File]::ReadAllBytes($wtSettingsPath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    } catch {}
    [IO.File]::WriteAllText($wtSettingsPath, ($root | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($hasBom))
}

# 定位目标 profile：guid 精确匹配 → name 锚定回退；都没有则在 profiles.list 追加最小条目
# （WT 会把 list 条目与内置动态 profile 按 guid 合并，所以只写 guid + 壁纸键即可生效）
function Get-WtProfile($root, $app) {
    $profs = $root.PSObject.Properties['profiles']
    if (-not $profs -or $profs.Value -is [array]) {
        $root | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{
            defaults = [pscustomobject]@{}; list = if ($profs) { @($profs.Value) } else { @() } }) -Force
        $profs = $root.PSObject.Properties['profiles']
    }
    $list = $profs.Value.PSObject.Properties['list']
    if (-not $list) {
        $profs.Value | Add-Member -NotePropertyName list -NotePropertyValue @() -Force
        $list = $profs.Value.PSObject.Properties['list']
    }
    foreach ($p in @($list.Value)) { if ($p -and $p.PSObject.Properties['guid'] -and $p.guid -ieq $app.WtGuid) { return $p } }
    foreach ($p in @($list.Value)) {
        if ($p -and $p.PSObject.Properties['name'] -and $p.name -imatch $app.WtNameMatch) { return $p }
    }
    $entry = [pscustomobject]@{ guid = $app.WtGuid; name = $app.Name }
    $profs.Value.list = @($list.Value) + $entry
    return $entry
}

# 写/清 background 三键。⚠️ 键名必须是 backgroundImage——WT 1.24 已不认旧名 backgroundImagePath
# （实测解析正常但静默不渲染）。三键同时写两处：profile 本体（wt -p / WT 下拉按 profile 开的标签）
# + profiles.defaults（开始菜单直接打开 cmd/powershell 走的「控制台接管」标签不绑定 profile，只继承 defaults）。
# alpha 是「界面不透明度」滑杆值（与其他应用同一语义：越高界面越实），
# 终端映射为 backgroundImageOpacity = 1 - alpha。imgPath 为 $null 时整组移除
# （defaults 仅在当前正指向该应用壁纸时才清，避免误删另一终端目标写入的值）。
function Set-WtBackground([string]$appName, $imgPath, [double]$alpha) {
    $root = Get-WtSettings
    if (-not $root) { return '无法解析 Windows Terminal settings.json（文件损坏？）' }
    try {
        $p = Get-WtProfile $root $AppMap[$appName]
        $profs = $root.PSObject.Properties['profiles']
        if (-not $profs.Value.PSObject.Properties['defaults']) {
            $profs.Value | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $defaults = $profs.Value.defaults
        $keys = @('backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode')
        foreach ($old in @('backgroundImagePath')) {
            foreach ($tgt in @($p, $defaults)) {
                $m = $tgt.PSObject.Properties[$old]; if ($m) { $tgt.PSObject.Properties.Remove($old) }
            }
        }
        if ($imgPath) {
            foreach ($tgt in @($p, $defaults)) {
                foreach ($kv in @(@('backgroundImage', [string]$imgPath),
                                  @('backgroundImageOpacity', [math]::Round((1 - $alpha), 2)),
                                  @('backgroundImageStretchMode', 'uniformToFill'))) {
                    if ($tgt.PSObject.Properties[$kv[0]]) { $tgt.PSObject.Properties[$kv[0]].Value = $kv[1] }
                    else { $tgt | Add-Member -NotePropertyName $kv[0] -NotePropertyValue $kv[1] -Force }
                }
            }
        } else {
            foreach ($k in $keys) { $m = $p.PSObject.Properties[$k]; if ($m) { $p.PSObject.Properties.Remove($k) } }
            $dm = $defaults.PSObject.Properties['backgroundImage']
            if ($dm -and $dm.Value -and ([string]$dm.Value).StartsWith($AppMap[$appName].Dir, [StringComparison]::OrdinalIgnoreCase)) {
                foreach ($k in $keys) { $m = $defaults.PSObject.Properties[$k]; if ($m) { $defaults.PSObject.Properties.Remove($k) } }
            }
        }
        Save-WtSettings $root
    } catch { return '写入 Windows Terminal 设置失败：' + $_.Exception.Message }
    return $null
}

# 终端目标的壁纸落盘：位图类直接硬链接进应用目录；视频/webp 用 ffmpeg 抽帧转 png。
# 返回 $null=成功，字符串=失败原因（调用方展示）。失败时不动现有壁纸。
function Set-TerminalWallpaper([string]$appName, [string]$src) {
    if (-not $wtSettingsPath) { return '未找到 Windows Terminal，无法设置终端壁纸' }
    $dir = $AppMap[$appName].Dir
    $ext = [IO.Path]::GetExtension($src).ToLower(); if ($ext -eq '.jpeg') { $ext = '.jpg' }
    $final = $src
    if ($ext -notin @('.png', '.jpg', '.bmp', '.gif')) {
        # WT 不支持视频/webp：抽第 1 秒帧（webp 直接转）成 png；gif 动图 WT 原生支持无需转
        $ff = Join-Path $hub 'bin\ffmpeg.exe'
        if (-not (Test-Path $ff)) { return '终端壁纸仅支持图片/GIF：把视频转成 png 需要 ffmpeg（~\.ai-wallpaper\bin\），未找到' }
        $tmp = Join-Path $env:TEMP ('zwp-term-' + [guid]::NewGuid().ToString('N') + '.png')
        $ffArgs = @('-hide_banner', '-loglevel', 'error', '-y')
        if ($ext -in @('.mp4', '.webm')) { $ffArgs += @('-ss', '1') }
        $ffArgs += @('-i', $src, '-frames:v', '1', $tmp)
        & $ff @ffArgs 2>$null
        if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -eq 0) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            return '视频抽帧失败，无法生成终端壁纸（png）'
        }
        $final = $tmp; $ext = '.png'
    }
    # 与其他应用同款落盘规则：先清旧 wallpaper.*（被占用则改名腾路径），再硬链接、失败回退复制
    Get-ChildItem -Path (Join-Path $dir 'wallpaper.*') -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {
            try { Move-Item $_.FullName ($_.FullName + '.zwp-old') -Force -ErrorAction Stop } catch {}
        }
    }
    $dst = Join-Path $dir ('wallpaper' + $ext)
    if ($final -ne $dst) {
        $linked = $false
        try { New-Item -ItemType HardLink -Path $dst -Target $final -ErrorAction Stop | Out-Null; $linked = $true } catch {}
        if (-not $linked) { Copy-Item $final $dst -Force }
    }
    if ($final -ne $src) { Remove-Item $final -Force -ErrorAction SilentlyContinue }
    return (Set-WtBackground $appName $dst (Get-UiAlpha $appName))
}

# ── 壁纸写入（单应用直控） ────────────────────────────────
function Set-AppStaticWallpaper([string]$appName, [string]$src) {
    if ($AppMap[$appName].Terminal) {
        # 终端目标不走通用落盘+refresh 标记链路：转换后直接写 WT profile（热加载即时生效）
        $err = Set-TerminalWallpaper $appName $src
        if ($err) { $script:WpError = $err }
        return
    }
    $dir = $AppMap[$appName].Dir
    # 旧壁纸可能是被运行中应用占用的硬链接：删不掉就改名腾出路径。
    # 绝不能对着现存路径原地覆写——硬链接会把新内容写进中心库文件本身，污染所有应用
    Get-ChildItem -Path (Join-Path $dir 'wallpaper.*') -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {
            try { Move-Item $_.FullName ($_.FullName + '.zwp-old') -Force -ErrorAction Stop } catch {}
        }
    }
    $dst = Join-Path $dir ('wallpaper' + [IO.Path]::GetExtension($src))
    # 硬链接到中心库文件：零重复磁盘空间；跨卷/系统不支持时回退为复制
    $linked = $false
    if (-not (Test-Path $dst)) {
        try { New-Item -ItemType HardLink -Path $dst -Target $src -ErrorAction Stop | Out-Null; $linked = $true } catch {}
    }
    if (-not $linked) { Copy-Item $src $dst -Force }
    # 应用端探测到 rotate-1.* 就会忽略静态壁纸：单应用设置壁纸时清掉该应用的轮换集，保证立即生效
    Get-ChildItem -Path (Join-Path $dir 'rotate') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'refresh-*' } | Remove-Item -Force
    $c = Get-AppConfig $appName
    if ($c.rotation) { $c.rotation = $false; Save-AppConfig $appName $c }
    Touch-LiveMarker $appName
}

function Add-LibEntry([string]$libName, [string]$type, [string]$appName) {
    if (-not $libName) { return }
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $h = Get-HubConfig
    if (-not @($h.items | Where-Object { $_.file -eq $libName })) {
        $h.items = @($h.items) + [pscustomobject]@{ file = $libName; type = $type; rotate = $false; added = $now }
        Save-HubConfig $h
    }
    # 同写入该应用配置，保证独立模式下「壁纸库」页也能看到
    $c = Get-AppConfig $appName
    if (-not @($c.items | Where-Object { $_ -ne $null -and $_.file -eq $libName })) {
        $c.items = @($c.items) + [pscustomobject]@{ file = $libName; type = $type; rotate = $false; added = $now }
        Save-AppConfig $appName $c
    }
}

# 视频归一化：压到 ≤1080p/30fps H.264，体积与解码负载同步大降（新导入即时受益）。
# ffmpeg 位于 ~\.ai-wallpaper\bin\（不在则原样返回，导入照常只是不压缩）
function Convert-ToNormVideo([string]$path) {
    $ff = Join-Path $hub 'bin\ffmpeg.exe'
    if (-not (Test-Path $ff)) { return $path }
    $tmp = Join-Path $hubLib ([IO.Path]::GetFileNameWithoutExtension($path) + '.norm.mp4')
    & $ff -hide_banner -loglevel error -y -i $path -vf "scale='min(1920,iw)':-2,fps=30" -c:v libx264 -crf 25 -preset veryfast -pix_fmt yuv420p -movflags +faststart -an $tmp 2>$null
    if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0 -and ((Get-Item $tmp).Length -lt (Get-Item $path).Length)) {
        if ($path -ne $tmp) { Remove-Item $path -Force -ErrorAction SilentlyContinue }
        return $tmp
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $path
}

function Import-Wallpaper([string]$file, [string]$appName) {
    if (-not (Test-Path $file)) { return }
    $ext = [IO.Path]::GetExtension($file).ToLower()
    if ($ext -eq '.jpeg') { $ext = '.jpg' }
    if ($ext -notin @('.mp4', '.webm', '.gif', '.webp', '.png', '.jpg')) {
        $statusText.Text = '不支持的文件类型：' + $ext
        return
    }
    $type = if ($ext -in @('.mp4', '.webm')) { 'video' } else { 'image' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $libName = "$stamp$ext"
    Copy-Item -Path $file -Destination (Join-Path $hubLib $libName) -Force
    $libPath = Join-Path $hubLib $libName
    if ($type -eq 'video') {
        $statusText.Text = '正在归一化视频（≤1080p/30fps，时长取决于视频大小）…'
        $libPath = Convert-ToNormVideo $libPath
    }
    Add-LibEntry ([IO.Path]::GetFileName($libPath)) $type $appName
    $script:WpError = $null
    Set-AppStaticWallpaper $appName $libPath
    Update-NowView
    if ($script:WpError) {
        $statusText.Text = "已收藏到壁纸库，但 $appName 设置壁纸失败：" + $script:WpError
        $script:WpError = $null
        Update-Library
        return
    }
    $statusText.Text = "已为 $appName 设置并收藏：$([IO.Path]::GetFileName($libPath))`n$([math]::Round((Get-Item $libPath).Length/1MB,1)) MB · 仅作用于 $appName；要批量应用到其他应用请到「壁纸库」页点「应用」"
    Update-Library
}

function Apply-LibraryItem($item) {
    $src = Join-Path $hubLib $item.file
    if (-not (Test-Path $src)) { return }
    $cfg = Get-Cfg
    $wasRotating = $cfg.rotation
    $targets = @(Get-Targets)
    $script:WpError = $null
    foreach ($name in $targets) {
        # 拷贝壁纸 + 清轮换残留 + 写 refresh 标记 → 运行中的应用 5 秒内热切换
        Set-AppStaticWallpaper $name $src
    }
    $msg = "已应用到 $(TargetsText)：$($item.file)"
    if ($script:WpError) {
        $msg += "`n注意：终端目标有失败 —— " + $script:WpError
        $script:WpError = $null
    }
    if ($wasRotating) {
        # 应用 = 固定这张，暂停轮换，保证选择器与应用显示一致
        $cfg.rotation = $false
        Commit-Cfg $cfg
        $msg += "`n（原轮换已暂停，开关可随时重新打开）"
    }
    # 跳到「当前壁纸」页并查看目标应用之一，立刻看到同步结果
    if (@($targets) -notcontains $script:NowApp) {
        $script:NowApp = $targets[0]
        (Ctrl 'NowAppCombo').SelectedItem = $script:NowComboMap[$script:NowApp]
    }
    (Ctrl 'TabNow').IsChecked = $true
    Update-NowView
    $statusText.Text = $msg
}

# ── 库卡片悬停播放：垫底缩略图 + 延时起播 + 全局单路解码 ──
# 缩略图永远垫底，视频层首帧就绪（MediaOpened）才显示 → 悬停不再黑屏闪一下；
# 悬停 320ms 后才起播（快速扫过不触发解码），同一时刻只允许一路解码 → 不卡。
$script:HoverPending = $null
$script:HoverCurrent = $null
function Stop-HoverVideo {
    if ($script:HoverTimer -ne $null) { $script:HoverTimer.Stop() }
    $script:HoverPending = $null
    $h = $script:HoverCurrent
    $script:HoverCurrent = $null
    if ($h -ne $null -and $h.media -ne $null) {
        try { $h.media.Stop(); $h.media.Close() } catch {}
        $h.media.Source = $null
        $h.media.Visibility = 'Hidden'
        if ($h.img -ne $null) { $h.img.Visibility = 'Visible' }
    }
}
$script:HoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:HoverTimer.Interval = [TimeSpan]::FromMilliseconds(320)
$script:HoverTimer.Add_Tick({
    $script:HoverTimer.Stop()
    $h = $script:HoverPending
    $script:HoverPending = $null
    if ($h -eq $null -or $script:HoverCurrent -eq $h) { return }
    Stop-HoverVideo
    $script:HoverCurrent = $h
    try { $h.media.Source = [Uri]$h.src; $h.media.Play() } catch {}
})

# ── 壁纸库网格 ───────────────────────────────────────────
function New-MiniButton([string]$text, $tag) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text
    $b.Tag = $tag
    $b.Style = $window.Resources['BtnMini']
    return $b
}

function Update-Hints {
    (Ctrl 'BtnRestart').Content = if ($AppMap[$script:NowApp].Terminal) { '热生效 · 免重启' } else { "重启 $script:NowApp" }
    # 滑杆跟随当前查看应用的设置（程序化回填不打到写盘定时器）
    try {
        $want = (Get-UiAlpha $script:NowApp) * 100
        if ([math]::Abs($uiSlider.Value - $want) -gt 0.5) {
            $script:SliderSync = $true
            $uiSlider.Value = $want
            $script:SliderSync = $null
        }
    } catch {}
}

function Update-Library {
    Stop-HoverVideo
    $cfg = Get-Cfg
    $swRotate.IsChecked = $cfg.rotation
    $vis = 'Collapsed'
    if ($cfg.rotation) { $vis = 'Visible' }
    (Ctrl 'IntervalRow').Visibility = $vis
    $iv = $cfg.interval
    foreach ($pair in @(@('Iv0', 0), @('Iv1', 1), @('Iv5', 5), @('Iv15', 15), @('Iv30', 30), @('Iv60', 60))) {
        (Ctrl $pair[0]).IsChecked = ($pair[1] -eq $iv)
    }
    $n = @($cfg.items | Where-Object { $_.rotate }).Count
    $who = TargetsText
    $hint = "开启后每次打开 $who 自动换用下面勾选的下一张壁纸"
    if ($cfg.rotation) {
        $hint = "已选 $n 张 · 每次打开 $who 自动换用下一张"
        if ($iv -gt 0) { $hint += " · 每 $iv 分钟再换一次" }
    }
    (Ctrl 'RotHint').Text = $hint

    $libPanel.Children.Clear()
    $items = @($cfg.items)
    $emptyVis = 'Collapsed'
    if ($items.Count -eq 0) { $emptyVis = 'Visible' }
    $libEmpty.Visibility = $emptyVis

    foreach ($it in $items) {
        $src = Join-Path $hubLib $it.file
        if (-not (Test-Path $src)) { continue }
        $isVideo = $it.file -match '\.(mp4|webm)$'
        $thumbErr = ''

        $card = New-Object Windows.Controls.Border
        $card.Width = 150
        $card.CornerRadius = New-Object Windows.CornerRadius 8
        $card.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#20242E')
        $card.Margin = New-Object Windows.Thickness 0, 0, 8, 8

        $panel = New-Object Windows.Controls.Grid
        $r0 = New-Object Windows.Controls.RowDefinition; $r0.Height = New-Object Windows.GridLength 84
        $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = [Windows.GridLength]::Auto
        $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = [Windows.GridLength]::Auto
        $panel.RowDefinitions.Add($r0); $panel.RowDefinitions.Add($r1); $panel.RowDefinitions.Add($r2)

        # 媒体区：视频 → 缩略图垫底 + 悬停延时播放（全局单路解码）；图片 → Image
        $clipBorder = New-Object Windows.Controls.Border
        $clipBorder.CornerRadius = New-Object Windows.CornerRadius 8, 8, 0, 0
        $clipBorder.ClipToBounds = $true
        $clipBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#0B0D12')
        if ($isVideo) {
            $img = New-Object Windows.Controls.Image
            $img.Stretch = 'Uniform'
            try { $img.Source = Get-ThumbSource $src } catch { $thumbErr = $_.Exception.Message }
            if ($img.Source -eq $null) { $thumbErr = 'SOURCE_NULL' }
            if ($img.Source -ne $null -and $img.Source.PixelWidth -lt 10) { $thumbErr = 'TINY_' + $img.Source.PixelWidth }

            # 视频层先隐藏，MediaOpened（首帧就绪）才显示 → 不会黑屏
            $me = New-Object Windows.Controls.MediaElement
            $me.Stretch = 'Uniform'
            $me.IsMuted = $true
            $me.Volume = 0
            $me.LoadedBehavior = 'Manual'
            $me.UnloadedBehavior = 'Close'
            $me.Visibility = 'Hidden'
            $me.Add_MediaOpened({
                $h = $script:HoverCurrent
                if ($h -ne $null -and $h.media -ne $null) {
                    $h.media.Visibility = 'Visible'
                    $h.img.Visibility = 'Hidden'
                }
            })
            $me.Add_MediaEnded({
                if ($this.Source -ne $null) { $this.Position = [TimeSpan]::Zero; $this.Play() }
            })

            $vidGrid = New-Object Windows.Controls.Grid
            $vidGrid.Children.Add($img) | Out-Null
            $vidGrid.Children.Add($me) | Out-Null
            $holder = @{ img = $img; media = $me; src = $src }
            $vidGrid.Tag = $holder
            $vidGrid.Add_MouseEnter({
                Stop-HoverVideo
                $script:HoverPending = $this.Tag
                $script:HoverTimer.Start()
            })
            $vidGrid.Add_MouseLeave({ Stop-HoverVideo })
            $clipBorder.Child = $vidGrid
        } else {
            $img = New-Object Windows.Controls.Image
            $img.Stretch = 'UniformToFill'
            try { $img.Source = Get-ImageSource $src } catch {}
            $clipBorder.Child = $img
        }
        [Windows.Controls.Grid]::SetRow($clipBorder, 0)
        $panel.Children.Add($clipBorder) | Out-Null

        # 名称
        $name = New-Object Windows.Controls.TextBlock
        $name.Text = $it.file + $(if ($thumbErr) { ' ⚠' + $thumbErr } else { '' })
        $name.FontSize = 10.5
        $name.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#9CA3AF')
        $name.TextTrimming = 'CharacterEllipsis'
        $name.Margin = New-Object Windows.Thickness 8, 4, 8, 0
        [Windows.Controls.Grid]::SetRow($name, 1)
        $panel.Children.Add($name) | Out-Null

        # 操作行（三等分统一 mini 按钮）
        $ops = New-Object Windows.Controls.Primitives.UniformGrid
        $ops.Columns = 3
        $ops.Margin = New-Object Windows.Thickness 6, 5, 6, 7

        $rotBtn = New-MiniButton '轮换' $it
        if ($it.rotate) {
            $rotBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#3B82F6')
            $rotBtn.Foreground = [Windows.Media.Brushes]::White
        }
        $rotBtn.Margin = New-Object Windows.Thickness 0, 0, 3, 0
        $rotBtn.Add_Click({
            $item = $this.Tag
            $cfg2 = Get-Cfg
            foreach ($e2 in @($cfg2.items)) { if ($e2.file -eq $item.file) { $e2.rotate = (-not [bool]$e2.rotate) } }
            Commit-Cfg $cfg2
            Update-Library
        })
        $ops.Children.Add($rotBtn) | Out-Null

        $useBtn = New-MiniButton '应用' $it
        $useBtn.Margin = New-Object Windows.Thickness 0
        $useBtn.Add_Click({
            $item = $this.Tag
            Apply-LibraryItem $item
        })
        $ops.Children.Add($useBtn) | Out-Null

        $delBtn = New-MiniButton '删除' $it
        $delBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#F87171')
        $delBtn.Margin = New-Object Windows.Thickness 3, 0, 0, 0
        $delBtn.Add_Click({
            $item = $this.Tag
            $cfg2 = Get-Cfg
            $cfg2.items = @($cfg2.items | Where-Object { $_ -ne $null -and $_.file -ne $item.file })
            Commit-Cfg $cfg2
            Remove-Item (Join-Path $hubLib $item.file) -Force -ErrorAction SilentlyContinue
            Update-Library
        })
        $ops.Children.Add($delBtn) | Out-Null

        [Windows.Controls.Grid]::SetRow($ops, 2)
        $panel.Children.Add($ops) | Out-Null

        $card.Child = $panel
        $libPanel.Children.Add($card) | Out-Null
    }
}

# ── 界面不透明度滑杆（作用于当前查看的应用） ─────────────
function Get-UiAlpha([string]$appName) {
    if ($AppMap[$appName].Terminal) {
        # 终端：滑杆值 = 1 - backgroundImageOpacity（存于 WT profile/defaults），未设置过时与其他应用同默认 0.55
        $v = $null
        try {
            $root = Get-WtSettings
            $p = if ($root) { Get-WtProfile $root $AppMap[$appName] } else { $null }
            $src = $p
            if ($src -and -not $src.PSObject.Properties['backgroundImageOpacity'] -and $root -and $root.PSObject.Properties['profiles'] -and $root.profiles.PSObject.Properties['defaults']) {
                # profile 未写时回退读 defaults（控制台接管路径的写入位置）
                $src = $root.profiles.defaults
            }
            if ($src -and $src.PSObject.Properties['backgroundImageOpacity']) { $v = [double]$src.backgroundImageOpacity }
        } catch {}
        if ($null -ne $v) { return [math]::Round((1 - $v), 2) }
        return 0.55
    }
    $css = Join-Path $AppMap[$appName].Dir 'custom.css'
    if (Test-Path $css) {
        try {
            $m = [regex]::Match((Get-Content $css -Raw -Encoding UTF8), '--ocwp-ui-alpha:\s*([0-9.]+)')
            if ($m.Success) { return [double]$m.Groups[1].Value }
        } catch {}
    }
    return 0.55
}

function Set-UiAlpha([double]$v, [string[]]$names) {
    $val = $v.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    $block = @"
/* ocwp-alpha-begin (AI壁纸设置 维护) */
:root, body { --ocwp-ui-alpha: $val !important; }
/* ZCode 当前版本回退（重打补丁后由上面的 --ocwp-ui-alpha 单独驱动） */
:root, body { --color-background: rgba(250,250,250,$val) !important; --color-background-alt: rgba(245,245,245,$val) !important; --color-background-win-alt: rgba(229,229,229,$val) !important; --color-header: rgba(245,245,245,$val) !important; --color-panel: rgba(245,245,245,$val) !important; --color-sidebar: rgba(245,245,245,$val) !important; }
.dark { --color-background: rgba(23,23,23,$val) !important; --color-background-alt: rgba(38,38,38,$val) !important; --color-background-win-alt: rgba(38,38,38,$val) !important; --color-header: rgba(23,23,23,$val) !important; --color-panel: rgba(23,23,23,$val) !important; --color-sidebar: rgba(10,10,10,$val) !important; }
:root, body { --vscode-editor-background: rgba(255,255,255,$val) !important; --vscode-sideBar-background: rgba(255,255,255,$val) !important; --vscode-activityBar-background: rgba(255,255,255,$val) !important; --vscode-titleBar-activeBackground: rgba(255,255,255,$val) !important; --vscode-statusBar-background: rgba(255,255,255,$val) !important; --vscode-panel-background: rgba(255,255,255,$val) !important; --wb-bg-primary: rgba(255,255,255,$val) !important; --wb-home-bg-primary: rgba(255,255,255,$val) !important; --wb-home-bg-secondary: rgba(255,255,255,$val) !important; --wb-main-area-background: rgba(255,255,255,$val) !important; }
body[data-vscode-theme-name*="Dark" i], body[data-vscode-theme-name*="dark"], body[data-vscode-theme-name*="Night" i] { --vscode-editor-background: rgba(30,30,30,$val) !important; --vscode-sideBar-background: rgba(24,24,24,$val) !important; --vscode-titleBar-activeBackground: rgba(30,30,30,$val) !important; --wb-bg-primary: rgba(38,38,38,$val) !important; --wb-home-bg-primary: rgba(31,31,31,$val) !important; --wb-home-bg-secondary: rgba(20,20,20,$val) !important; }
:root, body { --background-base: rgba(248,248,248,$val) !important; --background-weak: rgba(243,243,243,$val) !important; --background-strong: rgba(252,252,252,$val) !important; }
:root[data-color-scheme="dark"] { --background-base: rgba(16,16,16,$val) !important; --background-weak: rgba(30,30,30,$val) !important; --background-strong: rgba(18,18,18,$val) !important; }
/* ocwp-alpha-end */
"@
    foreach ($name in $names) {
        if ($AppMap[$name].Terminal) {
            # 终端应用：直接写 WT profile 的 backgroundImageOpacity（热加载即时生效），无需 custom.css 与标记
            $err = Set-WtBackground $name (Get-WallpaperFile $name) $v
            if ($err) { $statusText.Text = $err }
            continue
        }
        $css = Join-Path $AppMap[$name].Dir 'custom.css'
        $text = ''
        if (Test-Path $css) { $text = Get-Content $css -Raw -Encoding UTF8 }
        if ($text -match '/\* ocwp-alpha-begin [\s\S]*?/\* ocwp-alpha-end \*/') {
            $text = [regex]::Replace($text, '/\* ocwp-alpha-begin [\s\S]*?/\* ocwp-alpha-end \*/', $block.Replace('$', '$$'))
        } else {
            $text = $text.TrimEnd() + "`r`n`r`n" + $block
        }
        [IO.File]::WriteAllText($css, $text, [Text.UTF8Encoding]::new($true))
        Touch-LiveMarker $name
    }
}

$uiTimer = New-Object Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$uiTimer.Add_Tick({
    $uiTimer.Stop()
    $v = [math]::Round($uiSlider.Value / 100, 2)
    # 透明度永远按应用单独设置：只写当前查看的应用，不做统一覆盖
    $targets = @($script:NowApp)
    Set-UiAlpha $v $targets
    $statusText.Text = "界面不透明度 $([int]$uiSlider.Value)% 已应用到 $($targets -join '、')，几秒内自动生效（无需重启）。"
})
$uiSlider.Add_ValueChanged({
    $uiAlphaText.Text = ([int]$uiSlider.Value).ToString() + '%'
    if ($script:SliderSync) { return }
    $uiTimer.Stop()
    $uiTimer.Start()
})

# ── 事件 ─────────────────────────────────────────────────
(Ctrl 'DragBar').Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
(Ctrl 'BtnClose').Add_Click({ $window.Close() })
(Ctrl 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })

(Ctrl 'TabNow').Add_Checked({
    (Ctrl 'PageNow').Visibility = 'Visible'
    (Ctrl 'PageLib').Visibility = 'Collapsed'
    (Ctrl 'PageAi').Visibility = 'Collapsed'
    $window.Height = 727
    Update-Hints
    Update-NowView
})
(Ctrl 'TabLib').Add_Checked({
    (Ctrl 'PageNow').Visibility = 'Collapsed'
    (Ctrl 'PageLib').Visibility = 'Visible'
    (Ctrl 'PageAi').Visibility = 'Collapsed'
    $window.Height = 770
    Update-Library
})
(Ctrl 'TabAi').Add_Checked({
    (Ctrl 'PageNow').Visibility = 'Collapsed'
    (Ctrl 'PageLib').Visibility = 'Collapsed'
    (Ctrl 'PageAi').Visibility = 'Visible'
    $window.Height = 800
})

(Ctrl 'BtnPick').Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "为 $script:NowApp 选择壁纸"
    $dlg.Filter = '媒体文件|*.mp4;*.webm;*.gif;*.webp;*.png;*.jpg;*.jpeg|视频|*.mp4;*.webm|图片|*.gif;*.webp;*.png;*.jpg;*.jpeg|所有文件|*.*'
    if ($dlg.ShowDialog()) { Import-Wallpaper $dlg.FileName $script:NowApp }
})

$window.Add_Drop({
    param($sender, $e)
    if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([Windows.DataFormats]::FileDrop)
        if ($files -and $files.Count -gt 0) { Import-Wallpaper $files[0] $script:NowApp }
    }
    $e.Handled = $true
})

# ── AI 生成（豆包 Seedream · 火山方舟 images/generations） ──
$aiKey        = Ctrl 'AiKey'
$aiModel      = Ctrl 'AiModel'
$aiPrompt     = Ctrl 'AiPrompt'
$aiPromptHint = Ctrl 'AiPromptHint'
$aiStatus     = Ctrl 'AiStatus'
$aiPanel      = Ctrl 'AiPanel'
$btnAiGen     = Ctrl 'BtnAiGen'

foreach ($m in @('doubao-seedream-4-0-250828', 'doubao-seedream-3-0-t2i-250415')) { [void]$aiModel.Items.Add($m) }
if ($script:Ai.model -and -not $aiModel.Items.Contains($script:Ai.model)) { [void]$aiModel.Items.Insert(0, $script:Ai.model) }
$aiModel.Text = $script:Ai.model
$aiKey.Text   = $script:Ai.apiKey

function Get-AiSize {
    foreach ($p in @(@('AiSize2K', '2K'), @('AiSize4K', '4K'), @('AiSizeW', '2560x1600'), @('AiSizeHD', '2048x1152'))) {
        if ((Ctrl $p[0]).IsChecked) { return $p[1] }
    }
    return '2K'
}
function Get-AiCount {
    foreach ($p in @(@('AiCnt1', 1), @('AiCnt2', 2), @('AiCnt4', 4))) {
        if ((Ctrl $p[0]).IsChecked) { return [int]$p[1] }
    }
    return 1
}
function Save-AiOptions {
    $script:Ai.apiKey = $aiKey.Text.Trim()
    $script:Ai.model  = $aiModel.Text.Trim()
    if (-not $script:Ai.model) { $script:Ai.model = 'doubao-seedream-4-0-250828' }
    $script:Ai.size  = Get-AiSize
    $script:Ai.count = Get-AiCount
    Save-AiConfig $script:Ai
}
# 服务端错误可能是 JSON（{"error":{"message":"…"}}），提取人话部分
function Get-ErrText([string]$raw) {
    $m = [regex]::Match($raw, '"message"\s*:\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return $raw
}

$aiPrompt.Add_TextChanged({
    $aiPromptHint.Visibility = if ($aiPrompt.Text) { 'Collapsed' } else { 'Visible' }
})
(Ctrl 'BtnAiKeySave').Add_Click({
    Save-AiOptions
    $aiStatus.Text = '已保存 API Key 与生成选项（仅存本机 doubao.json）。'
})

$script:AiBusy = $false
$script:AiJob  = $null

function Start-AiGenerate {
    if ($script:AiBusy) { return }
    $prompt = $aiPrompt.Text.Trim()
    if (-not $prompt) {
        $aiStatus.Text = '先写一句描述，例如：暮色雪山与湖泊，金色晚霞倒映水面，电影感构图，超高清细节'
        return
    }
    if (-not $aiKey.Text.Trim()) {
        $aiStatus.Text = '请先填入火山方舟 API Key（火山引擎控制台 → 火山方舟 → API Key 管理，需开通豆包·图像生成模型），填好后点「保存 Key」。'
        $aiKey.Focus()
        return
    }
    Save-AiOptions
    $script:AiBusy = $true
    $btnAiGen.IsEnabled = $false
    $btnAiGen.Content = '生成中…'
    $aiPanel.Children.Clear()
    $cnt = Get-AiCount
    $aiStatus.Text = "正在请求豆包生成 1/$cnt 张（每张约 10~30 秒）…"
    # 后台 runspace 里请求 API，避免卡死界面；完成后由 $aiTimer 在 UI 线程回收结果
    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($key, $model, $size, $prompt, $outDir, $count)
        $files = @(); $errors = @()
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
        for ($i = 0; $i -lt $count; $i++) {
            $json = @{
                model                       = $model
                prompt                      = $prompt
                size                        = $size
                response_format             = 'b64_json'
                watermark                   = $false
                sequential_image_generation = 'disabled'
            } | ConvertTo-Json
            try {
                $resp = Invoke-RestMethod -Uri 'https://ark.cn-beijing.volces.com/api/v3/images/generations' `
                    -Method Post -Headers @{ Authorization = "Bearer $key" } `
                    -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 300
                $d = $resp.data[0]
                $bytes = $null
                if ($d.b64_json) { $bytes = [Convert]::FromBase64String($d.b64_json) }
                elseif ($d.url) { $bytes = (Invoke-WebRequest -Uri $d.url -UseBasicParsing -TimeoutSec 120).Content }
                if ($bytes) {
                    $name = 'ai-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + (Get-Random -Maximum 999) + '.jpg'
                    [IO.File]::WriteAllBytes((Join-Path $outDir $name), $bytes)
                    $files += $name
                } else {
                    $errors += '响应中没有图片数据'
                }
            } catch {
                $msg = $_.ErrorDetails.Message
                if (-not $msg) { $msg = $_.Exception.Message }
                $errors += $msg
                break
            }
        }
        return @{ files = $files; errors = $errors }
    }).AddArgument($aiKey.Text.Trim()).AddArgument($script:Ai.model).AddArgument((Get-AiSize)).AddArgument($prompt).AddArgument($hubLib).AddArgument($cnt)
    $script:AiJob = @{ Ps = $ps; Async = $ps.BeginInvoke() }
    $aiTimer.Start()
}

$btnAiGen.Add_Click({ Start-AiGenerate })
$aiPrompt.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [Windows.Input.Key]::Enter -and
        ([Windows.Input.Keyboard]::IsKeyDown([Windows.Input.Key]::LeftCtrl) -or
         [Windows.Input.Keyboard]::IsKeyDown([Windows.Input.Key]::RightCtrl))) {
        $e.Handled = $true
        Start-AiGenerate
    }
})

$aiTimer = New-Object Windows.Threading.DispatcherTimer
$aiTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$aiTimer.Add_Tick({
    $job = $script:AiJob
    if ($job -eq $null) { $aiTimer.Stop(); return }
    if (-not $job.Async.IsCompleted) { return }
    $aiTimer.Stop()
    $out = $null
    # EndInvoke 返回 PSDataCollection：必须先取第一个输出对象再取属性，
    # 否则成员枚举会把空的 files 数组包成 @( @() )，被误判成"生成了 1 张空文件名"
    try { $out = @($job.Ps.EndInvoke($job.Async))[0] } catch { $out = @{ files = @(); errors = @($_.Exception.Message) } }
    $job.Ps.Dispose()
    $script:AiJob = $null
    $script:AiBusy = $false
    $btnAiGen.IsEnabled = $true
    $btnAiGen.Content = '✨ 生成壁纸'
    $files = @(@($out.files) | Where-Object { $_ }); $errs = @(@($out.errors) | Where-Object { $_ })
    if ($files.Count -gt 0) {
        foreach ($f in $files) {
            Add-LibEntry $f 'image' $script:NowApp
            Add-AiResultCard $f
        }
        Update-Library
        $msg = "已生成 $($files.Count) 张并自动收藏进壁纸库，点卡片「应用」立即换上。"
        if ($errs.Count -gt 0) { $msg += "（部分失败：$(($errs | ForEach-Object { Get-ErrText $_ }) -join '；')）" }
        $aiStatus.Text = $msg
    } else {
        $e = if ($errs.Count -gt 0) { ($errs | ForEach-Object { Get-ErrText $_ }) -join "`n" } else { '未知错误' }
        $aiStatus.Text = "生成失败：$e"
    }
})

# AI 结果卡片：缩略图 + 应用 / 删除（应用复用壁纸库逻辑：同步模式作用于所有勾选应用）
function Add-AiResultCard([string]$fileName) {
    if (-not $fileName) { return }
    $src = Join-Path $hubLib $fileName
    if (-not (Test-Path $src -PathType Leaf)) { return }
    $card = New-Object Windows.Controls.Border
    $card.Width = 150
    $card.CornerRadius = New-Object Windows.CornerRadius 8
    $card.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#20242E')
    $card.Margin = New-Object Windows.Thickness 0, 0, 8, 8
    $card.Tag = $fileName
    $panel = New-Object Windows.Controls.Grid
    $r0 = New-Object Windows.Controls.RowDefinition; $r0.Height = New-Object Windows.GridLength 84
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = [Windows.GridLength]::Auto
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = [Windows.GridLength]::Auto
    $panel.RowDefinitions.Add($r0); $panel.RowDefinitions.Add($r1); $panel.RowDefinitions.Add($r2)
    $clip = New-Object Windows.Controls.Border
    $clip.CornerRadius = New-Object Windows.CornerRadius 8, 8, 0, 0
    $clip.ClipToBounds = $true
    $clip.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#0B0D12')
    $img = New-Object Windows.Controls.Image
    $img.Stretch = 'UniformToFill'
    try { $img.Source = Get-ImageSource $src } catch {}
    $clip.Child = $img
    [Windows.Controls.Grid]::SetRow($clip, 0)
    $panel.Children.Add($clip) | Out-Null
    $name = New-Object Windows.Controls.TextBlock
    $name.Text = $fileName
    $name.FontSize = 10.5
    $name.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#9CA3AF')
    $name.TextTrimming = 'CharacterEllipsis'
    $name.Margin = New-Object Windows.Thickness 8, 4, 8, 0
    [Windows.Controls.Grid]::SetRow($name, 1)
    $panel.Children.Add($name) | Out-Null
    $ops = New-Object Windows.Controls.Primitives.UniformGrid
    $ops.Columns = 2
    $ops.Margin = New-Object Windows.Thickness 6, 5, 6, 7
    $useBtn = New-MiniButton '应用' $fileName
    $useBtn.Margin = New-Object Windows.Thickness 0, 0, 3, 0
    $useBtn.Add_Click({
        $h = Get-HubConfig
        $item = @($h.items | Where-Object { $_ -ne $null -and $_.file -eq $this.Tag }) | Select-Object -First 1
        if ($item) { Apply-LibraryItem $item }
    })
    $ops.Children.Add($useBtn) | Out-Null
    $delBtn = New-MiniButton '删除' $fileName
    $delBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#F87171')
    $delBtn.Margin = New-Object Windows.Thickness 3, 0, 0, 0
    $delBtn.Add_Click({
        $f = [string]$this.Tag
        $h = Get-HubConfig
        $h.items = @($h.items | Where-Object { $_ -ne $null -and $_.file -ne $f })
        Save-HubConfig $h
        $c = Get-AppConfig $script:NowApp
        $c.items = @($c.items | Where-Object { $_ -ne $null -and $_.file -ne $f })
        Save-AppConfig $script:NowApp $c
        Remove-Item (Join-Path $hubLib $f) -Force -ErrorAction SilentlyContinue
        foreach ($el in @($aiPanel.Children)) {
            if ([string]$el.Tag -eq $f) { $aiPanel.Children.Remove($el); break }
        }
        Update-Library
    })
    $ops.Children.Add($delBtn) | Out-Null
    [Windows.Controls.Grid]::SetRow($ops, 2)
    $panel.Children.Add($ops) | Out-Null
    $card.Child = $panel
    $aiPanel.Children.Add($card) | Out-Null
}

(Ctrl 'BtnClear').Add_Click({
    $app = $script:NowApp
    $dir = $AppMap[$app].Dir
    if ($AppMap[$app].Terminal) {
        # 终端：删本地壁纸文件 + 移除 WT profile 里的 background* 键 → 回到默认纯色背景（热生效）
        Get-ChildItem -Path (Join-Path $dir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
        $err = Set-WtBackground $app $null 0.55
        Update-NowView
        $statusText.Text = if ($err) { "清除 $app 壁纸失败：$err" } else { "已清除 $app 的壁纸，Windows Terminal 恢复默认纯色背景。" }
        return
    }
    Get-ChildItem -Path (Join-Path $dir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -Path (Join-Path $dir 'rotate') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'refresh-*' } | Remove-Item -Force
    $c = Get-AppConfig $app
    if ($c.rotation) { $c.rotation = $false; Save-AppConfig $app $c }
    Touch-LiveMarker $app
    Update-NowView
    $statusText.Text = "已清除 $app 的壁纸与轮换文件，将显示内置动态极光。（「壁纸库」页的轮换设置不受影响）"
})

(Ctrl 'BtnOpen').Add_Click({ Start-Process explorer.exe -ArgumentList "`"$hubLib`"" })

function Restart-Apps([string[]]$names) {
    if (@($names | Where-Object { -not $AppMap[$_].Terminal }).Count -eq 0) {
        # 终端目标：WT 监听 settings.json 热加载，换壁纸/改透明度即时生效，重启既无必要也不该杀终端
        [System.Windows.MessageBox]::Show(
            'PowerShell / CMD 由 Windows Terminal 承载：换壁纸即时热生效，无需重启。',
            '免重启', 'OK', 'Information') | Out-Null
        return
    }
    $running = @()
    foreach ($name in $names) {
        $p = Get-Process -Name $AppMap[$name].Proc -ErrorAction SilentlyContinue
        if ($p) { $running += @{ Name = $name; Proc = $p } }
    }
    if ($running.Count -eq 0) {
        [System.Windows.MessageBox]::Show('目标应用未在运行，直接启动即可。', '提示', 'OK', 'Information') | Out-Null
        return
    }
    $list = ($running | ForEach-Object { $_.Name }) -join '、'
    $answer = [System.Windows.MessageBox]::Show(
        "将关闭并重新启动：$list。未保存的会话内容不受影响（应用会自动恢复任务）。`n`n确认重启？",
        '重启应用', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    foreach ($r in $running) {
        $app = $AppMap[$r.Name]
        if ($app.Launcher) {
            # 代理型应用（Doubao）：必须经 vbs 启动器重启，才能带上调试端口加载壁纸代理
            $r.Proc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process wscript.exe -ArgumentList ('"' + $app.Launcher + '"')
            continue
        }
        if ($app.ShellApp) {
            # MSIX 应用（Codex）：WindowsApps 里的 exe 无法直接运行，经系统 AppsFolder 入口重启
            $r.Proc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process explorer.exe -ArgumentList "`"$($app.ShellApp)`""
            continue
        }
        if ($app.RelaunchLnk) {
            # Reasonix（launcher+versions 布局）：重启走官方 launcher 快捷方式——
            # 直接启动 versions 里的 app exe 不保证带完整环境
            $r.Proc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if ($app.Lnk -and (Test-Path $app.Lnk)) { Start-Process $app.Lnk }
            continue
        }
        if ($app.Elevate) {
            # Marvis 等提权应用：非提权的选择器进程结束不了它 → 一次性提权助手（-EncodedCommand 无临时文件竞态）
            $exePath = $null
            foreach ($cand in $app.ExeCandidates) { if (Test-Path $cand) { $exePath = $cand; break } }
            if (-not $exePath -and $app.Lnk -and (Test-Path $app.Lnk)) {
                try { $exePath = ((New-Object -ComObject WScript.Shell).CreateShortcut($app.Lnk)).TargetPath } catch {}
            }
            if ($exePath) {
                $body = "`$ErrorActionPreference='SilentlyContinue'; Get-Process -Name '$($app.Proc)' | Stop-Process -Force; Start-Sleep 2; Start-Process -FilePath '$exePath'"
                $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
                try {
                    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc) | Out-Null
                } catch {}
            }
            continue
        }
        $exePath = ($r.Proc | Select-Object -First 1).Path
        $r.Proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not $exePath -or -not (Test-Path $exePath)) {
            foreach ($cand in $app.ExeCandidates) { if (Test-Path $cand) { $exePath = $cand; break } }
            if (-not $exePath -and (Test-Path $app.Lnk)) {
                $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($app.Lnk)
                $exePath = $sh.TargetPath
            }
        }
        if ($exePath -and (Test-Path $exePath)) { Start-Process -FilePath $exePath }
    }
    $window.Close()
}

(Ctrl 'BtnRestart').Add_Click({ Restart-Apps @($script:NowApp) })

$swRotate.Add_Click({
    $cfg = Get-Cfg
    $cfg.rotation = [bool]$swRotate.IsChecked
    Commit-Cfg $cfg
    Update-Library
    Update-NowView
    $n = @($cfg.items | Where-Object { $_.rotate }).Count
    if ($cfg.rotation -and $n -eq 0) {
        $statusText.Text = '自动更换已开启，但还没有勾选任何壁纸——把想轮换的卡片点「轮换」勾上。'
    } elseif ($cfg.rotation) {
        $statusText.Text = "自动更换已开启（$(TargetsText)，$n 张）。每次打开应用自动换用下一张。"
    } else {
        $statusText.Text = "自动更换已关闭（$(TargetsText)），将一直使用当前壁纸。"
    }
})

foreach ($pair in @(@('Iv0', 0), @('Iv1', 1), @('Iv5', 5), @('Iv15', 15), @('Iv30', 30), @('Iv60', 60))) {
    $rb = Ctrl $pair[0]
    $rb.Add_Checked({
        $cfg = Get-Cfg
        $cfg.interval = [int]$this.Tag
        Commit-Cfg $cfg
        $ivNow = [int]$this.Tag
        if ($ivNow -gt 0) {
            $statusText.Text = "轮换间隔：每 $ivNow 分钟自动换一张（应用运行期间也生效）"
        } else {
            $statusText.Text = '轮换间隔：仅在打开应用时换一张'
        }
    })
}

$swSync.Add_Click({
    $script:Sync = [bool]$swSync.IsChecked
    if (-not $script:Sync) {
        # 切到独立模式：当前应用 = 勾选中的第一个
        if (-not ($script:Checked -contains $script:Active)) { $script:Active = $script:Checked[0] }
        $script:Checked = @($script:Active)
    } else {
        # 切到同步模式：以当前应用的设置为准推送到所有勾选应用
        $appCfg = Get-AppConfig $script:Active
        $hubCfg2 = Get-HubConfig
        $hubCfg2.rotation = $appCfg.rotation
        $hubCfg2.interval = $appCfg.interval
        $hubCfg2.items = @($appCfg.items)
        $hubCfg2.sync = $true
        $hubCfg2.checked = @($script:Checked)
        Save-HubConfig $hubCfg2
        Commit-Cfg $hubCfg2
    }
    Update-ChipVisual
    Update-Library
    Update-NowView
    if ($script:Sync) {
        $statusText.Text = "同步模式：「壁纸库」页的设置将一致应用到 $(TargetsText)。「当前壁纸」页仍按应用单独显示与设置。"
    } else {
        $statusText.Text = "独立模式：「壁纸库」页只修改 $script:Active。「当前壁纸」页仍按应用单独显示与设置。"
    }
})

# ── 「当前壁纸」页应用切换下拉框 ──────────────────────────
$script:NowApp = $Apps[0].Name
$script:NowComboMap = @{}
$nowCombo = Ctrl 'NowAppCombo'
foreach ($a in $Apps) {
    $it = New-Object System.Windows.Controls.ComboBoxItem
    $it.Content = $a.Name
    $it.Tag = $a.Name
    [void]$nowCombo.Items.Add($it)
    $script:NowComboMap[$a.Name] = $it
}
$nowCombo.Add_SelectionChanged({
    # 优先取 ComboBoxItem.Tag；未命中再退回 SelectedValue（已配 SelectedValuePath="Tag"）
    $name = $this.SelectedItem
    if ($name) { $name = [string]$name.Tag }
    if (-not $name) { $name = [string]$this.SelectedValue }
    if (-not $name -or $name -eq $script:NowApp) { return }
    $script:NowApp = $name
    Update-Hints
    Update-NowView
    $statusText.Text = "正在查看：$script:NowApp 的当前壁纸 · 本页操作只作用于 $script:NowApp"
})
$nowCombo.SelectedItem = $script:NowComboMap[$script:NowApp]
Update-Hints
Update-NowView

# ── 一键修复（后台重跑 apply-patch.ps1，自动识别目录，完成后复检并询问重启） ──
$script:RepairJob = $null

function Start-App([string]$name, [string]$preferExe) {
    $app = $AppMap[$name]
    if ($app.Launcher -and (Test-Path $app.Launcher)) {
        # 代理型应用（Doubao / Codex）：必须经启动器拉起才能带上壁纸注入
        Start-Process wscript.exe -ArgumentList ('"' + $app.Launcher + '"')
        return
    }
    $exePath = $preferExe
    if (-not ($exePath -and (Test-Path $exePath))) {
        $exePath = $null
        foreach ($cand in $app.ExeCandidates) { if (Test-Path $cand) { $exePath = $cand; break } }
    }
    if (-not $exePath -and $app.Lnk -and (Test-Path $app.Lnk)) {
        try { $exePath = ((New-Object -ComObject WScript.Shell).CreateShortcut($app.Lnk)).TargetPath } catch {}
    }
    if (-not $exePath -and $script:Health[$name] -and $script:Health[$name].Dir) {
        $exePath = Join-Path $script:Health[$name].Dir ($app.Proc + '.exe')
    }
    if ($exePath -and (Test-Path $exePath)) {
        if ($app.Elevate) { Start-Process -FilePath $exePath -Verb RunAs }
        else { Start-Process -FilePath $exePath }
    }
}

function Start-Repair {
    if ($script:RepairJob -ne $null) { $statusText.Text = '修复正在进行中，请稍候…'; return }
    $broken = @($Apps.Name | Where-Object { $script:Health[$_].Broken })
    if ($broken.Count -eq 0) { $statusText.Text = '未检测到失效的壁纸补丁，无需修复。'; return }
    if (-not (Test-Path $RepairTool)) {
        [System.Windows.MessageBox]::Show(
            "未找到修复工具链：`n$RepairTool`n`n请重新执行一次 apply-patch.ps1，它会自动部署修复工具。",
            '一键修复', 'OK', 'Warning') | Out-Null
        return
    }
    # 组装修复任务；自动识别不到目录的应用弹文件夹选择框人工指认
    $jobs = @(); $needClose = @()
    foreach ($name in $broken) {
        $app = $AppMap[$name]
        $dir = $script:Health[$name].Dir
        if (-not $dir -and -not $app.MsixId) {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "未能自动定位 $name 的安装目录，请手动选择（含 resources 文件夹的那一层）"
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg.SelectedPath) {
                $dir = $dlg.SelectedPath
            } else {
                $statusText.Text = "已跳过 $name（未指定安装目录）。"
                continue
            }
        }
        $jobs += @{
            App = $name
            Id  = $(if ($app.PatchId) { $app.PatchId } else { $name })
            Dir = $dir
        }
        $p = Get-Process -Name $app.Proc -ErrorAction SilentlyContinue
        if ($p) { $needClose += @{ Name = $name; Proc = $p } }
    }
    if ($jobs.Count -eq 0) { return }
    # 打补丁要求应用处于关闭状态（MSIX 提权实例内部还会再查一次）
    if ($needClose.Count -gt 0) {
        $list = ($needClose | ForEach-Object { $_.Name }) -join '、'
        $ans = [System.Windows.MessageBox]::Show(
            "修复 $list 需要先关闭它（未保存的会话内容不受影响，应用会自动恢复任务，修完可选择重新启动）。`n`n继续？",
            '一键修复', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        foreach ($c in $needClose) { $c.Proc | Stop-Process -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 3
    }
    $script:RepairClosed = @($needClose | ForEach-Object { $_.Name })
    (Ctrl 'BtnFix').IsEnabled = $false
    $statusText.Text = "正在修复：$(@($jobs | ForEach-Object { $_.App }) -join '、')（重打补丁约需几十秒，ZCode 需重新打包 asar）…"
    # 后台 runspace 逐个调用修复脚本，避免卡死界面；完成后由 $repairTimer 回收
    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($tool, $jobs)
        $results = @()
        foreach ($j in $jobs) {
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-App', $j.Id, '-NoShortcut')
            if ($j.Dir) { $argList += @('-InstallDir', $j.Dir) }
            $out = & powershell.exe @argList 2>&1
            $results += [pscustomobject]@{
                Name = $j.App
                Exit = $LASTEXITCODE
                Log  = (($out | ForEach-Object { [string]$_ }) -join "`n")
            }
        }
        return $results
    }).AddArgument($RepairTool).AddArgument($jobs)
    $script:RepairJob = @{ Ps = $ps; Async = $ps.BeginInvoke() }
    $repairTimer.Start()
}

$repairTimer = New-Object Windows.Threading.DispatcherTimer
$repairTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$repairTimer.Add_Tick({
    $job = $script:RepairJob
    if ($job -eq $null) { $repairTimer.Stop(); return }
    if (-not $job.Async.IsCompleted) { return }
    $repairTimer.Stop()
    $results = $null
    try { $results = @($job.Ps.EndInvoke($job.Async)) } catch { $results = @() }
    $job.Ps.Dispose()
    $script:RepairJob = $null
    (Ctrl 'BtnFix').IsEnabled = $true
    Update-AppHealth
    $okList = @(); $badList = @(); $msixWait = @()
    foreach ($r in $results) {
        $h = $script:Health[$r.Name]
        if ($h -and -not $h.Broken) { $okList += $r.Name }
        elseif ($AppMap[$r.Name].MsixId) { $msixWait += $r.Name }
        else { $badList += $r.Name }
    }
    $msg = ''
    if ($okList.Count -gt 0) { $msg += "已修复：$($okList -join '、')。" }
    if ($msixWait.Count -gt 0) {
        $msg += "$($msixWait -join '、') 需管理员授权：请在弹出的 UAC/管理员窗口中确认，完成后自动检测（也可点「重新检测」）。"
    }
    if ($badList.Count -gt 0) {
        $msg += "`n修复失败："
        foreach ($name in $badList) {
            $r = $results | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            $tail = (@($r.Log -split "`n") | Select-Object -Last 2) -join ' '
            $msg += "`n· $name：$tail"
        }
    }
    $statusText.Text = $msg.Trim()
    # 管理员授权窗口（MSIX）执行期间轮询复检，最多 3 分钟
    if ($msixWait.Count -gt 0) {
        $script:RecheckNames = $msixWait
        $script:RecheckLeft = 60
        $recheckTimer.Start()
    }
    # 修复成功且刚才有关闭应用 → 询问重启
    if ($okList.Count -gt 0 -and $script:RepairClosed.Count -gt 0) {
        $restart = @($script:RepairClosed | Where-Object { $okList -contains $_ })
        $ans = [System.Windows.MessageBox]::Show(
            "修复完成：$($restart -join '、')。`n`n是否立即重新启动？",
            '一键修复', 'YesNo', 'Question')
        if ($ans -eq 'Yes') {
            foreach ($name in $restart) { Start-App $name '' }
            $statusText.Text = "已重新启动 $($restart -join '、')，窗口标题出现 ✦ 即壁纸生效。"
        }
    }
})

# 「重新检测」：手动刷新补丁健康状态（含 MSIX 提权修复完成后的确认）
$recheckTimer = New-Object Windows.Threading.DispatcherTimer
$recheckTimer.Interval = [TimeSpan]::FromSeconds(3)
$recheckTimer.Add_Tick({
    $script:RecheckLeft--
    Update-AppHealth
    $left = @($script:RecheckNames | Where-Object { $script:Health[$_].Broken })
    if ($left.Count -eq 0 -or $script:RecheckLeft -le 0) {
        $recheckTimer.Stop()
        $fixed = @($script:RecheckNames | Where-Object { -not $script:Health[$_].Broken })
        if ($fixed.Count -gt 0) { $statusText.Text = "已修复：$($fixed -join '、')。" }
        else { $statusText.Text = "$($script:RecheckNames -join '、') 仍未修复，可重试「一键修复」或查看管理员窗口里的报错。" }
    }
})
(Ctrl 'BtnRecheck').Add_Click({
    Update-AppHealth
    $n = @($Apps.Name | Where-Object { $script:Health[$_].Broken }).Count
    $statusText.Text = if ($n -eq 0) { '检测完成：所有应用的壁纸补丁均正常。' } else { "检测完成：仍有 $n 个应用补丁失效，可点「一键修复」。`n$((Ctrl 'FixText').Text)" }
})
(Ctrl 'BtnFix').Add_Click({ Start-Repair })

Update-ChipVisual
Update-Library
$modeText = if ($script:Sync) { "同步模式：「壁纸库」的设置应用到 $($script:Checked -join '、')" } else { "独立模式：「壁纸库」只修改 $script:Active" }
$statusText.Text = "$modeText。「当前壁纸」页按应用单独显示，操作只作用于当前查看的应用。"
# 启动时全量体检一次：有补丁失效的（应用升级覆盖等）立即弹出警告条
Update-AppHealth
[void]$window.ShowDialog()
