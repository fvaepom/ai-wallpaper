/* zwp-ver:2 (2026-09-16) — 体检/apply-patch 据此识别已部署脚本是否为旧版 */
/* ai-wallpaper — 壁纸层 + 界面透明化注入脚本（DeepSeek Harness 桌面端专用变体）
 *
 * 由 apply-patch.ps1 以【内联】方式注入到 DSH Desktop（开源 DeepSeek Harness 桌面壳，
 * github.com/anywhere-labs/dsh-desktop）的前端页：
 *   <安装目录>\resources\app\node_modules\@deepseek-ai\dsh-web-frontend\dist\index.html
 * 主窗口由 Electron 壳 loadURL 到本机回环 webserver（动态端口），页面源 = 上述 dist；
 * 壁纸媒体 / custom.css / 轮换标记由本机回环 HTTP 媒体服务（127.0.0.1:19399）供给，
 * __WALLPAPER_DIR__ 指向 http://127.0.0.1:19399/dsh（媒体服务的 dsh 虚拟根）。
 * ⚠ 外壳对「跨源 + 带查询串」的请求一律拦截（同源带串、跨源无串均正常，实测）——
 * 因此本变体不用 ?v= 缓存穿透（与 Marvis 同款限制）：轮换集（不同 URL）热切换正常，
 * 选择器对同名 wallpaper.* 的就地覆盖需重启应用后可见。
 * 壁纸查找顺序：
 *   1. 自动轮换（检测到 <壁纸目录>\rotate\rotate-1.* 时启用）：
 *      每次页面加载按 localStorage 计数器换下一张 rotate-N.*
 *   2. <壁纸目录>\wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 都没有 → 内置"动态极光渐变"兜底
 * （__WALLPAPER_DIR__ 占位符由 apply-patch.ps1 替换）
 */
;(function () {
  if (document.getElementById('oc-wallpaper')) return;

  /* ── 可调参数（custom.css 可覆盖大部分） ────── */
  var CONFIG = {
    videoOpacity: 0.9,  // 视频壁纸不透明度 0~1
    imageOpacity: 0.9,  // 图片/动图壁纸不透明度
    darkOverlay: 0.18   // 壁纸上的暗色遮罩 0~1，调大文字更清楚
  };

  /* ── 界面透明化 + 壁纸层样式 ────────────────── */
  var style = document.createElement('style');
  style.id = 'oc-wallpaper-style';
  style.textContent = [
    '#oc-wallpaper{position:fixed;inset:0;z-index:-1;overflow:hidden;pointer-events:none;',
    '  background:linear-gradient(160deg,#0b0f1a 0%,#101828 50%,#0b1120 100%);}',
    '#oc-wallpaper video,#oc-wallpaper img{width:100%;height:100%;object-fit:cover;display:block;}',
    '#oc-wallpaper .oc-wp-shade{position:absolute;inset:0;background:rgba(0,0,0,' + CONFIG.darkOverlay + ');}',

    /* 兜底：动态极光渐变（未检测到壁纸文件时显示）。
       光斑用径向渐变自带羽化、动画只走 transform——不用 blur / mix-blend-mode /
       filter 动画，那三类每帧都强制离屏合成与重栅格化，是全屏 GPU 开销的大头。
       关掉动画（性能模式）：在 custom.css 里加一行
       #oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{animation:none !important} */
    '#oc-wallpaper.aurora{background:radial-gradient(55% 70% at 62% 38%,rgba(14,165,233,.22) 0%,transparent 70%),linear-gradient(160deg,#0b0f1a 0%,#101828 50%,#0b1120 100%);}',
    '#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{',
    '  content:"";position:absolute;width:90vmax;height:90vmax;border-radius:50%;',
    '  will-change:transform;}',
    '#oc-wallpaper.aurora::before{',
    '  background:radial-gradient(circle at 50% 50%,rgba(59,130,246,.6) 0%,rgba(29,78,216,.32) 32%,transparent 68%);',
    '  top:-30%;left:-20%;animation:oc-drift-a 26s ease-in-out infinite alternate;}',
    '#oc-wallpaper.aurora::after{',
    '  background:radial-gradient(circle at 50% 50%,rgba(168,85,247,.55) 0%,rgba(109,40,217,.3) 34%,transparent 68%);',
    '  bottom:-35%;right:-25%;animation:oc-drift-b 32s ease-in-out infinite alternate;}',
    '@keyframes oc-drift-a{0%{transform:translate(0,0) scale(1) rotate(0deg);}',
    '  50%{transform:translate(12vw,8vh) scale(1.15) rotate(20deg);}',
    '  100%{transform:translate(4vw,16vh) scale(.95) rotate(-10deg);}}',
    '@keyframes oc-drift-b{0%{transform:translate(0,0) scale(1);}',
    '  50%{transform:translate(-10vw,-10vh) scale(1.2);}',
    '  100%{transform:translate(-4vw,-4vh) scale(.9);}}',
    '@media (prefers-reduced-motion: reduce){#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{animation:none;}}',

    /* DeepSeek Harness（开源 DSH Desktop，Electron 壳 + Vite/React 前端，
       主题令牌为 --dsw-alias-*，定义在 body（浅色）与 body[data-ds-dark-theme]（深色））：
       基底令牌透明让壁纸透出；主面板令牌 layer-1 改为按主题半透明磨砂
       （浅色 ≈ bluish-00 #fff、深色 ≈ bluish-875 #232324 的 alpha 版）——
       全透明会把深色文字直接叠在壁纸上导致不可读，磨砂层同时保住对比度与透出度，
       可在 custom.css 里调 --ocwp-ui-alpha（0~1，越小越透）。boot 启动屏引用
       --dsw-alias-bg-base 自动跟着透明；卡片/弹层 layer-2/3 保持原色保证可读性；
       个别写死颜色的大色块由下方运行时扫描兜底 */
    'html,body{background:transparent !important;}',
    '#root,#app,#wrapper{background:transparent !important;}',
    'body{',
    '  --dsw-alias-bg-base:transparent !important;',
    '  --dsw-alias-bg-layer-1:rgba(250,250,252,var(--ocwp-ui-alpha,.72)) !important;}',
    'body[data-ds-dark-theme]{',
    '  --dsw-alias-bg-base:transparent !important;',
    '  --dsw-alias-bg-layer-1:rgba(30,30,32,var(--ocwp-ui-alpha,.66)) !important;}'
  ].join('\n');
  document.head.appendChild(style);

  /* ── 壁纸层 ──────────────────────────────── */
  var layer = document.createElement('div');
  layer.id = 'oc-wallpaper';
  layer.className = 'aurora'; // 先显示兜底渐变，找到壁纸文件后替换
  (document.body || document.documentElement).appendChild(layer);

  // 皮肤生效标记：窗口标题出现 ✦ 即说明本脚本已运行（DSH 外壳可能固定标题，
  // 被覆盖时以壁纸可见为准）
  try { document.title += ' ✦'; } catch (e) {}

  /* ── 大面积不透明色块自动降透明（React 界面存在写死静态色的表面，
     CSS 猜测不可靠 → 运行时扫描：盖住几乎整个视口、或全高侧栏的大块纯色背景，
     统一压到 alpha 0.45。React 异步挂载 + 路由切换，延迟多跑几遍。
     卡片/弹窗等小块不动，保证可读性；个别想不透明的场景在 custom.css 里
     对具体元素加回背景即可 ── */
  function deopaque() {
    try {
      if (!document.body) return;
      var vw = innerWidth, vh = innerHeight;
      var all = document.body.getElementsByTagName('*');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        if (el.id === 'oc-wallpaper') continue;
        var r = el.getBoundingClientRect();
        if (r.width < 10 || r.height < 10) continue;
        var full = (r.width >= vw * 0.95 && r.height >= vh * 0.95);
        var tall = (r.height >= vh * 0.85 && r.width >= 120 && r.width <= vw * 0.6);
        if (!full && !tall) continue;
        var bg = getComputedStyle(el).backgroundColor;
        var m = bg && bg.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/);
        if (!m) continue;
        var a = (m[4] === undefined) ? 1 : parseFloat(m[4]);
        if (a >= 0.85) {
          el.style.setProperty('background-color',
            'rgba(' + m[1] + ',' + m[2] + ',' + m[3] + ',0.45)', 'important');
        }
      }
    } catch (e) {}
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { deopaque(); });
  } else { deopaque(); }
  setTimeout(deopaque, 2500);
  setTimeout(deopaque, 6000);

  /* ── 用户自定义微调：wallpaper 目录下的 custom.css（热加载） ── */
  var WALLPAPER_DIR = '__WALLPAPER_DIR__/'; // 占位符，由 apply-patch.ps1 替换
  var hasUserDir = WALLPAPER_DIR.indexOf('__') === -1;
  var ROTATE_DIR = hasUserDir ? WALLPAPER_DIR + 'rotate/' : null;
  var exts = ['mp4', 'webm', 'gif', 'webp', 'png', 'jpg'];

  if (hasUserDir) {
    try {
      var customLink = document.createElement('link');
      customLink.rel = 'stylesheet';
      customLink.id = 'ocwp-custom';
      customLink.href = WALLPAPER_DIR + 'custom.css';
      document.head.appendChild(customLink);
    } catch (e) {}
  }

  function reloadCustomCss() {
    if (!hasUserDir) return;
    try {
      var old = document.getElementById('ocwp-custom');
      if (old) old.parentNode.removeChild(old);
      var l = document.createElement('link');
      l.rel = 'stylesheet';
      l.id = 'ocwp-custom';
      l.href = WALLPAPER_DIR + 'custom.css';
      document.head.appendChild(l);
    } catch (e) {}
  }

  function addShade() {
    var shade = document.createElement('div');
    shade.className = 'oc-wp-shade';
    layer.appendChild(shade);
  }

  function applyMedia(el) {
    layer.className = '';
    layer.innerHTML = '';
    el.style.opacity = (el.tagName === 'VIDEO' ? CONFIG.videoOpacity : CONFIG.imageOpacity);
    layer.appendChild(el);
    addShade();
    if (el.tagName === 'VIDEO') {
      /* 跳过开头黑场：壁纸视频常有数秒暗场/标题卡开头，自动播放被外壳的 autoplay
         策略拦下时，暂停画面停留其上 = 整窗近黑；seek 到第 2 秒让静态帧有内容，
         播放由下方首次交互手势解锁（DSH 的 webPreferences 限 user-gesture-required） */
      try {
        var d = el.duration;
        if (isFinite(d) && d > 4) el.currentTime = 2;
      } catch (e) {}
      el.play().catch(function () {});
    }
  }

  /* 探测一个媒体 URL：成功回调 el，失败回调 fail */
  function loadMedia(url, onOk, onFail, timeoutMs) {
    var isVideo = /\.(mp4|webm)$/i.test(url.split('?')[0]); // 去掉缓存穿透参数再判断扩展名
    if (isVideo) {
      var v = document.createElement('video');
      var done = false;
      v.muted = true;
      v.loop = true;
      v.autoplay = true;
      v.playsInline = true;
      v.addEventListener('loadeddata', function () {
        if (done) return; done = true; onOk(v);
      });
      v.addEventListener('error', function () {
        if (done) return; done = true; onFail();
      });
      v.src = url;
      setTimeout(function () {
        if (!done) { done = true; v.removeAttribute('src'); v.load(); onFail(); }
      }, timeoutMs || 5000);
    } else {
      var img = new Image();
      img.onload = function () { onOk(img); };
      img.onerror = onFail;
      img.src = url;
    }
  }

  /* 依次探测 url 列表（串行，命中即止） */
  function probeList(urls, onOk, onExhausted) {
    var i = 0;
    (function next() {
      if (i >= urls.length) { onExhausted(); return; }
      var url = urls[i++];
      loadMedia(url, function (el) { onOk(el); }, next);
    })();
  }

  /* ── 1) 自动轮换：rotate/rotate-N.* 存在即启用 ── */
  var INTERVALS = [1, 5, 15, 30, 60, 120]; // 选择器可生成的换片间隔（分钟）
  var intervalTimer = null;

  /* bust = 缓存穿透串（热切换重探时传时间戳）：同名文件被选择器覆盖后，
     Chromium 可能仍回旧缓存图，带 ?v= 强制按磁盘现值重载 */
  function rotateStart(bust) {
    var idx = 0;
    try { idx = parseInt(localStorage.getItem('oc-wp-idx') || '0', 10) || 0; } catch (e) {}
    tryRotate(idx + 1, bust);
    detectInterval(0, bust); // 探测 interval-N.gif → 有则启动定时换片
  }

  function detectInterval(i, bust) {
    if (i >= INTERVALS.length) {
      // 探测穷尽 = 轮换已关闭/间隔被清：必须清掉旧定时器，否则它按旧间隔永远存活
      // （关轮换后旧 tick 反复全失败重探：视频壁纸每 N 分钟闪断一次；关间隔则轮换关不掉）
      if (intervalTimer) { clearInterval(intervalTimer); intervalTimer = null; }
      return;
    }
    var minutes = INTERVALS[i];
    var img = new Image();
    img.onload = function () {
      if (intervalTimer) clearInterval(intervalTimer); // 热切换重探后不留旧定时器
      intervalTimer = setInterval(function () {
        if (document.hidden) return; // 后台零解码：隐藏期不换片，恢复可见后的下一个 tick 自然续上
        var cur = 0;
        try { cur = parseInt(localStorage.getItem('oc-wp-idx') || '0', 10) || 0; } catch (e) {}
        tryRotate(cur + 1, bust);
      }, minutes * 60 * 1000);
    };
    img.onerror = function () { detectInterval(i + 1, bust); };
    img.src = ROTATE_DIR + 'interval-' + minutes + '.gif';
  }

  function tryRotate(n, bust) {
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(ROTATE_DIR + 'rotate-' + n + '.' + exts[i]);
    probeList(urls, function (el) {
      try { localStorage.setItem('oc-wp-idx', String(n)); } catch (e) {}
      applyMedia(el);
    }, function () {
      if (n > 1) tryRotate(1, bust);   // 越界 → 回到第一张
      else probeStatic(0, bust);       // 轮换集被清空 → 静态回落
    });
  }

  /* ── 2) 静态壁纸：wallpaper.<ext> ── */
  function probeStatic(dirIdx, bust) {
    if (dirIdx >= 1 || !hasUserDir) return; // 极光兜底
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(WALLPAPER_DIR + 'wallpaper.' + exts[i]);
    probeList(urls, applyMedia, function () { probeStatic(dirIdx + 1, bust); });
  }

  /* ── 启动：先检测轮换是否开启 ── */
  function fullProbe(bust) {
    if (ROTATE_DIR) {
      var rotUrls = [];
      for (var r = 0; r < exts.length; r++) rotUrls.push(ROTATE_DIR + 'rotate-1.' + exts[r]);
      probeList(rotUrls, function () { rotateStart(bust); }, function () { probeStatic(0, bust); });
    } else {
      probeStatic(0, bust);
    }
  }
  fullProbe(null);

  /* ── 热切换：选择器改动设置后会写入 refresh-N.gif 标记（编号按 1..3 循环，
     兼容只探测 1..3 的旧版已部署脚本），每 5 秒探测一次全部 5 个标记位，
     位图变化即带缓存穿透重探壁纸，免重启生效。
     页面隐藏时跳过探测（此时探测纯耗磁盘读，发现也得等可见才能换），恢复可见立即补测 ── */
  var lastMarker = -1;
  function probeMarkers() {
    if (!ROTATE_DIR || document.hidden) return;
    var found = 0, pending = 5;
    function settle() {
      if (--pending > 0) return;
      if (lastMarker !== -1 && found !== lastMarker) {
        try { localStorage.removeItem('oc-wp-idx'); } catch (e) {}
        reloadCustomCss();
        fullProbe(String(Date.now()));
      } else {
        resumeMedia(); // 标记没变化：只把被暂停的视频继续播，不销毁重建
      }
      if (found !== 0) lastMarker = found;
    }
    for (var n = 1; n <= 5; n++) {
      (function (idx) {
        var img = new Image();
        img.onload = function () { found |= (1 << idx); settle(); };
        img.onerror = function () { settle(); };
        img.src = ROTATE_DIR + 'refresh-' + idx + '.gif';
      })(n);
    }
  }
  if (ROTATE_DIR) { setInterval(probeMarkers, 5000); }

  function resumeMedia() {
    var v = layer.querySelector('video');
    if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }

  /* 自动播放解锁：DSH 外壳的 autoplay 策略要求用户手势，脚本直接 play() 会被拒。
     页面里任何一次真实交互（点击/按键/滚轮）都会建立激活态，监听一次性触发后
     由 resumeMedia 恢复播放；轮询里的 resumeMedia 在激活态建立后也会持续兜底 */
  (function () {
    var unlock = function () {
      resumeMedia();
      document.removeEventListener('pointerdown', unlock, true);
      document.removeEventListener('keydown', unlock, true);
      document.removeEventListener('wheel', unlock, true);
    };
    document.addEventListener('pointerdown', unlock, true);
    document.addEventListener('keydown', unlock, true);
    document.addEventListener('wheel', unlock, true);
  })();

  /* 后台零解码：隐藏即暂停视频（切走后不再烧 GPU/CPU），前台恢复播放。
     恢复可见时补测一次标记——后台期间选择器做过的改动几秒内可见；
     只有标记真的变化才 fullProbe 重载视频，切回窗口不再有"销毁重建大视频"
     造成的瞬间卡顿。（绕过选择器手动替换壁纸文件需重启应用才会被发现——
     换取的是每次切回窗口零卡顿，README 有说明） */
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      try { reloadCustomCss(); } catch (e) {}
      resumeMedia();
      probeMarkers();
    } else {
      var v = layer.querySelector('video');
      if (v && !v.paused) { try { v.pause(); } catch (e) {} }
    }
  });
})();
