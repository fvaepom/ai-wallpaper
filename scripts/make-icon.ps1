# 生成 ai-wallpaper 应用图标：蓝紫渐变圆角底 + 白色山形 + 太阳
Add-Type -AssemblyName System.Drawing

$outDir = 'H:\zcode改造\zcode-wallpaper\files'
$tmpDir = Join-Path $env:TEMP 'zwp-icon'
New-Item -ItemType Directory $tmpDir -Force | Out-Null

function New-IconPng([int]$size, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $pad = [single]($size * 0.04)
    $w = $size - $pad * 2
    $radius = [single]($w * 0.24)

    $bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bgPath.AddArc($pad, $pad, $radius, $radius, 180, 90)
    $bgPath.AddArc($pad + $w - $radius, $pad, $radius, $radius, 270, 90)
    $bgPath.AddArc($pad + $w - $radius, $pad + $w - $radius, $radius, $radius, 0, 90)
    $bgPath.AddArc($pad, $pad + $w - $radius, $radius, $radius, 90, 90)
    $bgPath.CloseFigure()

    $c1 = [System.Drawing.Color]::FromArgb(255, 59, 130, 246)
    $c2 = [System.Drawing.Color]::FromArgb(255, 124, 58, 237)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        [System.Drawing.Point]::new([int]$pad, [int]$pad),
        [System.Drawing.Point]::new([int]($pad + $w), [int]($pad + $w)),
        $c1, $c2)
    $g.FillPath($grad, $bgPath)
    $grad.Dispose()
    $bgPath.Dispose()

    # 太阳
    $sunR = [single](0.09 * $w)
    $sunX = [single]($pad + 0.66 * $w)
    $sunY = [single]($pad + 0.28 * $w)
    $g.FillEllipse([System.Drawing.Brushes]::White, $sunX - $sunR, $sunY - $sunR, $sunR * 2, $sunR * 2)

    # 山形
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 255, 255, 255))
    $pts = New-Object 'System.Drawing.PointF[]' 6
    $pts[0] = [System.Drawing.PointF]::new([single]($pad + 0.14 * $w), [single]($pad + 0.80 * $w))
    $pts[1] = [System.Drawing.PointF]::new([single]($pad + 0.40 * $w), [single]($pad + 0.32 * $w))
    $pts[2] = [System.Drawing.PointF]::new([single]($pad + 0.58 * $w), [single]($pad + 0.58 * $w))
    $pts[3] = [System.Drawing.PointF]::new([single]($pad + 0.70 * $w), [single]($pad + 0.42 * $w))
    $pts[4] = [System.Drawing.PointF]::new([single]($pad + 0.88 * $w), [single]($pad + 0.80 * $w))
    $pts[5] = [System.Drawing.PointF]::new([single]($pad + 0.14 * $w), [single]($pad + 0.80 * $w))
    $g.FillPolygon($white, $pts)
    $white.Dispose()

    # 底部反光条
    $barH = [single](0.045 * $w)
    $barBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(80, 255, 255, 255))
    $g.FillRectangle($barBrush, [single]($pad + 0.14 * $w), [single]($pad + 0.845 * $w), [single](0.72 * $w), $barH)
    $barBrush.Dispose()

    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$sizes = @(256, 128, 64, 48, 32, 16)
$pngs = @()
foreach ($sz in $sizes) {
    $p = Join-Path $tmpDir ("icon-$sz.png")
    New-IconPng $sz $p
    $pngs += , @($sz, $p)
}

# 组装 ICO（PNG-in-ICO）
$icoPath = Join-Path $outDir 'app.ico'
$ms = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
    $bytes = [IO.File]::ReadAllBytes($p[1])
    $szb = 0
    if ($p[0] -lt 256) { $szb = $p[0] }
    $bw.Write([byte]$szb); $bw.Write([byte]$szb)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $bytes.Length
}
foreach ($p in $pngs) { $bw.Write([IO.File]::ReadAllBytes($p[1])) }
$bw.Flush()
[IO.File]::WriteAllBytes($icoPath, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

Copy-Item (Join-Path $tmpDir 'icon-256.png') 'H:\zcode改造\zcode-wallpaper\docs\icon-preview.png' -Force
Write-Output ('ICO_DONE ' + (Get-Item $icoPath).Length + ' bytes')
