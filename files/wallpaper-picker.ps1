# zcode-wallpaper — ZCode 壁纸选择器
# 选择图片或视频作为 ZCode 界面背景，重启 ZCode 后生效。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$wallDir = Join-Path $env:USERPROFILE '.zcode\wallpaper'
if (-not (Test-Path $wallDir)) { New-Item -ItemType Directory -Path $wallDir -Force | Out-Null }

$form                    = New-Object System.Windows.Forms.Form
$form.Text               = 'ZCode 壁纸设置'
$form.Size               = New-Object System.Drawing.Size(440, 230)
$form.FormBorderStyle    = 'FixedDialog'
$form.StartPosition      = 'CenterScreen'
$form.MaximizeBox        = $false
$form.TopMost            = $true

$status                  = New-Object System.Windows.Forms.Label
$status.AutoSize         = $false
$status.Size             = New-Object System.Drawing.Size(400, 44)
$status.Location         = New-Object System.Drawing.Point(16, 12)
$status.Font             = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

function Get-StatusText {
    $files = Get-ChildItem -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue
    if ($files) {
        $f = $files[0]
        "当前壁纸：$($f.Name)  ($([math]::Round($f.Length/1MB,1)) MB)`n来源：$wallDir"
    } else {
        "当前壁纸：（未设置，使用内置动态极光）`n壁纸目录：$wallDir"
    }
}
$status.Text = Get-StatusText
$form.Controls.Add($status)

$btnPick                 = New-Object System.Windows.Forms.Button
$btnPick.Text            = '选择图片 / 视频...'
$btnPick.Size            = New-Object System.Drawing.Size(180, 34)
$btnPick.Location        = New-Object System.Drawing.Point(16, 70)
$form.Controls.Add($btnPick)

$btnClear                = New-Object System.Windows.Forms.Button
$btnClear.Text           = '恢复默认极光'
$btnClear.Size           = New-Object System.Drawing.Size(180, 34)
$btnClear.Location       = New-Object System.Drawing.Point(220, 70)
$form.Controls.Add($btnClear)

$btnOpen                 = New-Object System.Windows.Forms.Button
$btnOpen.Text            = '打开壁纸文件夹'
$btnOpen.Size            = New-Object System.Drawing.Size(180, 34)
$btnOpen.Location        = New-Object System.Drawing.Point(16, 116)
$form.Controls.Add($btnOpen)

$btnRestart              = New-Object System.Windows.Forms.Button
$btnRestart.Text         = '重启 ZCode 生效'
$btnRestart.Size         = New-Object System.Drawing.Size(180, 34)
$btnRestart.Location     = New-Object System.Drawing.Point(220, 116)
$form.Controls.Add($btnRestart)

$hint                    = New-Object System.Windows.Forms.Label
$hint.AutoSize           = $false
$hint.Size               = New-Object System.Drawing.Size(400, 40)
$hint.Location           = New-Object System.Drawing.Point(16, 160)
$hint.ForeColor          = 'Gray'
$hint.Font               = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.25)
$hint.Text               = '支持 mp4 / webm 视频（静音循环）和 gif / webp / png / jpg 图片。设置后需重启 ZCode。'
$form.Controls.Add($hint)

$btnPick.Add_Click({
    $dlg          = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title    = '选择壁纸'
    $dlg.Filter   = '媒体文件|*.mp4;*.webm;*.gif;*.webp;*.png;*.jpg;*.jpeg|视频文件|*.mp4;*.webm|图片文件|*.gif;*.webp;*.png;*.jpg;*.jpeg|所有文件|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Remove-Item -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue
            $ext = [IO.Path]::GetExtension($dlg.FileName).ToLower().TrimStart('.')
            if ($ext -eq 'jpeg') { $ext = 'jpg' }
            Copy-Item -Path $dlg.FileName -Destination (Join-Path $wallDir "wallpaper.$ext") -Force
            $status.Text = Get-StatusText
            [System.Windows.Forms.MessageBox]::Show(
                "壁纸已设置：`n$($dlg.FileName)`n`n点击「重启 ZCode 生效」，或手动重启 ZCode。",
                '设置成功', [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("设置失败：$($_.Exception.Message)",
                '错误', [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }
})

$btnClear.Add_Click({
    Remove-Item -Path (Join-Path $wallDir 'wallpaper.*') -ErrorAction SilentlyContinue
    $status.Text = Get-StatusText
    [System.Windows.Forms.MessageBox]::Show('已清除壁纸，重启 ZCode 后恢复内置动态极光。',
        '完成', [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

$btnOpen.Add_Click({
    Start-Process explorer.exe -ArgumentList "`"$wallDir`""
})

$btnRestart.Add_Click({
    $proc = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
    if (-not $proc) {
        [System.Windows.Forms.MessageBox]::Show('ZCode 未在运行，直接启动即可。', '提示',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $exePath = ($proc | Select-Object -First 1).Path
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "将关闭并重新启动 ZCode（$($proc.Count) 个相关进程）。任务会话已自动保存，重启后会恢复。`n`n确认重启？",
        '重启 ZCode', [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if ($exePath -and (Test-Path $exePath)) { Start-Process -FilePath $exePath }
        $form.Close()
    }
})

[void]$form.ShowDialog()
