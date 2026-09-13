;/* zcode-wallpaper bridge: wp:// protocol serving %USERPROFILE%\.opencode\wallpaper */
;(async function () {
  try {
    const electron = await import('electron');
    const mod = electron.default ?? electron;
    const path = await import('node:path');
    const os = await import('node:os');
    const fs = await import('node:fs');
    const WP_ROOT = path.join(os.homedir(), '.opencode', 'wallpaper');
    const registerWp = () => {
      try {
        if (mod.protocol.isProtocolHandled('wp')) return;
        mod.protocol.handle('wp', async (request) => {
          try {
            const u = new URL(request.url);
            const rel = decodeURIComponent((u.pathname || '').replace(/^\/+/, ''));
            if (!rel || rel.includes('..') || !/^[A-Za-z0-9._\-\/ ]+$/.test(rel)) {
              return new Response('forbidden', { status: 403 });
            }
            const file = path.join(WP_ROOT, rel);
            if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
              return new Response('not found', { status: 404 });
            }
            const range = request.headers.get('range');
            return await mod.net.fetch('file:///' + file.split('\\').join('/'), {
              headers: range ? { range } : undefined
            });
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
