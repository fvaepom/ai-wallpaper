# zcode-wallpaper — ZCode 壁纸选择器（现代深色 UI · 壁纸库 · 自动轮换）
# 图片/视频均可；支持拖拽导入；可管理壁纸库并设置每次打开 ZCode 自动更换。

Add-Type -AssemblyName PresentationFramework, WindowsBase, System.Drawing

$wallDir = Join-Path $env:USERPROFILE '.zcode\wallpaper'
$libDir  = Join-Path $wallDir 'library'
$rotDir  = Join-Path $wallDir 'rotate'
$cfgPath = Join-Path $wallDir 'config.json'
foreach ($d in @($wallDir, $libDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ── Shell 视频缩略图（视频预览用） ───────────────────────
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
        using (Bitmap tmp = (Bitmap)Image.FromHbitmap(hbm)) {
            copy = new Bitmap(tmp);
        }
        DeleteObject(hbm);
        return copy;
    }
}
'@ -ReferencedAssemblies System.Drawing
}

# ── 配置（library.json） ─────────────────────────────────
function Get-Config {
    if (Test-Path $cfgPath) {
        try {
            $c = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return [pscustomobject]@{
                rotation = [bool]$c.rotation
                items    = @($c.items)
            }
        } catch {}
    }
    return [pscustomobject]@{ rotation = $false; items = @() }
}
function Save-Config($c) {
    $c | ConvertTo-Json -Depth 6 | Set-Content -Path $cfgPath -Encoding UTF8
}

# ── 轮换集重建：rotate\rotate-N.<ext> ────────────────────
function Rebuild-Rotate {
    if (Test-Path $rotDir) {
        Get-ChildItem $rotDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    $cfg = Get-Config
    if (-not $cfg.rotation) { return }
    New-Item -ItemType Directory -Path $rotDir -Force | Out-Null
    $n = 1
    foreach ($it in (@($cfg.items) | Where-Object { $_.rotate } | Sort-Object added)) {
        $src = Join-Path $libDir $it.file
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $rotDir ("rotate-$n" + [IO.Path]::GetExtension($it.file))) -Force
            $n++
        }
    }
}

# ── XAML 界面 ────────────────────────────────────────────
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ZCode 壁纸设置" Height="672" Width="560"
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
          <TextBlock Text="ZCode 壁纸" Foreground="#ECECEC" FontSize="14.5" FontWeight="SemiBold"
                     Margin="10,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Text="设置" Foreground="#5B6172" FontSize="12" Margin="8,2,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,10,0">
          <Button x:Name="BtnMin" Style="{StaticResource CaptionBtn}" Content="─"/>
          <Button x:Name="BtnClose" Style="{StaticResource CaptionBtn}" Content="✕"/>
        </StackPanel>
      </Grid>

      <Grid Grid.Row="1" Margin="20,2,20,16">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
          <RadioButton x:Name="TabNow" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="当前壁纸" IsChecked="True"/>
          <RadioButton x:Name="TabLib" Style="{StaticResource TabPill}" GroupName="tabs"
                       Content="壁纸库"/>
        </StackPanel>

        <Grid Grid.Row="1">
          <!-- 页 1：当前壁纸 -->
          <Grid x:Name="PageNow">
            <Grid.RowDefinitions>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" CornerRadius="10" Background="#101218"
                    BorderBrush="#242835" BorderThickness="1" ClipToBounds="True">
              <Grid x:Name="PreviewArea" Background="Transparent">
                <Image x:Name="Preview" Stretch="UniformToFill" Visibility="Collapsed"/>
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
                        HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="10,0,0,10" Visibility="Collapsed">
                  <TextBlock x:Name="BadgeText" Foreground="#C9CEDA" FontSize="11.5"/>
                </Border>
              </Grid>
            </Border>
            <StackPanel Grid.Row="1" Margin="0,14,0,0">
              <Button x:Name="BtnPick" Style="{StaticResource BtnPrimary}" Content="选择图片 / 视频..."/>
              <UniformGrid Columns="3" Margin="0,10,0,0">
                <Button x:Name="BtnClear" Style="{StaticResource BtnGhost}" Content="恢复极光" Margin="0,0,5,0"/>
                <Button x:Name="BtnOpen"  Style="{StaticResource BtnGhost}" Content="壁纸文件夹" Margin="5,0"/>
                <Button x:Name="BtnRestart" Style="{StaticResource BtnGhost}" Content="重启 ZCode" Margin="5,0,0,0"/>
              </UniformGrid>
              <TextBlock x:Name="StatusText" Foreground="#8A90A0" FontSize="12" Margin="2,12,0,0" TextWrapping="Wrap"/>
              <TextBlock Foreground="#4E5464" FontSize="11" Margin="2,6,0,0"
                         Text="支持 mp4 / webm / gif / webp / png / jpg · 可以直接把文件拖进本窗口 · 新壁纸自动存入壁纸库"/>
            </StackPanel>
          </Grid>

          <!-- 页 2：壁纸库 -->
          <Grid x:Name="PageLib" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#101218" CornerRadius="10" Padding="14,10" Margin="0,0,0,10"
                    BorderBrush="#242835" BorderThickness="1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                  <TextBlock Text="打开 ZCode 时自动更换壁纸" Foreground="#ECECEC" FontSize="12.5"/>
                  <TextBlock Text="开启后每次打开 ZCode 自动换用下面勾选的下一张壁纸" Foreground="#6B7183" FontSize="10.5" Margin="0,2,0,0"/>
                </StackPanel>
                <CheckBox Grid.Column="1" x:Name="SwRotate" Style="{StaticResource Switch}" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <WrapPanel x:Name="LibPanel"/>
                <TextBlock x:Name="LibEmpty" Text="壁纸库为空 · 在「当前壁纸」页选择或拖入文件即可收藏"
                           Foreground="#6B7183" FontSize="12" HorizontalAlignment="Center" Margin="0,40,0,0"/>
              </StackPanel>
            </ScrollViewer>
            <TextBlock Grid.Row="2" Foreground="#4E5464" FontSize="10.5" Margin="2,8,0,0"
                       Text="单击卡片应用为当前壁纸（勾选「轮换」的壁纸参与自动更换）"/>
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
$previewEmpty = Ctrl 'PreviewEmpty'
$badge        = Ctrl 'Badge'
$badgeText    = Ctrl 'BadgeText'
$statusText   = Ctrl 'StatusText'
$previewArea  = Ctrl 'PreviewArea'
$libPanel     = Ctrl 'LibPanel'
$libEmpty     = Ctrl 'LibEmpty'
$swRotate     = Ctrl 'SwRotate'

# ── 工具函数 ─────────────────────────────────────────────
function Get-ThumbImage([string]$path) {
    # 返回 BitmapImage；视频走 Shell 缩略图
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'
    if ($path -match '\.(mp4|webm)$') {
        $thumb = [ShellThumb]::GetThumb($path, 400, 225)
        $ms = New-Object IO.MemoryStream
        $thumb.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $thumb.Dispose()
        $bi.StreamSource = $ms
    } else {
        $bi.UriSource = [Uri]$path
    }
    $bi.EndInit()
    return $bi
}

function Get-WallpaperFile {
    foreach ($e in @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')) {
        $f = Join-Path $wallDir "wallpaper.$e"
        if (Test-Path $f) { return $f }
    }
    return $null
}

function Show-Empty {
    $preview.Source = $null
    $preview.Visibility = 'Collapsed'
    $previewEmpty.Visibility = 'Visible'
    $badge.Visibility = 'Collapsed'
}

function Update-Preview {
    $f = Get-WallpaperFile
    if ($f) {
        try {
            $preview.Source = Get-ThumbImage $f
            $preview.Visibility = 'Visible'
            $previewEmpty.Visibility = 'Collapsed'
            $badge.Visibility = 'Visible'
            $badgeText.Text = '{0}  ({1:N1} MB)' -f (Split-Path $f -Leaf), ((Get-Item $f).Length / 1MB)
        } catch { Show-Empty }
    } else { Show-Empty }
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
    Copy-Item -Path $file -Destination (Join-Path $libDir $libName) -Force

    $cfg = Get-Config
    $entry = [pscustomobject]@{
        file  = $libName
        type  = $type
        rotate = $cfg.rotation
        added = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $cfg.items = @($cfg.items) + $entry
    Save-Config $cfg
    Rebuild-Rotate

    # 应用为当前壁纸
    Get-ChildItem -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item (Join-Path $libDir $libName) (Join-Path $wallDir "wallpaper$ext") -Force
    Update-Preview
    $statusText.Text = "已设置并收藏：$([IO.Path]::GetFileName($file))`n$([math]::Round((Get-Item $file).Length/1MB,1)) MB · 已存入壁纸库"
    Update-Library
}

function Apply-LibraryItem($item) {
    $src = Join-Path $libDir $item.file
    if (-not (Test-Path $src)) { return }
    Get-ChildItem -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item $src (Join-Path $wallDir ("wallpaper" + [IO.Path]::GetExtension($item.file))) -Force
    Update-Preview
    $msg = "已应用：$($item.file)"
    if ((Get-Config).rotation) { $msg += "`n注意：自动轮换开启中，下次打开 ZCode 仍会自动换张" }
    $statusText.Text = $msg
    (Ctrl 'TabNow').IsSelected = $true
}

function Update-Library {
    $cfg = Get-Config
    $swRotate.IsChecked = $cfg.rotation
    $libPanel.Children.Clear()
    $items = @($cfg.items)
    $libEmpty.Visibility = if ($items.Count -eq 0) { 'Visible' } else { 'Collapsed' }

    foreach ($it in $items) {
        $src = Join-Path $libDir $it.file
        if (-not (Test-Path $src)) { continue }

        $card = New-Object Windows.Controls.Border
        $card.Width = 154
        $card.CornerRadius = New-Object Windows.CornerRadius 8
        $card.Background = [Windows.Media.Brushes]::Transparent
        $card.BorderBrush = [Windows.Media.Brushes]::Transparent
        $card.BorderThickness = New-Object Windows.Thickness 1
        $card.Margin = New-Object Windows.Thickness 0, 0, 10, 10

        $panel = New-Object Windows.Controls.Grid
        $r0 = New-Object Windows.Controls.RowDefinition; $r0.Height = New-Object Windows.GridLength 84
        $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = [Windows.GridLength]::Auto
        $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = [Windows.GridLength]::Auto
        $panel.RowDefinitions.Add($r0); $panel.RowDefinitions.Add($r1); $panel.RowDefinitions.Add($r2)

        # 缩略图
        $img = New-Object Windows.Controls.Image
        $img.Stretch = 'UniformToFill'
        try { $img.Source = Get-ThumbImage $src } catch {}
        $img.Clip = $null
        [Windows.Controls.Grid]::SetRow($img, 0)
        $clipBorder = New-Object Windows.Controls.Border
        $clipBorder.CornerRadius = New-Object Windows.CornerRadius 8, 8, 0, 0
        $clipBorder.ClipToBounds = $true
        $clipBorder.Child = $img
        $panel.Children.Add($clipBorder) | Out-Null

        # 名称
        $name = New-Object Windows.Controls.TextBlock
        $name.Text = $it.file
        $name.FontSize = 10.5
        $name.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#9CA3AF')
        $name.TextTrimming = 'CharacterEllipsis'
        $name.Margin = New-Object Windows.Thickness 2, 3, 2, 0
        [Windows.Controls.Grid]::SetRow($name, 1)
        $panel.Children.Add($name) | Out-Null

        # 操作行：轮换 / 用 / 删
        $ops = New-Object Windows.Controls.StackPanel
        $ops.Orientation = 'Horizontal'
        $ops.Margin = New-Object Windows.Thickness 0, 4, 0, 2

        $cb = New-Object Windows.Controls.CheckBox
        $cb.Content = '轮换'
        $cb.IsChecked = [bool]$it.rotate
        $cb.FontSize = 10.5
        $cb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#8A90A0')
        $cb.VerticalAlignment = 'Center'
        $cb.Add_Click({
            $cbSelf = $this
            $it2 = $cbSelf.Tag
            $cfg2 = Get-Config
            foreach ($e2 in @($cfg2.items)) { if ($e2.file -eq $it2.file) { $e2.rotate = [bool]$cbSelf.IsChecked } }
            Save-Config $cfg2
            Rebuild-Rotate
        }.GetNewClosure())
        $cb.Tag = $it
        $ops.Children.Add($cb) | Out-Null

        $useBtn = New-Object Windows.Controls.Button
        $useBtn.Content = '应用'
        $useBtn.FontSize = 10.5
        $useBtn.Tag = $it
        $useBtn.Cursor = [Windows.Input.Cursors]::Hand
        $useBtn.Background = [Windows.Media.Brushes]::Transparent
        $useBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#60A5FA')
        $useBtn.Add_Click({
            $item = $this.Tag
            Apply-LibraryItem $item
        })
        $ops.Children.Add($useBtn) | Out-Null

        $delBtn = New-Object Windows.Controls.Button
        $delBtn.Content = '✕'
        $delBtn.FontSize = 10.5
        $delBtn.Tag = $it
        $delBtn.Cursor = [Windows.Input.Cursors]::Hand
        $delBtn.Background = [Windows.Media.Brushes]::Transparent
        $delBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6B7280')
        $delBtn.Margin = New-Object Windows.Thickness 6, 0, 0, 0
        $delBtn.Add_Click({
            $item = $this.Tag
            $cfg2 = Get-Config
            $cfg2.items = @($cfg2.items | Where-Object { $_.file -ne $item.file })
            Save-Config $cfg2
            Remove-Item (Join-Path $libDir $item.file) -Force -ErrorAction SilentlyContinue
            Rebuild-Rotate
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

(Ctrl 'TabNow').Add_Checked({ (Ctrl 'PageNow').Visibility = 'Visible'; (Ctrl 'PageLib').Visibility = 'Collapsed' })
(Ctrl 'TabLib').Add_Checked({ (Ctrl 'PageLib').Visibility = 'Visible';  (Ctrl 'PageNow').Visibility = 'Collapsed'; Update-Library })

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
    Get-ChildItem -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
    Update-Preview
    $statusText.Text = '已清除当前壁纸，重启 ZCode 后显示内置动态极光。'
})

(Ctrl 'BtnOpen').Add_Click({ Start-Process explorer.exe -ArgumentList "`"$wallDir`"" })

(Ctrl 'BtnRestart').Add_Click({
    $proc = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
    if (-not $proc) {
        [System.Windows.MessageBox]::Show('ZCode 未在运行，直接启动即可。', '提示', 'OK', 'Information') | Out-Null
        return
    }
    $exePath = ($proc | Select-Object -First 1).Path
    $answer = [System.Windows.MessageBox]::Show(
        "将关闭并重新启动 ZCode（$($proc.Count) 个相关进程）。任务会话已自动保存，重启后会恢复。`n`n确认重启？",
        '重启 ZCode', 'YesNo', 'Question')
    if ($answer -eq 'Yes') {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if ($exePath -and (Test-Path $exePath)) { Start-Process -FilePath $exePath }
        $window.Close()
    }
})

$swRotate.Add_Click({
    $cfg = Get-Config
    $cfg.rotation = [bool]$swRotate.IsChecked
    Save-Config $cfg
    Rebuild-Rotate
    $n = @($cfg.items | Where-Object { $_.rotate }).Count
    if ($cfg.rotation -and $n -eq 0) {
        $statusText.Text = '自动轮换已开启，但还没有勾选任何壁纸——去「壁纸库」把想轮换的勾上。'
        (Ctrl 'TabLib').IsSelected = $true
    } elseif ($cfg.rotation) {
        $statusText.Text = "自动轮换已开启（$n 张）。每次打开 ZCode 自动换用下一张。"
    } else {
        $statusText.Text = '自动轮换已关闭，将一直使用当前壁纸。'
    }
})

Update-Preview
Update-Library
[void]$window.ShowDialog()
