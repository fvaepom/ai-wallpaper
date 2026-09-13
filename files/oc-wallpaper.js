/* zcode-wallpaper — 壁纸层 + 界面透明化注入脚本
 *
 * 由 apply-patch.ps1 注入到 ZCode 主窗口 index.html。
 * 壁纸查找顺序：
 *   1. %USERPROFILE%\.zcode\wallpaper\wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *      （__WALLPAPER_DIR__ 占位符由补丁脚本替换为实际用户目录）
 *   2. 本文件同目录下的 wallpaper.*
 *   3. 都没有 → 内置动态极光渐变兜底
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
  if (WALLPAPER_DIR.indexOf('__') === -1) {
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

  /* ── 探测用户壁纸文件（外部目录优先，其次同目录） ── */
  var exts = ['mp4', 'webm', 'gif', 'webp', 'png', 'jpg'];
  var HERE = './';
  var HERE_ONLY = WALLPAPER_DIR.indexOf('__') !== -1; // 占位符未替换时只探测同目录

  function candidates() {
    var list = [];
    var bases = HERE_ONLY ? [HERE] : [WALLPAPER_DIR, HERE];
    for (var d = 0; d < bases.length; d++) {
      for (var i = 0; i < exts.length; i++) list.push({ base: bases[d], ext: exts[i] });
    }
    return list;
  }

  function tryNext(idx) {
    var list = candidates();
    if (idx >= list.length) return; // 没有壁纸文件，保留极光兜底
    var c = list[idx];
    var url = c.base + 'wallpaper.' + c.ext;
    var isVideo = c.ext === 'mp4' || c.ext === 'webm';
    if (isVideo) {
      var v = document.createElement('video');
      v.src = url;
      v.autoplay = true;
      v.loop = true;
      v.muted = true;
      v.playsInline = true;
      v.style.opacity = CONFIG.videoOpacity;
      var done = false;
      v.addEventListener('loadeddata', function () {
        if (done) return;
        done = true;
        layer.className = '';
        layer.appendChild(v);
        addShade();
        v.play().catch(function () {});
      });
      v.addEventListener('error', function () {
        if (done) return;
        done = true;
        tryNext(idx + 1);
      });
      setTimeout(function () {
        if (!done) { done = true; v.removeAttribute('src'); v.load(); tryNext(idx + 1); }
      }, 4000);
    } else {
      var img = new Image();
      img.onload = function () {
        layer.className = '';
        img.style.opacity = CONFIG.imageOpacity;
        layer.appendChild(img);
        addShade();
      };
      img.onerror = function () { tryNext(idx + 1); };
      img.src = url;
    }
  }
  tryNext(0);
})();
