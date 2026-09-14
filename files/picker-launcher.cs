// AI壁纸设置 launcher - 把统一选择器打包成 exe：
// 双击 → 经 WScript.Shell 以隐藏窗口（0）拉起 hub 里的 wallpaper-picker.ps1，无控制台黑窗。
// 内置 AUMID（AI.WallpaperPicker），任务栏图标正确。与 wallpaper-picker.vbs 行为一致。
using System;
using System.IO;
using System.Runtime.InteropServices;

static class Launcher
{
    private const string RunCommand =
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%USERPROFILE%\\.ai-wallpaper\\wallpaper-picker.ps1\"";

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    static int Main()
    {
        SetCurrentProcessExplicitAppUserModelID("AI.WallpaperPicker");
        string ps1 = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".ai-wallpaper", "wallpaper-picker.ps1");
        if (!File.Exists(ps1))
        {
            const uint MB_ICONWARNING = 0x30;
            MessageBoxW(IntPtr.Zero,
                "未找到壁纸设置工具，请先在本仓库运行 apply-patch.ps1 安装。",
                "AI壁纸设置", MB_ICONWARNING);
            return 1;
        }
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        object shell = Activator.CreateInstance(shellType);
        // Run(command, 0 = 隐藏窗口, false = 不等待)
        shellType.InvokeMember("Run", System.Reflection.BindingFlags.InvokeMethod,
            null, shell, new object[] { RunCommand, 0, false });
        return 0;
    }
}
