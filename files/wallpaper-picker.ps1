# ai-wallpaper — AI 壁纸设置中心（ZCode / WorkBuddy / OpenCode 统一选择器）
# 多应用管理：同步模式（一套壁纸/轮换设置应用到所有勾选的应用）或独立模式（每个应用各设各的）。
# 共享壁纸库存放于 %USERPROFILE%\.ai-wallpaper\library，改动通过 refresh 标记免重启热切换（部分应用需重启）。

Add-Type -AssemblyName PresentationFramework, WindowsBase, System.Drawing

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
       Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OpenCode.lnk" }
)
$Apps = @($AllApps | Where-Object { Test-Path $_.Dir })
if ($Apps.Count -eq 0) {
    [System.Windows.MessageBox]::Show(
        '未检测到已打补丁的应用（ZCode / WorkBuddy / OpenCode）。' + [char]10 +
        '请先在对应应用上执行 apply-patch.ps1 安装壁纸补丁。',
        'AI 壁纸设置', 'OK', 'Warning') | Out-Null
    exit
}
$AppMap = @{}
foreach ($a in $Apps) {
    if (-not (Test-Path (Join-Path $a.Dir 'rotate'))) { New-Item -ItemType Directory -Path (Join-Path $a.Dir 'rotate') -Force | Out-Null }
    $AppMap[$a.Name] = $a
}

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
                items    = @($c.items)
                checked  = @($c.checked)
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
$script:Checked = @($hubCfg.checked | Where-Object { $AppMap.ContainsKey($_) })
if ($script:Checked.Count -eq 0) { $script:Checked = @($Apps | ForEach-Object { $_.Name }) }
$script:Active = $script:Checked[0]

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
                $c.items = @($c.items | Where-Object { Test-Path (Join-Path $hubLib $_.file) })
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

# ── 媒体探测/轮换重建（参数化到指定应用） ─────────────────
function Get-WallpaperFile([string]$appName) {
    foreach ($e in @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')) {
        $f = Join-Path $AppMap[$appName].Dir "wallpaper.$e"
        if (Test-Path $f) { return $f }
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
    # 递增编号的 1x1 透明 GIF：应用内壁纸脚本每 5 秒探测，编号变化即免重启热切换
    $rot = Join-Path $AppMap[$appName].Dir 'rotate'
    if (-not (Test-Path $rot)) { New-Item -ItemType Directory -Path $rot -Force | Out-Null }
    Get-ChildItem $rot -Filter 'refresh-*' -ErrorAction SilentlyContinue | Remove-Item -Force
    $counterPath = Join-Path $hub '.refresh-counter'
    $c = 0
    try { if (Test-Path $counterPath) { $c = [int](Get-Content $counterPath -Raw) } } catch {}
    $c++
    Set-Content -Path $counterPath -Value $c -Encoding ASCII
    $gif = [Convert]::FromBase64String('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7')
    [IO.File]::WriteAllBytes((Join-Path $rot ("refresh-" + (($c % 5) + 1) + ".gif")), $gif)
}

function Rebuild-Rotate([string]$appName, $cfg) {
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

# 当前生效目标：同步=所有勾选应用；独立=当前应用
function Get-Targets {
    if ($script:Sync) { return @($script:Checked) } else { return @($script:Active) }
}
function Get-DisplayApp {
    if ($script:Sync) { return $script:Checked[0] } else { return $script:Active }
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
        Title="AI 壁纸设置" Height="612" Width="560"
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
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="9">
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
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8">
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
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
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
          <TextBlock Text="ZCode · WorkBuddy" Foreground="#5B6172" FontSize="12" Margin="8,2,0,0" VerticalAlignment="Center"/>
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

        <!-- 应用选择行 -->
        <Border Grid.Row="0" Background="#101218" CornerRadius="10" Padding="14,9" Margin="0,0,0,8"
                BorderBrush="#242835" BorderThickness="1">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="应用" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <WrapPanel x:Name="AppChips"/>
            </StackPanel>
            <CheckBox Grid.Column="1" x:Name="SwSync" Style="{StaticResource Switch}" Content="同步设置"
                      VerticalAlignment="Center" ToolTip="开：一套壁纸与轮换设置应用到所有勾选的应用；关：只改当前勾选的应用"/>
          </Grid>
        </Border>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
          <RadioButton x:Name="TabNow" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="当前壁纸" IsChecked="True"/>
          <RadioButton x:Name="TabLib" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="壁纸库"/>
        </StackPanel>

        <Grid Grid.Row="2">
          <!-- 页 1：当前壁纸 -->
          <Grid x:Name="PageNow">
            <Grid.RowDefinitions>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" CornerRadius="10" Background="#0B0D12" Height="268"
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
                  <TextBlock Text="未设置壁纸 · 使用内置动态极光" Foreground="#6B7183" FontSize="12.5"
                             HorizontalAlignment="Center" Margin="0,10,0,0"/>
                </StackPanel>
                <Border x:Name="Badge" CornerRadius="6" Background="#CC101218" Padding="10,5"
                        HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="10,10,0,10" Visibility="Collapsed">
                  <TextBlock x:Name="BadgeText" Foreground="#C9CEDA" FontSize="11.5"/>
                </Border>
              </Grid>
            </Border>
            <StackPanel Grid.Row="1" Margin="0,12,0,0">
              <Button x:Name="BtnPick" Style="{StaticResource BtnPrimary}" Content="选择图片 / 视频..."/>
              <UniformGrid Columns="3" Margin="0,10,0,0">
                <Button x:Name="BtnClear" Style="{StaticResource BtnGhost}" Content="恢复极光" Margin="0,0,5,0"/>
                <Button x:Name="BtnOpen"  Style="{StaticResource BtnGhost}" Content="壁纸文件夹" Margin="5,0"/>
                <Button x:Name="BtnRestart" Style="{StaticResource BtnGhost}" Content="重启应用" Margin="5,0,0,0"/>
              </UniformGrid>
              <TextBlock x:Name="StatusText" Foreground="#8A90A0" FontSize="12" Margin="2,10,0,0" TextWrapping="Wrap"/>
              <TextBlock Foreground="#4E5464" FontSize="11" Margin="2,6,0,0"
                         Text="支持 mp4 / webm / gif / webp / png / jpg · 可以直接把文件拖进本窗口 · 新壁纸自动存入壁纸库"/>
            </StackPanel>
          </Grid>

          <!-- 页 2：壁纸库 -->
          <Grid x:Name="PageLib" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#101218" CornerRadius="10" Padding="14,10" Margin="0,0,0,8"
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
            <StackPanel Grid.Row="1" x:Name="IntervalRow" Orientation="Horizontal" Margin="4,0,0,10" Visibility="Collapsed">
              <TextBlock Text="换片间隔" Foreground="#8A90A0" FontSize="11.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <RadioButton x:Name="Iv0"  Style="{StaticResource IvPill}" GroupName="iv" Content="仅打开时" Tag="0" IsChecked="True"/>
              <RadioButton x:Name="Iv1"  Style="{StaticResource IvPill}" GroupName="iv" Content="1分钟" Tag="1"/>
              <RadioButton x:Name="Iv5"  Style="{StaticResource IvPill}" GroupName="iv" Content="5分钟" Tag="5"/>
              <RadioButton x:Name="Iv15" Style="{StaticResource IvPill}" GroupName="iv" Content="15分钟" Tag="15"/>
              <RadioButton x:Name="Iv30" Style="{StaticResource IvPill}" GroupName="iv" Content="30分钟" Tag="30"/>
              <RadioButton x:Name="Iv60" Style="{StaticResource IvPill}" GroupName="iv" Content="1小时" Tag="60"/>
            </StackPanel>
            <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <WrapPanel x:Name="LibPanel"/>
                <TextBlock x:Name="LibEmpty" Text="壁纸库为空 · 在「当前壁纸」页选择或拖入文件即可收藏"
                           Foreground="#6B7183" FontSize="12" HorizontalAlignment="Center" Margin="0,40,0,0"/>
              </StackPanel>
            </ScrollViewer>
            <TextBlock Grid.Row="3" Foreground="#4E5464" FontSize="10.5" Margin="2,8,0,0"
                       Text="单击卡片应用为当前壁纸 · 勾选「轮换」的壁纸参与自动更换 · 视频卡片自动循环播放预览"/>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

function Ctrl($name) { $window.FindName($name) }
$preview      = Ctrl 'Preview'
$previewVideo = Ctrl 'PreviewVideo'
$previewEmpty = Ctrl 'PreviewEmpty'
$badge        = Ctrl 'Badge'
$badgeText    = Ctrl 'BadgeText'
$statusText   = Ctrl 'StatusText'
$previewArea  = Ctrl 'PreviewArea'
$libPanel     = Ctrl 'LibPanel'
$libEmpty     = Ctrl 'LibEmpty'
$swRotate     = Ctrl 'SwRotate'
$swSync       = Ctrl 'SwSync'

$previewVideo.Add_MediaEnded({
    $previewVideo.Position = [TimeSpan]::Zero
    $previewVideo.Play()
})

# ── 应用芯片 ─────────────────────────────────────────────
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
        Update-Preview
        Update-Library
        Update-Hints
    }.GetNewClosure())
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
function Get-ImageSource([string]$path) {
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'
    $bi.UriSource = [Uri]$path
    $bi.EndInit()
    return $bi
}

function Get-ThumbSource([string]$path) {
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'
    $thumb = [ShellThumb]::GetThumb($path, 480, 270)
    $ms = New-Object IO.MemoryStream
    $thumb.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $thumb.Dispose()
    $bi.StreamSource = $ms
    $bi.EndInit()
    return $bi
}

function Stop-PreviewVideo {
    $previewVideo.Stop()
    $previewVideo.Source = $null
    $previewVideo.Visibility = 'Collapsed'
}

function Show-Empty {
    $preview.Source = $null
    $preview.Visibility = 'Collapsed'
    Stop-PreviewVideo
    $previewEmpty.Visibility = 'Visible'
    $badge.Visibility = 'Collapsed'
}

function Update-Preview {
    $dispApp = Get-DisplayApp
    $cfg = if ($script:Sync) { Get-HubConfig } else { Get-AppConfig $dispApp }
    if ($cfg.rotation) {
        $rot1 = $null
        foreach ($e in @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')) {
            $cand = Join-Path (Join-Path $AppMap[$dispApp].Dir 'rotate') "rotate-1.$e"
            if (Test-Path $cand) { $rot1 = $cand; break }
        }
        $n = @($cfg.items | Where-Object { $_.rotate }).Count
        $iv = $cfg.interval
        if ($rot1) {
            $previewEmpty.Visibility = 'Collapsed'
            $badge.Visibility = 'Visible'
            $ivText = if ($iv -gt 0) { " · 每 $iv 分钟再换" } else { '' }
            $badgeText.Text = "$dispApp · 自动轮换中（$n 张$ivText）"
            if ($rot1 -match '\.(mp4|webm)$') {
                $preview.Source = $null
                $preview.Visibility = 'Collapsed'
                $previewVideo.Visibility = 'Visible'
                $previewVideo.Source = [Uri]$rot1
                $previewVideo.Play()
            } else {
                Stop-PreviewVideo
                $preview.Source = Get-ImageSource $rot1
                $preview.Visibility = 'Visible'
            }
            $statusText.Text = "$(TargetsText) 正在自动轮换壁纸（$n 张参与$ivText）。想固定某一张：在壁纸库点「应用」，会自动暂停轮换。"
            return
        }
    }
    $f = Get-WallpaperFile $dispApp
    if (-not $f) { Show-Empty; return }
    $previewEmpty.Visibility = 'Collapsed'
    $badge.Visibility = 'Visible'
    $badgeText.Text = "$dispApp · {0}  ({1:N1} MB)" -f (Split-Path $f -Leaf), ((Get-Item $f).Length / 1MB)
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

function TargetsText {
    if ($script:Sync) { return ($script:Checked -join '、') }
    return $script:Active
}

function Import-Wallpaper([string]$file) {
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

    $cfg = Get-Cfg
    $entry = [pscustomobject]@{
        file   = $libName
        type   = $type
        rotate = $cfg.rotation
        added  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $cfg.items = @($cfg.items) + $entry
    Commit-Cfg $cfg

    # 应用到目标：写入各目标应用的 wallpaper.<ext>
    foreach ($name in (Get-Targets)) {
        Get-ChildItem -Path (Join-Path $AppMap[$name].Dir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
        Copy-Item (Join-Path $hubLib $libName) (Join-Path $AppMap[$name].Dir "wallpaper$ext") -Force
    }
    Update-Preview
    $statusText.Text = "已设置并收藏：$([IO.Path]::GetFileName($file))`n$([math]::Round((Get-Item $file).Length/1MB,1)) MB · 目标：$(TargetsText)"
    Update-Library
}

function Apply-LibraryItem($item) {
    $src = Join-Path $hubLib $item.file
    if (-not (Test-Path $src)) { return }
    $cfg = Get-Cfg
    $wasRotating = $cfg.rotation
    foreach ($name in (Get-Targets)) {
        Get-ChildItem -Path (Join-Path $AppMap[$name].Dir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
        Copy-Item $src (Join-Path $AppMap[$name].Dir ("wallpaper" + [IO.Path]::GetExtension($item.file))) -Force
    }
    $msg = "已应用到 $(TargetsText)：$($item.file)"
    if ($wasRotating) {
        # 应用 = 固定这张，暂停轮换，保证选择器与应用显示一致
        $cfg.rotation = $false
        Commit-Cfg $cfg
        $msg += "`n（原轮换已暂停，开关可随时重新打开）"
    }
    Update-Preview
    $statusText.Text = $msg
    (Ctrl 'TabNow').IsChecked = $true
}

# ── 壁纸库网格 ───────────────────────────────────────────
function New-MiniButton([string]$text, $tag) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text
    $b.Tag = $tag
    $b.Style = $window.Resources['BtnMini']
    return $b
}

function Update-Hints {
    (Ctrl 'BtnRestart').Content = if ($script:Sync) { '重启应用' } else { "重启 $script:Active" }
}

function Update-Library {
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

        # 媒体区：视频 → 静态帧 + 悬停播放（避免多路同时解码卡顿）；图片 → Image
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
            # 悬停在本卡片内原地播放（同一时刻只有一路解码），移开恢复静态帧
            $holder = @{ border = $clipBorder; img = $img; src = $src; media = $null }
            $clipBorder.Tag = $holder
            $clipBorder.Add_MouseEnter({
                $h = $this.Tag
                $me = New-Object Windows.Controls.MediaElement
                $me.Stretch = 'Uniform'
                $me.IsMuted = $true
                $me.Volume = 0
                $me.LoadedBehavior = 'Manual'
                $me.UnloadedBehavior = 'Close'
                $me.Source = [Uri]$h.src
                $me.Add_MediaEnded({
                    $s = $this
                    if ($s.Source -ne $null) { $s.Position = [TimeSpan]::Zero; $s.Play() }
                })
                $h.media = $me
                $h.border.Child = $me
                $me.Play()
            })
            $clipBorder.Add_MouseLeave({
                $h = $this.Tag
                if ($h.media -ne $null) {
                    $h.media.Stop()
                    $h.media.Source = $null
                    $h.media.Close()
                    $h.media = $null
                }
                $h.border.Child = $h.img
            })
        } else {
            $img = New-Object Windows.Controls.Image
            $img.Stretch = 'UniformToFill'
            try { $img.Source = Get-ImageSource $src } catch {}
        }
        $clipBorder.Child = $img
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
            $cfg2.items = @($cfg2.items | Where-Object { $_.file -ne $item.file })
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

# ── 事件 ─────────────────────────────────────────────────
(Ctrl 'DragBar').Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
(Ctrl 'BtnClose').Add_Click({ $window.Close() })
(Ctrl 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })

(Ctrl 'TabNow').Add_Checked({
    (Ctrl 'PageNow').Visibility = 'Visible'
    (Ctrl 'PageLib').Visibility = 'Collapsed'
    $window.Height = 612
})
(Ctrl 'TabLib').Add_Checked({
    (Ctrl 'PageLib').Visibility = 'Visible'
    (Ctrl 'PageNow').Visibility = 'Collapsed'
    $window.Height = 718
    Update-Library
})

(Ctrl 'BtnPick').Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = '选择壁纸'
    $dlg.Filter = '媒体文件|*.mp4;*.webm;*.gif;*.webp;*.png;*.jpg;*.jpeg|视频|*.mp4;*.webm|图片|*.gif;*.webp;*.png;*.jpg;*.jpeg|所有文件|*.*'
    if ($dlg.ShowDialog()) { Import-Wallpaper $dlg.FileName }
})

$window.Add_Drop({
    param($sender, $e)
    if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([Windows.DataFormats]::FileDrop)
        if ($files -and $files.Count -gt 0) { Import-Wallpaper $files[0] }
    }
    $e.Handled = $true
})

(Ctrl 'BtnClear').Add_Click({
    foreach ($name in (Get-Targets)) {
        Get-ChildItem -Path (Join-Path $AppMap[$name].Dir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
        Touch-LiveMarker $name
    }
    Update-Preview
    $statusText.Text = "已清除 $(TargetsText) 的壁纸，壁纸界面将显示内置动态极光。"
})

(Ctrl 'BtnOpen').Add_Click({ Start-Process explorer.exe -ArgumentList "`"$hubLib`"" })

function Restart-Apps([string[]]$names) {
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
        $exePath = ($r.Proc | Select-Object -First 1).Path
        $r.Proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not $exePath -or -not (Test-Path $exePath)) {
            $app = $AppMap[$r.Name]
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

(Ctrl 'BtnRestart').Add_Click({ Restart-Apps (Get-Targets) })

$swRotate.Add_Click({
    $cfg = Get-Cfg
    $cfg.rotation = [bool]$swRotate.IsChecked
    Commit-Cfg $cfg
    Update-Library
    $n = @($cfg.items | Where-Object { $_.rotate }).Count
    if ($cfg.rotation -and $n -eq 0) {
        $statusText.Text = '自动更换已开启，但还没有勾选任何壁纸——去「壁纸库」把想轮换的勾上。'
        (Ctrl 'TabLib').IsChecked = $true
    } elseif ($cfg.rotation) {
        $statusText.Text = "自动更换已开启（$(TargetsText)，$n 张）。每次打开应用自动换用下一张。"
    } else {
        $statusText.Text = "自动更换已关闭（$(TargetsText)），将一直使用当前壁纸。"
    }
})

foreach ($pair in @(@('Iv0', 0), @('Iv1', 1), @('Iv5', 5), @('Iv15', 15), @('Iv30', 30), @('Iv60', 60))) {
    $rb = Ctrl $pair[0]
    $rb.Add_Checked({
        if (-not $rbIv.IsChecked) { return }
        $cfg = Get-Cfg
        $cfg.interval = [int]$rbIv.Tag
        Commit-Cfg $cfg
        $ivNow = [int]$rbIv.Tag
        if ($ivNow -gt 0) {
            $statusText.Text = "轮换间隔：每 $ivNow 分钟自动换一张（应用运行期间也生效）"
        } else {
            $statusText.Text = '轮换间隔：仅在打开应用时换一张'
        }
    }.GetNewClosure())
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
    Update-Preview
    Update-Library
    Update-Hints
    if ($script:Sync) {
        $statusText.Text = "同步模式：壁纸与轮换设置将一致应用到 $(TargetsText)。"
    } else {
        $statusText.Text = "独立模式：当前只修改 $script:Active，其他应用保持各自的设置。"
    }
})

Update-ChipVisual
Update-Hints
Update-Preview
Update-Library
if ($script:Sync) {
    $statusText.Text = "同步模式：壁纸与轮换设置将一致应用到 $(TargetsText)。"
} else {
    $statusText.Text = "独立模式：当前只修改 $script:Active，其他应用保持各自的设置。"
}
[void]$window.ShowDialog()
