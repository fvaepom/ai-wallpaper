/* zcode-wallpaper — 壁纸层 + 界面透明化注入脚本
 *
 * 由 apply-patch.ps1 注入到应用主窗口 index.html。
 * 同时适配 ZCode（--color-* 变量 / .dark 类）与 OpenCode 桌面端
 * （--background-* 变量 / data-color-scheme 属性），未使用的变量集自动失效。
 * 壁纸查找顺序：
 *   1. 自动轮换（检测到 %USERPROFILE%\.zcode\wallpaper\rotate\rotate-1.* 时启用）：
 *      每次页面加载按 localStorage 计数器换下一张 rotate-N.*
 *   2. %USERPROFILE%\.zcode\wallpaper\wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 本文件同目录下的 wallpaper.*
 *   4. 都没有 → 内置"动态极光渐变"兜底
 * （__WALLPAPER_DIR__ 占位符由 apply-patch.ps1 替换为实际用户目录）
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

    /* 兜底：动态极光渐变（未检测到壁纸文件时显示） */
    '#oc-wallpaper.aurora{animation:oc-hue 40s linear infinite;}',
    '#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{',
    '  content:"";position:absolute;width:70vmax;height:70vmax;border-radius:50%;',
    '  filter:blur(90px);opacity:.5;mix-blend-mode:screen;will-change:transform;}',
    '#oc-wallpaper.aurora::before{',
    '  background:radial-gradient(circle at 30% 30%,#3b82f6 0%,#1d4ed8 35%,transparent 70%);',
    '  top:-25%;left:-15%;animation:oc-drift-a 26s ease-in-out infinite alternate;}',
    '#oc-wallpaper.aurora::after{',
    '  background:radial-gradient(circle at 60% 60%,#a855f7 0%,#6d28d9 40%,transparent 70%);',
    '  bottom:-30%;right:-20%;animation:oc-drift-b 32s ease-in-out infinite alternate;}',
    '@keyframes oc-drift-a{0%{transform:translate(0,0) scale(1) rotate(0deg);}',
    '  50%{transform:translate(12vw,8vh) scale(1.15) rotate(20deg);}',
    '  100%{transform:translate(4vw,16vh) scale(.95) rotate(-10deg);}}',
    '@keyframes oc-drift-b{0%{transform:translate(0,0) scale(1);}',
    '  50%{transform:translate(-10vw,-10vh) scale(1.2);}',
    '  100%{transform:translate(-4vw,-4vh) scale(.9);}}',
    '@keyframes oc-hue{0%{filter:hue-rotate(0deg);}50%{filter:hue-rotate(40deg);}100%{filter:hue-rotate(0deg);}}',
    '@media (prefers-reduced-motion: reduce){#oc-wallpaper.aurora::before,#oc-wallpaper.aurora::after{animation:none;}}',

    /* 让界面透出壁纸：alpha 越小越透。弹层保持较高不透明度保证可读 */
    ':root,:host{',
    '  --color-background:rgba(250,250,250,.66) !important;',
    '  --color-background-alt:rgba(245,245,245,.5) !important;',
    '  --color-background-win-alt:rgba(229,229,229,.72) !important;',
    '  --color-header:rgba(245,245,245,.55) !important;',
    '  --color-panel:rgba(245,245,245,.58) !important;',
    '  --color-sidebar:rgba(245,245,245,.6) !important;',
    '  --color-card:rgba(255,255,255,.78) !important;',
    '  --color-card-selected:rgba(229,229,229,.85) !important;',
    '  --color-popover:rgba(255,255,255,.94) !important;',
    '  --color-input:rgba(255,255,255,.7) !important;}',
    '.dark{',
    '  --color-background:rgba(23,23,23,.62) !important;',
    '  --color-background-alt:rgba(38,38,38,.5) !important;',
    '  --color-background-win-alt:rgba(38,38,38,.7) !important;',
    '  --color-header:rgba(23,23,23,.55) !important;',
    '  --color-panel:rgba(23,23,23,.58) !important;',
    '  --color-sidebar:rgba(10,10,10,.6) !important;',
    '  --color-card:rgba(38,38,38,.78) !important;',
    '  --color-card-selected:rgba(64,64,64,.85) !important;',
    '  --color-popover:rgba(38,38,38,.92) !important;',
    '  --color-input:rgba(38,38,38,.7) !important;}',

    /* OpenCode 桌面端变量（弹层 --background-stronger 保持高不透明度保证可读） */
    ':root,:host{',
    '  --background-base:rgba(248,248,248,.66) !important;',
    '  --background-weak:rgba(243,243,243,.52) !important;',
    '  --background-strong:rgba(252,252,252,.6) !important;',
    '  --background-stronger:rgba(252,252,252,.92) !important;}',
    ':root[data-color-scheme="dark"]{',
    '  --background-base:rgba(16,16,16,.6) !important;',
    '  --background-weak:rgba(30,30,30,.5) !important;',
    '  --background-strong:rgba(18,18,18,.55) !important;',
    '  --background-stronger:rgba(21,21,21,.92) !important;}',
    'html,body{background:transparent !important;}'
  ].join('\n');
  document.head.appendChild(style);

  /* ── 壁纸层 ──────────────────────────────── */
  var layer = document.createElement('div');
  layer.id = 'oc-wallpaper';
  layer.className = 'aurora'; // 先显示兜底渐变，找到壁纸文件后替换
  (document.body || document.documentElement).appendChild(layer);

  // 皮肤生效标记：窗口标题出现 ✦ 即说明本脚本已运行
  try { document.title += ' ✦'; } catch (e) {}

  /* ── 用户自定义微调：wallpaper 目录下的 custom.css ─ */
  var WALLPAPER_DIR = '__WALLPAPER_DIR__/'; // 占位符，由 apply-patch.ps1 替换
  var HERE = './';
  var hasUserDir = WALLPAPER_DIR.indexOf('__') === -1;
  var ROTATE_DIR = hasUserDir ? WALLPAPER_DIR + 'rotate/' : null;
  var exts = ['mp4', 'webm', 'gif', 'webp', 'png', 'jpg'];

  if (hasUserDir) {
    try {
      var customLink = document.createElement('link');
      customLink.rel = 'stylesheet';
      customLink.href = WALLPAPER_DIR + 'custom.css';
      document.head.appendChild(customLink);
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
    if (el.tagName === 'VIDEO') { el.play().catch(function () {}); }
  }

  /* 探测一个媒体 URL：成功回调 el，失败回调 fail */
  function loadMedia(url, onOk, onFail, timeoutMs) {
    var isVideo = /\.(mp4|webm)$/i.test(url);
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

  function rotateStart() {
    var idx = 0;
    try { idx = parseInt(localStorage.getItem('oc-wp-idx') || '0', 10) || 0; } catch (e) {}
    tryRotate(idx + 1);
    detectInterval(0); // 探测 interval-N.gif → 有则启动定时换片
  }

  function detectInterval(i) {
    if (i >= INTERVALS.length) return;
    var minutes = INTERVALS[i];
    var img = new Image();
    img.onload = function () {
      setInterval(function () {
        var cur = 0;
        try { cur = parseInt(localStorage.getItem('oc-wp-idx') || '0', 10) || 0; } catch (e) {}
        tryRotate(cur + 1);
      }, minutes * 60 * 1000);
    };
    img.onerror = function () { detectInterval(i + 1); };
    img.src = ROTATE_DIR + 'interval-' + minutes + '.gif';
  }

  function tryRotate(n) {
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(ROTATE_DIR + 'rotate-' + n + '.' + exts[i]);
    probeList(urls, function (el) {
      try { localStorage.setItem('oc-wp-idx', String(n)); } catch (e) {}
      applyMedia(el);
    }, function () {
      if (n > 1) tryRotate(1);   // 越界 → 回到第一张
      else probeStatic(0);       // 轮换集被清空 → 静态回落
    });
  }

  /* ── 2) 静态壁纸：wallpaper.<ext> ── */
  var staticDirs = hasUserDir ? [WALLPAPER_DIR, HERE] : [HERE];
  function probeStatic(dirIdx) {
    if (dirIdx >= staticDirs.length) return; // 极光兜底
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(staticDirs[dirIdx] + 'wallpaper.' + exts[i]);
    probeList(urls, applyMedia, function () { probeStatic(dirIdx + 1); });
  }

  /* ── 启动：先检测轮换是否开启 ── */
  if (ROTATE_DIR) {
    var rotUrls = [];
    for (var r = 0; r < exts.length; r++) rotUrls.push(ROTATE_DIR + 'rotate-1.' + exts[r]);
    probeList(rotUrls, rotateStart, function () { probeStatic(0); });
  } else {
    probeStatic(0);
  }
})();
