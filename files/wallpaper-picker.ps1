# zcode-wallpaper — ZCode 壁纸选择器（现代深色 UI）
# 选择图片或视频作为 ZCode 界面背景，支持拖拽文件到窗口，重启 ZCode 后生效。

Add-Type -AssemblyName PresentationFramework, WindowsBase, System.Drawing

$wallDir = Join-Path $env:USERPROFILE '.zcode\wallpaper'
if (-not (Test-Path $wallDir)) { New-Item -ItemType Directory -Path $wallDir -Force | Out-Null }

# ── Shell 视频缩略图（用于视频壁纸预览） ────────────────
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

    // PowerShell 无法对 __ComObject 做接口 cast，缩略图逻辑整体放在 C# 侧
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

# ── XAML 界面 ────────────────────────────────────────────
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ZCode 壁纸设置" Height="446" Width="500"
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
  </Window.Resources>

  <Border CornerRadius="14" Background="#1B1D23" BorderBrush="#2A2E3B" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="52"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
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

      <Border Grid.Row="1" CornerRadius="10" Background="#101218" Margin="20,0,20,0"
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

      <StackPanel Grid.Row="2" Margin="20,14,20,0">
        <Button x:Name="BtnPick" Style="{StaticResource BtnPrimary}" Content="选择图片 / 视频..."/>
        <UniformGrid Columns="3" Margin="0,10,0,0">
          <Button x:Name="BtnClear" Style="{StaticResource BtnGhost}" Content="恢复极光" Margin="0,0,5,0"/>
          <Button x:Name="BtnOpen"  Style="{StaticResource BtnGhost}" Content="壁纸文件夹" Margin="5,0"/>
          <Button x:Name="BtnRestart" Style="{StaticResource BtnGhost}" Content="重启 ZCode" Margin="5,0,0,0"/>
        </UniformGrid>
        <TextBlock x:Name="StatusText" Foreground="#8A90A0" FontSize="12" Margin="2,12,0,0" TextWrapping="Wrap"/>
        <TextBlock Foreground="#4E5464" FontSize="11" Margin="2,6,0,0"
                   Text="支持 mp4 / webm / gif / webp / png / jpg · 可以直接把文件拖进本窗口"/>
      </StackPanel>

      <Grid Grid.Row="3" Height="16"/>
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

# ── 工具函数 ─────────────────────────────────────────────
function Get-WallpaperFile {
    $exts = @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')
    foreach ($e in $exts) {
        $f = Join-Path $wallDir "wallpaper.$e"
        if (Test-Path $f) { return $f }
    }
    return $null
}

function Get-MediaThumb([string]$path) {
    # 返回可用于 Image.Source 的 BitmapImage；视频走 Shell 缩略图，图片直接加载
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'
    if ($path -match '\.(mp4|webm)$') {
        $thumb = [ShellThumb]::GetThumb($path, 800, 450)
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
            $preview.Source = Get-MediaThumb $f
            $preview.Visibility = 'Visible'
            $previewEmpty.Visibility = 'Collapsed'
            $badge.Visibility = 'Visible'
            $badgeText.Text = '{0}  ({1:N1} MB)' -f (Split-Path $f -Leaf), ((Get-Item $f).Length / 1MB)
        } catch {
            Show-Empty
        }
        $statusText.Text = '当前壁纸：' + $f
    } else {
        Show-Empty
        $statusText.Text = '当前壁纸：未设置（使用内置动态极光）'
    }
}

function Set-Wallpaper([string]$file) {
    $ext = [IO.Path]::GetExtension($file).ToLower().TrimStart('.')
    if ($ext -eq 'jpeg') { $ext = 'jpg' }
    if ($ext -notin @('mp4', 'webm', 'gif', 'webp', 'png', 'jpg')) {
        $statusText.Text = '不支持的文件类型：.' + $ext
        return
    }
    Get-ChildItem -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -Path $file -Destination (Join-Path $wallDir "wallpaper.$ext") -Force
    Update-Preview
    $statusText.Text = "已设置：$file`n点击「重启 ZCode」应用。"
}

# ── 事件 ─────────────────────────────────────────────────
(Ctrl 'DragBar').Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })

(Ctrl 'BtnClose').Add_Click({ $window.Close() })
(Ctrl 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })

(Ctrl 'BtnPick').Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = '选择壁纸'
    $dlg.Filter = '媒体文件|*.mp4;*.webm;*.gif;*.webp;*.png;*.jpg;*.jpeg|视频|*.mp4;*.webm|图片|*.gif;*.webp;*.png;*.jpg;*.jpeg|所有文件|*.*'
    if ($dlg.ShowDialog()) { Set-Wallpaper $dlg.FileName }
})

$previewArea.AllowDrop = $true
$window.Add_Drop({
    param($sender, $e)
    if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([Windows.DataFormats]::FileDrop)
        if ($files -and $files.Count -gt 0) { Set-Wallpaper $files[0] }
    }
    $e.Handled = $true
})

(Ctrl 'BtnClear').Add_Click({
    Get-ChildItem -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue | Remove-Item -Force
    Update-Preview
})

(Ctrl 'BtnOpen').Add_Click({ Start-Process explorer.exe -ArgumentList "`"$wallDir`"" })

(Ctrl 'BtnRestart').Add_Click({
    $proc = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
    if (-not $proc) {
        [System.Windows.MessageBox]::Show('ZCode 未在运行，直接启动即可。', '提示',
            'OK', 'Information') | Out-Null
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

Update-Preview
[void]$window.ShowDialog()
