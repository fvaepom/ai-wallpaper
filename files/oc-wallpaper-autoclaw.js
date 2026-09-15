/* zcode-wallpaper — 壁纸层 + 界面透明化注入脚本（AutoClaw 版）
 *
 * 由 apply-patch.ps1 注入到 asar 内 out\renderer\index.html。
 * 壁纸查找顺序：
 *   1. 自动轮换（检测到壁纸目录 rotate\rotate-1.* 时启用）：
 *      每次页面加载按 localStorage 计数器换下一张 rotate-N.*
 *   2. %APPDATA%\autoclaw\wallpaper\wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 本文件同目录下的 wallpaper.*
 *   4. 都没有 → 内置"动态极光渐变"兜底
 * （__WALLPAPER_DIR__ 占位符由 apply-patch.ps1 替换为实际用户目录）
 *
 * AutoClaw 说明：主窗口经 loadFile（file://）加载，file:// 子资源可直接访问，无需协议桥。
 * 皮肤系统走 --theme-* 令牌（body[data-skin][data-theme]，含 --bg/--panel/--surface-* 等别名），
 * 深浅色按 body[data-theme] 判定；弹层/模态（--theme-surface-overlay 等）保持不透明。
 * 全程不用 innerHTML（防 Trusted Types 策略），深浅色变量断言收敛无循环。
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

    /* 让界面透出壁纸：覆盖 AutoClaw --theme-* 背景令牌（别名 --bg/--panel/--surface-* 随之生效）。
       弹层/模态令牌（--theme-surface-overlay 等）不在覆盖清单内，保持不透明保证可读 */
    ':root,body{',
    '  --theme-bg:rgba(255,255,255,.5) !important;',
    '  --theme-bg-sub:rgba(255,255,255,.5) !important;',
    '  --theme-panel:rgba(255,255,255,.55) !important;',
    '  --theme-panel-hover:rgba(255,255,255,.5) !important;',
    '  --theme-surface-base:rgba(255,255,255,.55) !important;',
    '  --theme-surface-subtle:rgba(255,255,255,.5) !important;',
    '  --theme-surface-elevated:rgba(255,255,255,.6) !important;',
    '  --theme-surface-sunken:rgba(255,255,255,.45) !important;',
    '  --theme-chrome-bg:rgba(255,255,255,.55) !important;',
    '  --theme-nav-bg:rgba(255,255,255,.55) !important;',
    '  --theme-input-bg:rgba(255,255,255,.6) !important;',
    '  --ocwp-popup-bg:#ffffff !important;}',
    'html,body{background:transparent !important;}',

    'body[data-theme*="dark" i],html[data-theme*="dark" i],body.dark,html.dark{',
    '  --theme-bg:rgba(24,24,26,.6) !important;',
    '  --theme-bg-sub:rgba(24,24,26,.6) !important;',
    '  --theme-panel:rgba(28,28,31,.6) !important;',
    '  --theme-panel-hover:rgba(38,38,42,.6) !important;',
    '  --theme-surface-base:rgba(28,28,31,.6) !important;',
    '  --theme-surface-subtle:rgba(36,36,40,.6) !important;',
    '  --theme-surface-elevated:rgba(42,42,46,.65) !important;',
    '  --theme-surface-sunken:rgba(18,18,20,.6) !important;',
    '  --theme-chrome-bg:rgba(24,24,26,.6) !important;',
    '  --theme-nav-bg:rgba(24,24,26,.6) !important;',
    '  --theme-input-bg:rgba(45,45,48,.65) !important;',
    '  --ocwp-popup-bg:#1b1c22 !important;}'
  ].join('\n');
  document.head.appendChild(style);

  /* ── 主题变量运行时覆盖：内联 !important 打赢皮肤系统的特异性规则（值相同不写，收敛） ── */
  var UI_A = 'var(--ocwp-ui-alpha,.55)';     // 浅色主题界面不透明度（可被 custom.css 覆盖）
  var UI_A_DARK = 'var(--ocwp-ui-alpha,.6)'; // 深色主题界面不透明度

  function lightVars() {
    return {
      '--theme-bg': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-bg-sub': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-panel': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-panel-hover': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-surface-base': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-surface-subtle': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-surface-elevated': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-surface-sunken': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-chrome-bg': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-nav-bg': 'rgba(255,255,255,' + UI_A + ')',
      '--theme-input-bg': 'rgba(255,255,255,' + UI_A + ')',
      '--ocwp-popup-bg': '#ffffff'
    };
  }
  function darkVars() {
    return {
      '--theme-bg': 'rgba(24,24,26,' + UI_A_DARK + ')',
      '--theme-bg-sub': 'rgba(24,24,26,' + UI_A_DARK + ')',
      '--theme-panel': 'rgba(28,28,31,' + UI_A_DARK + ')',
      '--theme-panel-hover': 'rgba(38,38,42,' + UI_A_DARK + ')',
      '--theme-surface-base': 'rgba(28,28,31,' + UI_A_DARK + ')',
      '--theme-surface-subtle': 'rgba(36,36,40,' + UI_A_DARK + ')',
      '--theme-surface-elevated': 'rgba(42,42,46,' + UI_A_DARK + ')',
      '--theme-surface-sunken': 'rgba(18,18,20,' + UI_A_DARK + ')',
      '--theme-chrome-bg': 'rgba(24,24,26,' + UI_A_DARK + ')',
      '--theme-nav-bg': 'rgba(24,24,26,' + UI_A_DARK + ')',
      '--theme-input-bg': 'rgba(45,45,48,' + UI_A_DARK + ')',
      '--ocwp-popup-bg': '#1b1c22'
    };
  }

  function isDarkTheme() {
    var v = '';
    try {
      v = (document.body.getAttribute('data-theme') || '') + ' ' +
          (document.body.getAttribute('data-skin') || '') + ' ' +
          (document.body.className || '') + ' ' +
          (document.documentElement.getAttribute('data-theme') || '') + ' ' +
          (document.documentElement.className || '');
    } catch (e) {}
    return /dark|night/i.test(v);
  }

  /* CSSOM 改写：
   * 1) MANAGED 里的 --theme-* 与别名令牌声明 → 按原色改写成半透明（保留 RGB 只压 alpha）；
   * 2) 通用底色降不透明度：AutoClaw 组件类里有大量硬编码 background: #fff / #f5f5f5，
   *    不走变量 → 对所有规则的不透明底色（alpha>=0.85）同样压低；弹层/菜单/模态/提示类
   *    规则（KEEP_OPAQUE_RE 命中）跳过，保证可读。已改写的值 alpha<0.85，天然收敛。 */
  var MANAGED = {};
  (function () {
    var names = ['--theme-bg', '--theme-bg-sub', '--theme-panel', '--theme-panel-hover',
                 '--theme-surface-base', '--theme-surface-subtle', '--theme-surface-elevated',
                 '--theme-surface-sunken', '--theme-chrome-bg', '--theme-nav-bg', '--theme-input-bg',
                 '--bg', '--bg-sub', '--panel', '--panel-hover',
                 '--surface-base', '--surface-subtle', '--surface-elevated', '--surface-sunken',
                 '--nav-bg', '--chrome-bg', '--input-bg',
                 '--approval-card-bg', '--approval-fields-bg',
                 '--approval-secondary-button-bg', '--approval-command-bg'];
    for (var i = 0; i < names.length; i++) MANAGED[names[i]] = 1;
  })();
  var BG_ALPHA = '0.5';
  var KEEP_OPAQUE_RE = /modal|dialog|popover|tooltip|menu|dropdown|popper|overlay|toast|notification|combobox|select-content|calendar|scheduler/i;
  var KEEP_OPAQUE_EL = '[role="dialog"],[role="menu"],[role="listbox"],[role="tooltip"],[data-radix-popper-content-wrapper],[data-state="open"][role]'

  /* 解析颜色为 [r,g,b]；解析不了（var()/color-mix 等）返回 null → 跳过不动 */
  function parseColor(v) {
    v = String(v).trim().toLowerCase();
    var m = v.match(/^#([0-9a-f]{3,8})$/);
    if (m) {
      var h = m[1];
      if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
      return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
    }
    m = v.match(/^rgba?\(([^)]+)\)$/);
    if (m) {
      var p = m[1].split(/[,\s\/]+/).filter(function (x) { return x !== ''; });
      if (p.length >= 3) return [Math.round(parseFloat(p[0])), Math.round(parseFloat(p[1])), Math.round(parseFloat(p[2]))];
    }
    return null;
  }

  function isOwnSheet(sheet) {
    return sheet.ownerNode && sheet.ownerNode.id === 'oc-wallpaper-style';
  }

  /* 一条声明是否要被降不透明度：命中弹层保持清单、带 alpha 的浅底色都跳过 */
  function keepOpaque(selectorText) {
    return KEEP_OPAQUE_RE.test(String(selectorText || ''));
  }

  function rewriteRuleStyle(s, selectorText) {
    var keep = keepOpaque(selectorText);
    for (var j = s.length - 1; j >= 0; j--) {
      var prop = s[j];
      if (MANAGED[prop]) {
        var rgb = parseColor(s.getPropertyValue(prop));
        if (rgb) s.setProperty(prop, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + BG_ALPHA + ')', 'important');
        continue;
      }
      if (keep || (prop !== 'background' && prop !== 'background-color')) continue;
      var val = s.getPropertyValue(prop);
      var rgb2 = parseColor(val);
      if (!rgb2) continue;
      var m = val.match(/,\s*([\d.]+)\s*\)\s*$/);
      var alpha = m ? parseFloat(m[1]) : 1;
      if (isNaN(alpha) || alpha < 0.85) continue;
      /* 只补 background-color 声明：写在同块末尾带 !important，压过前面的简写颜色 */
      s.setProperty('background-color', 'rgba(' + rgb2[0] + ',' + rgb2[1] + ',' + rgb2[2] + ',' + BG_ALPHA + ')', 'important');
    }
  }

  function rewriteSheetRules(rules) {
    for (var i = 0; i < rules.length; i++) {
      var r = rules[i];
      if (r.style) rewriteRuleStyle(r.style, r.selectorText);
      if (r.cssRules && r.cssRules.length) rewriteSheetRules(r.cssRules);
    }
  }

  function rewriteAllSheets() {
    var uiAlpha = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--ocwp-ui-alpha'));
    if (!isNaN(uiAlpha)) BG_ALPHA = String(uiAlpha);
    for (var s = 0; s < document.styleSheets.length; s++) {
      var sheet = document.styleSheets[s];
      if (isOwnSheet(sheet)) continue;
      var rules;
      try { rules = sheet.cssRules; } catch (e) { continue; }
      rewriteSheetRules(rules);
    }
    var roots = [document];
    try {
      var walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_ELEMENT);
      var el;
      while ((el = walker.nextNode())) { if (el.shadowRoot) roots.push(el.shadowRoot); }
    } catch (e) {}
    for (var r = 0; r < roots.length; r++) {
      var ad = roots[r].adoptedStyleSheets || [];
      for (var a = 0; a < ad.length; a++) {
        try { rewriteSheetRules(ad[a].cssRules); } catch (e) {}
      }
      var ss = roots[r].styleSheets;
      if (ss) {
        for (var q = 0; q < ss.length; q++) {
          if (isOwnSheet(ss[q])) continue;
          try { rewriteSheetRules(ss[q].cssRules); } catch (e) {}
        }
      }
    }
  }

  function assertThemeVars() {
    var vars = isDarkTheme() ? darkVars() : lightVars();
    var targets = [document.documentElement, document.body];
    for (var t = 0; t < targets.length; t++) {
      var el = targets[t];
      if (!el) continue;
      for (var k in vars) {
        if (el.style.getPropertyValue(k) !== vars[k]) el.style.setProperty(k, vars[k], 'important');
      }
    }
  }

  /* adopted 镜像表：皮肤规则若装载在构造式样式表里，级联顺序在普通 <style> 之后，
     同权重 !important 时它赢 → 把全部透明化规则镜像进挂到末尾的 adopted 表 */
  var ocwpAdopted = null;
  function ensureAdoptedSheet() {
    try {
      if (!ocwpAdopted) {
        if (typeof CSSStyleSheet === 'undefined' || !CSSStyleSheet.prototype.replaceSync) return;
        ocwpAdopted = new CSSStyleSheet();
        ocwpAdopted.replaceSync(style.textContent);
      }
      var arr = document.adoptedStyleSheets || [];
      for (var i = 0; i < arr.length; i++) { if (arr[i] === ocwpAdopted) return; }
      document.adoptedStyleSheets = arr.concat([ocwpAdopted]);
    } catch (e) {}
  }

  /* 内联样式刮刀：React 组件可能 style={{background:'#fff'}} 写死底色，
     CSSOM 够不到 → 直接改写元素内联声明（alpha>=0.85 的不透明底色压低）。
     元素命中弹层保持清单（closest）则跳过。只扫 style 里含 background 的元素，开销小 */
  function scrubInlineStyles() {
    var all = document.getElementsByTagName('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      var st = el.style;
      if (!st || !st.length) continue;
      var hasBg = false;
      for (var k = 0; k < st.length; k++) {
        if (st[k] === 'background' || st[k] === 'background-color') { hasBg = true; break; }
      }
      if (!hasBg) continue;
      try { if (el.closest(KEEP_OPAQUE_EL)) continue; } catch (e) {}
      for (var q = 0; q < st.length; q++) {
        var prop = st[q];
        if (prop !== 'background' && prop !== 'background-color') continue;
        var val = st.getPropertyValue(prop);
        var rgb = parseColor(val);
        if (!rgb) continue;
        var m = val.match(/,\s*([\d.]+)\s*\)\s*$/);
        var alpha = m ? parseFloat(m[1]) : 1;
        if (isNaN(alpha) || alpha < 0.85) continue;
        var cur = st.getPropertyValue('background-color');
        var want = 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + BG_ALPHA + ')';
        if (cur !== want) st.setProperty('background-color', want, 'important');
      }
    }
  }

  function __ocwpFullPass() {
    try { rewriteAllSheets(); assertThemeVars(); ensureAdoptedSheet(); scrubInlineStyles(); } catch (e) {}
  }
  __ocwpFullPass();

  document.addEventListener('load', __ocwpFullPass, true);
  document.addEventListener('DOMContentLoaded', __ocwpFullPass);
  window.addEventListener('load', __ocwpFullPass);
  [500, 1500, 4000, 8000].forEach(function (t) { setTimeout(__ocwpFullPass, t); });
  /* 皮肤可能整体替换 adoptedStyleSheets，低频兜底；页面隐藏时跳过（恢复可见时
     visibilitychange 会补一轮），间隔从 5s 放宽到 15s */
  setInterval(function () { if (!document.hidden) __ocwpFullPass(); }, 15000);

  /* 切回前台：补一轮覆盖 + 立即补测热切换标记（只在标记变化才重探壁纸，不销毁重建
     正在播的视频）；切到后台：暂停视频，零解码 */
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      try { reloadCustomCss(); } catch (e) {}
      try { __ocwpFullPass(); } catch (e) {}
      resumeMedia();
      probeMarkers();
    } else {
      var v = layer.querySelector('video');
      if (v && !v.paused) { try { v.pause(); } catch (e) {} }
    }
  });

  var __ocwpMo = null, __moTimer = null;
  function __moFire() {
    /* 200ms 防抖合并高频 DOM 变更；隐藏期间跳过（恢复可见时 visibilitychange 会补一轮） */
    if (__moTimer) return;
    __moTimer = setTimeout(function () {
      __moTimer = null;
      if (document.hidden) return;
      try { __ocwpFullPass(); } catch (e) {}
    }, 200);
  }
  function __ocwpStartObserver() {
    if (__ocwpMo || !document.body) return false;
    try {
      __ocwpMo = new MutationObserver(__moFire);
      __ocwpMo.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class', 'data-theme', 'data-skin'] });
      __ocwpMo.observe(document.body, { attributes: true, attributeFilter: ['style', 'class', 'data-theme', 'data-skin'] });
      __ocwpMo.observe(document.head, { childList: true, subtree: true, characterData: true });
      __ocwpFullPass();
      return true;
    } catch (e) { __ocwpMo = null; return false; }
  }
  if (!__ocwpStartObserver()) {
    setTimeout(__ocwpStartObserver, 500);
    setTimeout(__ocwpStartObserver, 3000);
  }

  /* ── 壁纸层 ──────────────────────────────── */
  var layer = document.createElement('div');
  layer.id = 'oc-wallpaper';
  layer.className = 'aurora';
  (document.body || document.documentElement).appendChild(layer);

  // 皮肤生效标记：窗口标题出现 ✦ 即说明本脚本已运行
  try { document.title += ' ✦'; } catch (e) {}

  /* ── 用户自定义微调：wallpaper 目录下的 custom.css ─ */
  var WALLPAPER_DIR = '__WALLPAPER_DIR__/';
  var HERE = './';
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
      l.href = WALLPAPER_DIR + 'custom.css?t=' + Date.now();
      document.head.appendChild(l);
    } catch (e) {}
  }

  function clearLayer() {
    while (layer.firstChild) layer.removeChild(layer.firstChild);
  }

  function addShade() {
    var shade = document.createElement('div');
    shade.className = 'oc-wp-shade';
    layer.appendChild(shade);
  }

  function applyMedia(el) {
    layer.className = '';
    clearLayer();
    el.style.opacity = (el.tagName === 'VIDEO' ? CONFIG.videoOpacity : CONFIG.imageOpacity);
    layer.appendChild(el);
    addShade();
    if (el.tagName === 'VIDEO') { el.play().catch(function () {}); }
  }

  function loadMedia(url, onOk, onFail, timeoutMs) {
    var isVideo = /\.(mp4|webm)$/i.test(url.split('?')[0]);
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

  function probeList(urls, onOk, onExhausted) {
    var i = 0;
    (function next() {
      if (i >= urls.length) { onExhausted(); return; }
      var url = urls[i++];
      loadMedia(url, function (el) { onOk(el); }, next);
    })();
  }

  /* ── 1) 自动轮换：rotate/rotate-N.* 存在即启用 ── */
  var INTERVALS = [1, 5, 15, 30, 60, 120];
  var intervalTimer = null;

  function rotateStart(bust) {
    var idx = 0;
    try { idx = parseInt(localStorage.getItem('oc-wp-idx') || '0', 10) || 0; } catch (e) {}
    tryRotate(idx + 1, bust);
    detectInterval(0, bust);
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
      if (intervalTimer) clearInterval(intervalTimer);
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
      if (n > 1) tryRotate(1, bust);
      else probeStatic(0, bust);
    });
  }

  /* ── 2) 静态壁纸：wallpaper.<ext> ── */
  var staticDirs = hasUserDir ? [WALLPAPER_DIR, HERE] : [HERE];
  function probeStatic(dirIdx, bust) {
    if (dirIdx >= staticDirs.length) return;
    var urls = [];
    for (var i = 0; i < exts.length; i++) urls.push(staticDirs[dirIdx] + 'wallpaper.' + exts[i] + (bust ? '?v=' + bust : ''));
    probeList(urls, applyMedia, function () { probeStatic(dirIdx + 1, bust); });
  }

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

  /* ── 热切换：refresh-N.gif 标记轮询，免重启生效。页面隐藏时跳过 ── */
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
        img.src = ROTATE_DIR + 'refresh-' + idx + '.gif?t=' + Date.now();
      })(n);
    }
  }
  if (ROTATE_DIR) { setInterval(probeMarkers, 5000); }

  function resumeMedia() {
    var v = layer.querySelector('video');
    if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }
})();
