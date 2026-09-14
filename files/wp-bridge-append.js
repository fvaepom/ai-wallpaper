;/* zcode-wallpaper bridge: wp:// protocol serving wallpaper dir (%__WP_HOME_REL__%) */
;/* __WP_HOME_REL__ 由 apply-patch.ps1 替换为各应用的壁纸目录相对路径（如 .codex/wallpaper） */
;(async function () {
  try {
    const electron = await import('electron');
    const mod = electron.default ?? electron;
    const path = await import('node:path');
    const os = await import('node:os');
    const fs = await import('node:fs');
    const WP_ROOT = path.join(os.homedir(), ...'__WP_HOME_REL__'.split('/'));
    const MIME = { '.mp4': 'video/mp4', '.webm': 'video/webm', '.gif': 'image/gif',
                   '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg',
                   '.jpeg': 'image/jpeg', '.css': 'text/css' };
    const registerWp = () => {
      try {
        /* 注意：不能用 protocol.isProtocolHandled 做守卫（新版 Electron 已移除该 API，
           调用即抛错 → handle 从未注册，Codex 桌面版 2026-09-15 实测踩坑）。
           直接注册；若真的重复注册，抛错走 catch 即可 */
        mod.protocol.handle('wp', async (request) => {
          try {
            const u = new URL(request.url);
            const rel = decodeURIComponent((u.pathname || '').replace(/^\/+/, ''));
            if (!rel || rel.includes('..') || !/^[A-Za-z0-9._\-\/ ]+$/.test(rel)) {
              return new Response('forbidden', { status: 403 });
            }
            /* 双重防护：resolve 后必须仍落在壁纸根目录内，越界一律 403 */
            const file = path.resolve(WP_ROOT, rel);
            if (file !== WP_ROOT && !file.startsWith(WP_ROOT + path.sep)) {
              return new Response('forbidden', { status: 403 });
            }
            if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
              return new Response('not found', { status: 404 });
            }
            /* 直接用 fs 读文件：net.fetch 的 file:// 在部分 Electron 版本不可用。
               实现 Range（视频拖动进度条必需），未带 Range 返回整文件 */
            const stat = fs.statSync(file);
            const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
            const range = request.headers.get('range');
            const m = range && range.match(/bytes=(\d*)-(\d*)/);
            if (m && (m[1] !== '' || m[2] !== '')) {
              let start = m[1] !== '' ? parseInt(m[1], 10) : Math.max(0, stat.size - parseInt(m[2], 10));
              let end = m[1] !== '' && m[2] !== '' ? parseInt(m[2], 10) : stat.size - 1;
              if (isNaN(start) || isNaN(end) || start < 0 || start >= stat.size || end < start) {
                return new Response('range error', { status: 416, headers: { 'Content-Range': 'bytes */' + stat.size } });
              }
              end = Math.min(end, stat.size - 1);
              const len = end - start + 1;
              const buf = Buffer.alloc(len);
              const fh = await fs.promises.open(file, 'r');
              try { await fh.read(buf, 0, len, start); } finally { await fh.close(); }
              return new Response(buf, { status: 206, headers: {
                'Content-Type': type, 'Content-Length': String(len), 'Accept-Ranges': 'bytes',
                'Content-Range': 'bytes ' + start + '-' + end + '/' + stat.size } });
            }
            return new Response(fs.readFileSync(file), { status: 200, headers: {
              'Content-Type': type, 'Content-Length': String(stat.size), 'Accept-Ranges': 'bytes' } });
          } catch (e) {
            return new Response('error', { status: 500 });
          }
        });
      } catch (e) {}
    };
    if (mod.app.isReady()) registerWp();
    else mod.app.whenReady().then(registerWp);
  } catch (e) {}
})();
