/* zwp-ver:2 (2026-09-23；2026-09-24 根层内联透明 + 可见恢复播放，修复主题表
   html[data-theme] important 规则压过样式表透明导致壁纸被白底盖死、以及窗口
   遮挡暂停视频不恢复的问题；2026-10-14 大块元素清 background-image——皮肤渐变
   (linear-gradient 铺满 loop-chrome-window) 画在背景色之上整窗盖死壁纸，仅压
   backgroundColor 无效)— 体检/apply-patch 据此识别已部署脚本是否为旧版
   （旧版不支持 --ocwp-ui-alpha 不透明度滑杆、custom.css 热重载等，见 README「注入脚本版本」）*/
/* ai-wallpaper — Qoder 壁纸层 + 界面透明化注入脚本
 *
 * 由 apply-patch.ps1 注入到 Qoder 主窗口归档内的 out/renderer/index.html。
 * 供流：Qoder 主窗口经自定义特权协议加载（qoder-cn-app://renderer/index.html），
 *   Chromium 禁止该页加载 file:// 子资源 → 壁纸 / 轮换标记 / custom.css 走 wp:// 协议桥
 *   （apply-patch 往 out/main/index.js 追加，直读磁盘 + Range），并放宽 index.html 的
 *   内联 CSP（原页 default-src 'self'，且未声明 media-src）。
 * 透明化：Qoder 界面色值令牌是构建期混淆名（--q90ff1d 之类，随版本变），CSS 定向覆盖
 *   不可靠 → 用运行时大块扫描（同 Marvis / Reasonix）：盖住视口或全高侧栏的纯色背景压到
 *   --ocwp-ui-alpha（「AI壁纸设置」滑杆写进 custom.css），小块卡片/弹窗保持不透明保证可读。
 * 壁纸查找顺序：
 *   1. 自动轮换（wallpaper/rotate/rotate-N.*）
 *   2. __WALLPAPER_DIR__/wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 本文件同目录下的 wallpaper.*
 *   4. 都没有 → 内置"动态极光渐变"兜底
 * （__WALLPAPER_DIR__ 占位符由 apply-patch.ps1 替换为 wp://local/<用户目录相对路径>）
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

    /* 根层一律透空，露出 z-index:-1 的壁纸层；启动页同理（Qoder 主题常给它们铺纯色）。
       界面主体的大面积色块由下面的运行时扫描处理（令牌名混淆，CSS 猜不得） */
    'html,body,#root{background:transparent !important;background-color:transparent !important;}',
    '#qoder-boot-splash{background:transparent !important;}'
  ].join('\n');
  document.head.appendChild(style);

  /* ── 壁纸层 ──────────────────────────────── */
  var layer = document.createElement('div');
  layer.id = 'oc-wallpaper';
  layer.className = 'aurora'; // 先显示兜底渐变，找到壁纸文件后替换
  (document.body || document.documentElement).appendChild(layer);

  // 皮肤生效标记：窗口标题出现 ✦ 即说明本脚本已运行
  try { document.title += ' ✦'; } catch (e) {}

  /* ── 大面积不透明色块自动降透明（Qoder 界面令牌为构建期混淆名 → 按几何与算得色扫描：
     盖住几乎整个视口、或全高侧栏的大块纯色背景，统一压到 --ocwp-ui-alpha（滑杆驱动，
     缺省 .55）。React 异步挂载 + 视图懒加载，首帧三次 + 可见时低频轮询兜底。
     卡片/弹窗等小块不动保证可读性；个别想不透明的场景在 custom.css 里加回背景即可 ── */
  function uiAlpha() {
    var a = NaN;
    try {
      a = parseFloat(getComputedStyle(document.documentElement)
        .getPropertyValue('--ocwp-ui-alpha'));
    } catch (e) {}
    if (!(a > 0)) a = 0.55;
    return a > 0.85 ? 0.85 : a;
  }

  function deopaque() {
    try {
      if (!document.body || document.hidden) return;
      var target = uiAlpha();
      var vw = innerWidth, vh = innerHeight;
      var all = document.body.getElementsByTagName('*');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        if (el.id === 'oc-wallpaper') continue;
        var r = el.getBoundingClientRect();
        if (r.width < 10 || r.height < 10) continue;
        var full = (r.width >= vw * 0.95 && r.height >= vh * 0.95);
        var tall = (r.height >= vh * 0.85 && r.width >= 120 && r.width <= vw * 0.6);
        /* 主内容大面板（对话区/workbench）：≥80% 高 + ≥50% 宽。2026-09-24 追加——
           Qoder 的 workbench 主面板约 81%×94%，此前「全屏」「全高侧栏」两类都不命中，
           保持不透明白底把对话区盖死（用户实测反馈）；中大型弹窗（高 <80%）不受影响 */
        var wide = (r.height >= vh * 0.8 && r.width >= vw * 0.5);
        if (!full && !tall && !wide) continue;
        var cs = getComputedStyle(el);
        /* 2026-10-14：皮肤/主题会往整面容器刷 background-image 渐变（用户皮肤的
           loop-chrome-window 即 linear-gradient(浅黄→灰蓝) 铺满全窗），backgroundColor
           压透明对它无效——渐变画在背景色之上、壁纸之前，整窗盖死。大块元素一律
           清掉 background-image 让位壁纸；每 tick 重扫，皮肤换新渐变下一 tick 照删 */
        var bi = cs.backgroundImage;
        if (bi && bi !== 'none') {
          el.style.setProperty('background-image', 'none', 'important');
        }
        var bg = cs.backgroundColor;
        var m = bg && bg.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/);
        if (!m) continue;
        var a = (m[4] === undefined) ? 1 : parseFloat(m[4]);
        if (a > target) {
          el.style.setProperty('background-color',
            'rgba(' + m[1] + ',' + m[2] + ',' + m[3] + ',' + target + ')', 'important');
        }
      }
    } catch (e) {}
  }
  /* 根层透明以内联 !important 再上一道保险：Qoder 主题表存在 html[data-theme=…]
     属性选择器的 important 规则（特异性高于本脚本的 html, body, #root 选择器且后加载，
     2026-09-24 forest-light 主题实测把 body 刷回不透明白、盖死 z-index:-1 的壁纸层），
     而内联样式不受层叠特异性与加载顺序影响。周期性重申，覆盖 React 重挂载与主题切换 */
  function forceTransparent() {
    var els = [document.documentElement, document.body, document.getElementById('root'),
               document.getElementById('qoder-boot-splash')];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (!el) continue;
      try {
        el.style.setProperty('background', 'transparent', 'important');
        el.style.setProperty('background-color', 'transparent', 'important');
      } catch (e) {}
    }
  }
  forceTransparent();

  function tick() { forceTransparent(); if (!document.hidden) deopaque(); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { tick(); });
  } else { tick(); }
  setTimeout(tick, 2500);
  setTimeout(tick, 6000);
  setInterval(tick, 12000);

  /* 可见性变化时重申内联透明（主题切换/React 重挂载可能重排根层）；
     视频续播与 custom.css 重载由文末既有的 visibilitychange 处理负责 */
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) forceTransparent();
  });

  /* ── 用户自定义微调：壁纸目录下的 custom.css ─ */
  var WALLPAPER_DIR = '__WALLPAPER_DIR__/'; // 占位符，由 apply-patch.ps1 替换
  var HERE = './';
  var hasUserDir = WALLPAPER_DIR.indexOf('__') === -1;
  var ROTATE_DIR = hasUserDir ? WALLPAPER_DIR + 'rotate/' : null;
  var exts = ['mp4', 'webm', 'gif', 'webp', 'png', 'jpg'];

  if (hasUserDir) {
    try {
      var customLink = document.createElement('link');
      customLink.rel = 'stylesheet';
      customLink.id = 'ocwp-custom';
      // 加时间戳穿透缓存：编辑 custom.css 后普通刷新即可生效
      customLink.href = WALLPAPER_DIR + 'custom.css?z=' + Date.now();
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
      l.href = WALLPAPER_DIR + 'custom.css?t=' + Date.now();
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
    if (el.tagName === 'VIDEO') { el.play().catch(function () {}); }
    deopaque(); // 壁纸换了/铺开了，按当前滑杆值重算一次界面透明度
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
    img.src = ROTATE_DIR + 'interval-' + minutes + '.gif' + (bust ? '?v=' + bust : '');
  }

  function tryRotate(n, bust) {
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(ROTATE_DIR + 'rotate-' + n + '.' + exts[i] + (bust ? '?v=' + bust : ''));
    probeList(urls, function (el) {
      try { localStorage.setItem('oc-wp-idx', String(n)); } catch (e) {}
      applyMedia(el);
    }, function () {
      if (n > 1) tryRotate(1, bust);   // 越界 → 回到第一张
      else probeStatic(0, bust);       // 轮换集被清空 → 静态回落
    });
  }

  /* ── 2) 静态壁纸：wallpaper.<ext> ── */
  var staticDirs = hasUserDir ? [WALLPAPER_DIR, HERE] : [HERE];
  function probeStatic(dirIdx, bust) {
    if (dirIdx >= staticDirs.length) return; // 极光兜底
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(staticDirs[dirIdx] + 'wallpaper.' + exts[i] + (bust ? '?v=' + bust : ''));
    probeList(urls, applyMedia, function () { probeStatic(dirIdx + 1, bust); });
  }

  /* ── 启动：先检测轮换是否开启 ── */
  function fullProbe(bust) {
    if (ROTATE_DIR) {
      var rotUrls = [];
      for (var r = 0; r < exts.length; r++) rotUrls.push(ROTATE_DIR + 'rotate-1.' + exts[r] + (bust ? '?v=' + bust : ''));
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
      deopaque(); // 滑杆/主题改动落在 custom.css 里，随每次 tick 生效
      if (found !== 0) lastMarker = found;
    }
    for (var n = 1; n <= 5; n++) {
      (function (idx) {
        var img = new Image();
        img.onload = function () { found |= (1 << idx); settle(); };
        img.onerror = function () { settle(); };
        img.src = ROTATE_DIR + 'refresh-' + idx + '.gif?t=' + Date.now();
      })(n);
    }
  }
  if (ROTATE_DIR) { setInterval(probeMarkers, 5000); }

  function resumeMedia() {
    var v = layer.querySelector('video');
    if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }

  /* 后台零解码：隐藏即暂停视频（切走后不再烧 GPU/CPU），前台恢复播放。
     恢复可见时补测一次标记——后台期选择器做过的改动几秒内可见；
     只有标记真的变化才 fullProbe 重载视频，切回窗口不再有"销毁重建几十 MB
     视频"造成的瞬间卡顿。（绕过选择器手动替换壁纸文件需重启应用才会被
     发现——换取的是每次切回窗口零卡顿） */
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      try { reloadCustomCss(); } catch (e) {}
      resumeMedia();
      probeMarkers();
      deopaque();
    } else {
      var v = layer.querySelector('video');
      if (v && !v.paused) { try { v.pause(); } catch (e) {} }
    }
  });
})();
