// ai-wallpaper setup — 自解压安装器（给其他电脑一键部署用）
// 双击 → 把内嵌的 payload.zip 解压到 %USERPROFILE%\.ai-wallpaper\（统一选择器的固定部署目录）
//        → 三选一：
//   「是」  = 安装：ShellExecute 打开「安装补丁.cmd」（内部依次执行 install-all.ps1 与
//             deploy-shortcuts.ps1，窗口停在结果页）
//   「否」  = 卸载：打开「卸载.cmd」回滚全部应用补丁并删除工具目录（含系统设置里的卸载项）
//   「取消」= 便携模式：只部署文件，稍后双击目录里的「安装补丁.cmd」
// 构建：csc /target:winexe /win32icon:files/app.ico /resource:<payload.zip,ai-wallpaper.payload.zip>
//       /r:System.dll /r:System.IO.Compression.FileSystem.dll /r:System.IO.Compression.dll setup.cs
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;

static class Setup
{
    const uint MB_ICONWARNING = 0x30, MB_ICONINFORMATION = 0x40;
    const uint MB_YESNOCANCEL = 0x4;
    const uint IDYES = 6, IDNO = 7;

    [STAThread]
    static int Main()
    {
        string hub = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ai-wallpaper");

        // payload 内嵌为资源；单独 resources 数组避免 netstandard 差异
        var asm = Assembly.GetExecutingAssembly();
        using (Stream src = asm.GetManifestResourceStream("ai-wallpaper.payload.zip"))
        {
            if (src == null)
            {
                Msg("安装包损坏（缺少内嵌文件），请重新下载。", 0x30);
                return 1;
            }
            Directory.CreateDirectory(hub);
            string tmp = Path.Combine(Path.GetTempPath(), "aiwp-payload-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".zip");
            using (Stream dst = File.Create(tmp)) { src.CopyTo(dst); }
            try
            {
                using (ZipArchive zip = ZipFile.OpenRead(tmp))
                    foreach (ZipArchiveEntry e in zip.Entries)
                    {
                        // 拒绝路径穿越，只允许仓库相对路径
                        string full = Path.GetFullPath(Path.Combine(hub, e.FullName));
                        if (!full.StartsWith(hub, StringComparison.OrdinalIgnoreCase) || e.FullName.Contains(".."))
                            continue;
                        if (e.FullName.EndsWith("/") || e.FullName.EndsWith("\\"))
                        {
                            Directory.CreateDirectory(full);
                            continue;
                        }
                        Directory.CreateDirectory(Path.GetDirectoryName(full));
                        e.ExtractToFile(full, true);   // 已有文件直接覆盖（重复安装/升级场景）
                    }
            }
            catch (Exception ex) { Msg("解压失败：\n" + ex.Message, 0x30); return 1; }
            finally { try { File.Delete(tmp); } catch {} }
        }

        uint rc = MessageBoxW(IntPtr.Zero,
            "壁纸工具已部署到：\n" + hub + "\n\n" +
            "「是」= 立即为本机已安装的应用打补丁（自动运行，完成后桌面出现「AI壁纸设置」）\n" +
            "「否」= 卸载：回滚全部壁纸补丁并删除工具\n" +
            "「取消」= 暂不操作（便携模式，稍后双击目录里「安装补丁.cmd」）",
            "ai-wallpaper", 0x0 | MB_YESNOCANCEL | MB_ICONINFORMATION);

        // 两个分支都只打开随 payload 释放的固定 .cmd（结果由控制台窗口展示并 pause）。
        // 不拼接任何命令行、不创建参数化子进程：ShellExecute 直接以文件为对象启动。
        if (rc == IDYES)
        {
            OpenDocument(Path.Combine(hub, "安装补丁.cmd"));
        }
        else if (rc == IDNO)
        {
            OpenDocument(Path.Combine(hub, "卸载.cmd"));
        }
        else
        {
            Msg("文件已就绪（便携模式）：\n" +
                "双击目录里「安装补丁.cmd」打补丁，之后桌面「AI壁纸设置」换壁纸。", MB_ICONINFORMATION);
        }
        return 0;
    }

    // 以 ShellExecute「open」打开脚本文件（.cmd 的文件关联程序，独立控制台窗口）。
    // 路径仅由 %USERPROFILE%（环境固定值）+ 固定文件名拼成，不含任何外部输入；
    // Windows 文件名禁止引号字符，此处断言把该前提固化为硬校验。
    static void OpenDocument(string path)
    {
        if (string.IsNullOrEmpty(path) || path.IndexOf('"') >= 0)
            throw new ArgumentException("document path must not contain quotes");
        IntPtr h = ShellExecuteW(IntPtr.Zero, "open", path, null, null, 1 /* SW_SHOWNORMAL */);
        if (h.ToInt64() <= 32)
        {
            Msg("无法打开 " + path + "（ShellExecute 错误 " + h.ToInt64() + "）。" +
                "请到安装目录手动双击对应 .cmd。", MB_ICONWARNING);
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern uint MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern IntPtr ShellExecuteW(IntPtr hWnd, string verb, string file, string parameters, string directory, int showCmd);

    static void Msg(string text, uint icon)
    {
        MessageBoxW(IntPtr.Zero, text, "ai-wallpaper", 0x0 | icon);
    }
}
