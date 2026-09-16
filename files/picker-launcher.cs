// AI壁纸设置 launcher - 双击直接拉起 hub 里的 wallpaper-picker.ps1（隐藏 powershell，无黑窗）。
// 不经 WScript.Shell：安全软件常拦截「wscript 隐藏启动 powershell」组合，COM 也可能被策略禁用；
// 改由本 GUI 进程直接 CreateProcess powershell（CREATE_NO_WINDOW）。picker 脚本崩溃时
// 弹窗 + 写 %USERPROFILE%\.ai-wallpaper\picker-error.log，不再静默消失。
// 内置 AUMID（AI.WallpaperPicker），任务栏图标正确。构建：scripts\build-picker-exe.ps1
using System;
using System.IO;
using System.Runtime.InteropServices;

static class Launcher
{
    [DllImport("shell32.dll")] private static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr ShellExecuteW(IntPtr hWnd, string verb, string file, string args, string dir, int showCmd);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(string applicationName, string commandLine, IntPtr processAttrs, IntPtr threadAttrs, bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory, ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInfo);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr h);

    private const uint CREATE_NO_WINDOW = 0x08000000;

    [StructLayout(LayoutKind.Sequential)]
    private struct STARTUPINFO
    {
        public uint cb; public IntPtr lpReserved; public IntPtr lpDesktop; public IntPtr lpTitle;
        public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public ushort wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public uint dwProcessId, dwThreadId; }

    static void Msg(string text, uint icon) { MessageBoxW(IntPtr.Zero, text, "AI壁纸设置", 0x0 | icon); }

    [STAThread]
    static int Main()
    {
        SetCurrentProcessExplicitAppUserModelID("AI.WallpaperPicker");
        string hub = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ai-wallpaper");
        string ps1 = Path.Combine(hub, "wallpaper-picker.ps1");
        if (!File.Exists(ps1))
        {
            Msg("未找到壁纸设置工具（" + ps1 + "）。请先运行安装器或 apply-patch.ps1 安装。", 0x30);
            return 1;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "windowspowershell\\v1.0\\powershell.exe");
        if (!File.Exists(ps)) ps = "powershell.exe";

        // 命令行只由固定环境值 + 固定文件名拼成，不含任何外部输入；Windows 文件名禁止
        // 引号字符，此处断言把该前提固化为硬校验（引号会破坏 PS 单引号路径转义）
        if (ps1.IndexOf('"') >= 0 || ps.IndexOf('"') >= 0)
        {
            Msg("安装路径含非法引号字符，无法启动。", 0x30);
            return 1;
        }
        // picker 脚本任何崩溃 → 弹窗 + 写 picker-error.log（隐藏窗口里不再无声消失）
        string args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"try { & '" + ps1 +
            "' } catch { $_ | Out-File '" + hub + "\\picker-error.log' -Encoding UTF8; " +
            "Add-Type -AssemblyName System.Windows.Forms; " +
            "[void][System.Windows.Forms.MessageBox]::Show(($_ | Out-String), 'AI壁纸设置 启动失败') }\"";

        STARTUPINFO si = new STARTUPINFO();
        si.cb = (uint)Marshal.SizeOf(si);
        PROCESS_INFORMATION pi;
        if (CreateProcessW(ps, "\"" + ps + "\" " + args, IntPtr.Zero, IntPtr.Zero, false,
                CREATE_NO_WINDOW, IntPtr.Zero, hub, ref si, out pi))
        {
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
            return 0;
        }
        // 主路径失败：退到可见的 cmd 入口（至少能打开、能看到报错），再失败才弹错误框
        string cmd = Path.Combine(hub, "AI壁纸设置.cmd");
        if (File.Exists(cmd))
        {
            IntPtr r = ShellExecuteW(IntPtr.Zero, "open", cmd, null, hub, 1 /* SW_SHOWNORMAL */);
            if (r.ToInt64() > 32) return 0;
        }
        Msg("启动壁纸设置失败（Win32 错误 " + Marshal.GetLastWin32Error() + "）。" +
            "请到 " + hub + " 双击「AI壁纸设置.cmd」，或把 picker-error.log 发给维护者。", 0x30);
        return 1;
    }
}
