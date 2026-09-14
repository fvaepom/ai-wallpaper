// ai-wallpaper setup — 自解压安装器（给其他电脑一键部署用）
// 双击 → 把内嵌的 payload.zip 解压到 %USERPROFILE%\.ai-wallpaper\（统一选择器的固定部署目录）
//        → 询问是否立即运行 install-all.ps1 为本机已安装的应用打补丁。
// 构建：csc /target:winexe /win32icon:files/app.ico /resource:<payload.zip,ai-wallpaper.payload.zip> setup.cs
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;

static class Setup
{
    const uint MB_ICONWARNING = 0x30, MB_ICONINFORMATION = 0x40;

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

        // 不在本进程内启动任何子进程/命令：解压完成后由用户自行双击
        // 「安装补丁.cmd」（一键打补丁）或「使用说明.txt」
        Msg("壁纸工具已安装到：\n" + hub + "\n\n" +
            "下一步（二选一）：\n" +
            "1) 双击该目录里的「安装补丁.cmd」→ 自动为本机已安装的应用打补丁\n" +
            "   （未安装的应用自动跳过；个别应用可能请求管理员授权）\n" +
            "2) 打完补丁后，双击桌面「AI壁纸设置」换壁纸\n\n" +
            "更多说明见安装目录里的 使用说明.txt", MB_ICONINFORMATION);
        return 0;
    }

    static uint MessageBox(IntPtr h, string text, string caption, uint type)
    {
        return MessageBoxW(h, text, caption, type);
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern uint MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    static void Msg(string text, uint icon)
    {
        MessageBoxW(IntPtr.Zero, text, "ai-wallpaper", 0x0 | icon);
    }
}
