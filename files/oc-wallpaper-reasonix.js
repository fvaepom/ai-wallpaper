/* ai-wallpaper — 壁纸层 + 界面透明化注入脚本（Reasonix 专用变体）
 *
 * 由 apply-patch.ps1 注入到 Reasonix 桌面壳主窗口页面（versions\<版本>\app\resources\app\index.html，
 * 经特权协议 reasonix://app 加载）。__WALLPAPER_DIR__ 占位符被替换为 ./zwp —— distRoot 内的
 * zwp junction（→ %USERPROFILE%\.reasonix\wallpaper），同源相对路径加载壁纸 / custom.css /
 * 轮换标记，无 CORS / 混合内容 / 私有网络访问限制，视频原生流式播放。
 * 壁纸查找顺序：
 *   1. 自动轮换（检测到 <壁纸目录>\rotate\rotate-1.* 时启用）：
 *      每次页面加载按 localStorage 计数器换下一张 rotate-N.*
 *   2. <壁纸目录>\wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 都没有 → 内置"动态极光渐变"兜底
 * 透明化两层：
 *   a. 令牌覆盖：Reasonix 全部表面色都从根源令牌 --bg / --bg-soft / --bg-elev / --bg-elev-2 /
 *      --chat-bg 派生（--stage/--surface/--panel/--overlay-surface-bg 与 color-mix 均引用它们），
 *      用 !important 覆盖一次即全主题（dark/light/graphite/aurora/slate）生效；
 *      深浅色由 html[data-theme] 判定，MutationObserver 跟随切换
 *   b. 自适应扫描：React 内联样式的实底色块（不走令牌）按"盖满视口 / 全高侧栏"启发式压到
 *      alpha 0.45，卡片/弹窗不动保证可读性
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

  /* ── 令牌透明化：深浅两套色值取自 Reasonix 官方 :root 定义 ── */
  var TOKENS = {
    dark:  { bg: '9,10,12',    soft: '17,19,25',   elev: '25,27,34',   elev2: '34,38,49' },
    light: { bg: '247,248,251', soft: '238,242,247', elev: '255,255,255', elev2: '242,245,249' }
  };
  var ALPHA = { bg: 0.40, soft: 0.48, elev: 0.68, elev2: 0.75 };
  function tokenCss(p) {
    return ':root{'
      + '--bg:rgba(' + p.bg + ',' + ALPHA.bg + ') !important;'
      + '--bg-soft:rgba(' + p.soft + ',' + ALPHA.soft + ') !important;'
      + '--bg-elev:rgba(' + p.elev + ',' + ALPHA.elev + ') !important;'
      + '--bg-elev-2:rgba(' + p.elev2 + ',' + ALPHA.elev2 + ') !important;'
      + '--chat-bg:rgba(' + p.bg + ',' + ALPHA.bg + ') !important;'
      /* 弹层/模态单独压住透明度，保证可读（其余 --surface/--panel/--stage 均由上面四个派生） */
      + '--overlay-surface-bg:rgba(' + p.elev + ',0.92) !important;'
      + '}';
  }
  function currentPalette() {
    var light = false;
    try { light = document.documentElement.getAttribute('data-theme') === 'light'; } catch (e) {}
    return light ? TOKENS.light : TOKENS.dark;
  }

  /* ── 界面透明化 + 壁纸层样式 ────────────────── */
  var style = document.createElement('style');
  style.id = 'oc-wallpaper-style';
  style.textContent = [
    tokenCss(currentPalette()),

    'html,body,#root{background:transparent !important;}',

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
    '@media (prefers-reduced-motion: reduce){#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{animation:none;}}'
  ].join('\n');
  document.head.appendChild(style);

  /* 深浅色跟随：html[data-theme] 被应用切换时重写令牌段 */
  try {
    var themeObs = new MutationObserver(function () {
      var seg = tokenCss(currentPalette());
      var cur = style.textContent;
      var i = cur.indexOf(':root{');
      var j = cur.indexOf('}', i);
      if (i >= 0 && j > i) { style.textContent = seg + cur.substring(j + 1); }
    });
    themeObs.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-theme-style'] });
  } catch (e) {}

  /* ── 壁纸层 ──────────────────────────────── */
  var layer = document.createElement('div');
  layer.id = 'oc-wallpaper';
  layer.className = 'aurora'; // 先显示兜底渐变，找到壁纸文件后替换
  (document.body || document.documentElement).appendChild(layer);

  // 皮肤生效标记：窗口标题出现 ✦ 即说明本脚本已运行
  try { document.title += ' ✦'; } catch (e) {}

  /* ── 大面积不透明色块自动降透明（React 内联样式不走令牌，CSS 猜测不可靠 →
     运行时扫描：盖住几乎整个视口、或全高侧栏的大块纯色背景，统一压到 alpha 0.45。
     React 异步挂载 + 视图懒加载，首帧三次 + 可见时低频轮询兜底。
     卡片/弹窗等小块不动，保证可读性；个别想不透明的场景在 custom.css 里对具体元素加回背景 ── */
  function deopaque() {
    try {
      if (!document.body || document.hidden) return;
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
  setInterval(function () { if (!document.hidden) deopaque(); }, 12000);

  /* ── 用户自定义微调：壁纸目录下的 custom.css（同源 ./zwp/custom.css）。
     轮换标记变化会重挂载本表（reasonix:// 特权协议直读磁盘、无 HTTP 缓存层；
     若编辑后仍见旧样式，重启一次应用即可） ── */
  var WALLPAPER_DIR = '__WALLPAPER_DIR__/'; // 占位符，由 apply-patch.ps1 替换
  var ROTATE_DIR = WALLPAPER_DIR + 'rotate/';
  var exts = ['mp4', 'webm', 'gif', 'webp', 'png', 'jpg'];

  function mountCustomCss() {
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
  mountCustomCss();
  function reloadCustomCss() { mountCustomCss(); }

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
    if (el.tagName === 'VIDEO') { el.play().catch(function () {}); }
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

  /* bust = 热切换重探的触发代号。本变体【不】把它拼进 URL：reasonix:// 是特权协议
     直读磁盘（无 HTTP 缓存层），加查询串反而可能与路径解析/缓存键产生兼容问题 ——
     与 Marvis/DSH 同款约束：覆盖同名 wallpaper.* 后需重启应用才保证可见 */
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
      else probeStatic(bust);          // 轮换集被清空 → 静态回落
    });
  }

  /* ── 2) 静态壁纸：wallpaper.<ext> ── */
  function probeStatic(bust) {
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(WALLPAPER_DIR + 'wallpaper.' + exts[i]);
    probeList(urls, applyMedia, function () { /* 极光兜底：保持 aurora 类 */ });
  }

  /* ── 启动：先检测轮换是否开启 ── */
  function fullProbe(bust) {
    var rotUrls = [];
    for (var r = 0; r < exts.length; r++) rotUrls.push(ROTATE_DIR + 'rotate-1.' + exts[r]);
    probeList(rotUrls, function () { rotateStart(bust); }, function () { probeStatic(bust); });
  }
  fullProbe(null);

  /* ── 热切换：选择器改动设置后会写入 refresh-N.gif 标记（编号 1..3 循环，
     兼容已部署各应用的旧版脚本约定），每 5 秒探测一次全部标记位，
     位图变化即全量重探壁纸（换片/换壁纸免重启；同名文件覆盖除外，见 bust 说明）。
     页面隐藏时跳过探测（此时探测纯耗磁盘读，发现也得等可见才能换），恢复可见立即补测 ── */
  var lastMarker = -1;
  function probeMarkers() {
    if (document.hidden) return;
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
  setInterval(probeMarkers, 5000);

  function resumeMedia() {
    var v = layer.querySelector('video');
    if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }

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
