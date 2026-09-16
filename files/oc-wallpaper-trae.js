/* zwp-ver:2 (2026-09-16) — 体检/apply-patch 据此识别已部署脚本是否为旧版 */
/* zcode-wallpaper — 壁纸层 + 界面透明化注入脚本（Trae CN / TRAE SOLO CN 版）
 *
 * 由 apply-patch.ps1 注入到应用主窗口 HTML（workbench.html / solo-lite.html 同目录）。
 * 壁纸查找顺序：
 *   1. 自动轮换（检测到 %USERPROFILE%\.trae-cn\wallpaper[-solo]\rotate\rotate-1.* 时启用）：
 *      每次页面加载按 localStorage 计数器换下一张 rotate-N.*
 *   2. 壁纸目录下的 wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 本文件同目录下的 wallpaper.*
 *   4. 都没有 → 内置"动态极光渐变"兜底
 * （__WALLPAPER_DIR__ 占位符由 apply-patch.ps1 替换为实际用户目录）
 *
 * 与 WorkBuddy 版的差异：
 *   - Trae 页面 CSP 带 require-trusted-types-for，全程不用 innerHTML（改用 DOM API 清空子节点）
 *   - 透明化变量在标准 --vscode-* 之外补充 Trae/icube 皮肤令牌
 *     （--vscode-icube-colorBg* / --vscode-icube--bg-bg-*，SOLO 外壳的 body 背景即 colorBg1）
 *   - SOLO 首页主面板（.panel-content）与输入框用的是 solo-lite 无前缀令牌
 *     --bg-bg-base-default / --bg-bg-base-secondary / --bg-bg-base-tertiary / --bg-bg-input，
 *     同样纳入透明化清单（弹层令牌 bg-bg-menu、bg-bg-tooltip 仍保持不透明）
 *   - 菜单/弹层/提示令牌（bg-bg-menu、bg-bg-tooltip、--vscode-menu-* 等）保持不透明
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

    /* 让界面透出壁纸：覆盖 VS Code 标准主题变量 + Trae/icube 皮肤令牌（CSS 兜底层）。
       主题服务的高特异性规则由下面的 JS 以「内联 !important」再覆盖一次（内联 > 任何样式表）。
       菜单/弹层/模态框保持较高不透明度保证可读（--ocwp-popup-bg 随主题切换取值） */    ':root,body{',
    '  --vscode-editor-background:rgba(255,255,255,.55) !important;',
    '  --vscode-sideBar-background:rgba(255,255,255,.5) !important;',
    '  --vscode-activityBar-background:rgba(255,255,255,.5) !important;',
    '  --vscode-titleBar-activeBackground:rgba(255,255,255,.55) !important;',
    '  --vscode-titleBar-inactiveBackground:rgba(255,255,255,.5) !important;',
    '  --vscode-statusBar-background:rgba(255,255,255,.6) !important;',
    '  --vscode-statusBar-noFolderBackground:rgba(255,255,255,.6) !important;',
    '  --vscode-panel-background:rgba(255,255,255,.5) !important;',
    '  --vscode-editorGroupHeader-tabsBackground:rgba(255,255,255,.45) !important;',
    '  --vscode-editorGroupHeader-noTabsBackground:rgba(255,255,255,.45) !important;',
    '  --vscode-input-background:rgba(255,255,255,.65) !important;',
    '  --vscode-dropdown-background:rgba(255,255,255,.8) !important;',
    '  --vscode-tab-activeBackground:rgba(255,255,255,.65) !important;',
    '  --vscode-tab-inactiveBackground:rgba(255,255,255,.45) !important;',
    '  --vscode-breadcrumb-background:rgba(255,255,255,.5) !important;',
    '  --vscode-terminal-background:rgba(255,255,255,.6) !important;',
    '  --vscode-icube-colorBg1:rgba(255,255,255,.55) !important;',
    '  --vscode-icube-colorBg2:rgba(255,255,255,.5) !important;',
    '  --vscode-icube-colorBg3:rgba(255,255,255,.5) !important;',
    '  --vscode-icube-colorBg4:rgba(255,255,255,.5) !important;',
    '  --vscode-icube-colorBg5:rgba(255,255,255,.5) !important;',
    '  --vscode-icube-colorBgCode:rgba(255,255,255,.6) !important;',
    '  --vscode-icube--bg-bg-base-default:rgba(255,255,255,.55) !important;',
    '  --vscode-icube--bg-bg-base-secondary:rgba(255,255,255,.5) !important;',
    '  --vscode-icube--bg-bg-base-tertiary:rgba(255,255,255,.5) !important;',
    '  --vscode-icube--bg-bg-overlay-l1:rgba(255,255,255,.55) !important;',
    '  --vscode-icube--bg-bg-overlay-l2:rgba(255,255,255,.5) !important;',
    '  --vscode-icube--bg-bg-overlay-l3:rgba(255,255,255,.5) !important;',
    '  --vscode-icube--bg-bg-overlay-l4:rgba(255,255,255,.5) !important;',
    /* SOLO 外壳（solo-lite）自带的【无前缀】设计令牌：主面板 .panel-content 的
       背景即 --bg-bg-base-default（回退 #fff），输入框用 --bg-bg-input —— 必须一并覆盖 */
    '  --bg-bg-base-default:rgba(255,255,255,.55) !important;',
    '  --bg-bg-base-secondary:rgba(255,255,255,.5) !important;',
    '  --bg-bg-base-tertiary:rgba(255,255,255,.5) !important;',
    '  --bg-bg-input:rgba(255,255,255,.6) !important;',
    '  --ocwp-popup-bg:#ffffff !important;',
    '  --vscode-menu-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorHoverWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-notifications-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-quickInput-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-icube--bg-bg-menu:var(--ocwp-popup-bg) !important;',
    '  --vscode-icube--bg-bg-tooltip:var(--ocwp-popup-bg) !important;}',
    'html,body{background:transparent !important;}',
    /* SOLO 外壳根容器背景（solo-lite.html body 内联 var(--vscode-icube-colorBg1)，
       colorBg1 被改半透明后这里自动跟随；显式声明防内联样式回写） */
    'html body{background-color:var(--vscode-icube-colorBg1) !important;}',

    /* icube 主题服务会给工作台布局容器写内联纯色背景（非 !important），
       样式表 !important 在级联上压得过内联普通声明 → 直接强透这些容器 */
    '.monaco-workbench{background-color:transparent !important;}',
    '.monaco-workbench .part{background-color:transparent !important;}',
    '.monaco-workbench .editor-container,.monaco-workbench .editor-group-container,',
    '.monaco-workbench .editor-group-container>.content,',
    '.monaco-workbench .content-area{background-color:transparent !important;}',
    /* 编辑器标签栏 / 面包屑 / 行号沟槽（icube 写死 rgb(23,25,26) 与 rgb(26,27,29)） */
    '.monaco-workbench .editor-group-container>.title,',
    '.monaco-workbench .editor-group-container>.title .tabs-container,',
    '.monaco-workbench .editor-group-container>.title .tabs-and-actions-container,',
    '.monaco-workbench .editor-group-container>.title .breadcrumb,',
    '.monaco-workbench .monaco-breadcrumb-tabs{background-color:transparent !important;}',
    '.monaco-editor .margin,.monaco-editor .margin-view-overlays,',
    '.monaco-editor .monaco-editor-background,.monaco-editor .sticky-widget,',
    '.monaco-editor .sticky-widget *{background-color:transparent !important;}',

    'body[data-vscode-theme-name*="Dark" i],body[data-vscode-theme-name*="dark"],',
    'body[data-vscode-theme-kind*="dark" i],',
    'body[data-vscode-theme-name*="Night" i],html.dark,body.dark{',
    '  --vscode-editor-background:rgba(30,30,30,.6) !important;',
    '  --vscode-sideBar-background:rgba(24,24,24,.55) !important;',
    '  --vscode-activityBar-background:rgba(24,24,24,.55) !important;',
    '  --vscode-titleBar-activeBackground:rgba(30,30,30,.6) !important;',
    '  --vscode-titleBar-inactiveBackground:rgba(30,30,30,.55) !important;',
    '  --vscode-statusBar-background:rgba(30,30,30,.65) !important;',
    '  --vscode-statusBar-noFolderBackground:rgba(30,30,30,.65) !important;',
    '  --vscode-panel-background:rgba(24,24,24,.55) !important;',
    '  --vscode-editorGroupHeader-tabsBackground:rgba(30,30,30,.5) !important;',
    '  --vscode-editorGroupHeader-noTabsBackground:rgba(30,30,30,.5) !important;',
    '  --vscode-input-background:rgba(45,45,45,.7) !important;',
    '  --vscode-dropdown-background:rgba(45,45,45,.85) !important;',
    '  --vscode-tab-activeBackground:rgba(30,30,30,.65) !important;',
    '  --vscode-tab-inactiveBackground:rgba(30,30,30,.5) !important;',
    '  --vscode-breadcrumb-background:rgba(30,30,30,.55) !important;',
    '  --vscode-terminal-background:rgba(30,30,30,.65) !important;',
    '  --vscode-icube-colorBg1:rgba(30,30,30,.6) !important;',
    '  --vscode-icube-colorBg2:rgba(24,24,24,.55) !important;',
    '  --vscode-icube-colorBg3:rgba(24,24,24,.55) !important;',
    '  --vscode-icube-colorBg4:rgba(24,24,24,.55) !important;',
    '  --vscode-icube-colorBg5:rgba(24,24,24,.55) !important;',
    '  --vscode-icube-colorBgCode:rgba(30,30,30,.65) !important;',
    '  --vscode-icube--bg-bg-base-default:rgba(30,30,30,.6) !important;',
    '  --vscode-icube--bg-bg-base-secondary:rgba(24,24,24,.55) !important;',
    '  --vscode-icube--bg-bg-base-tertiary:rgba(24,24,24,.55) !important;',
    '  --vscode-icube--bg-bg-overlay-l1:rgba(30,30,30,.6) !important;',
    '  --vscode-icube--bg-bg-overlay-l2:rgba(24,24,24,.55) !important;',
    '  --vscode-icube--bg-bg-overlay-l3:rgba(24,24,24,.55) !important;',
    '  --vscode-icube--bg-bg-overlay-l4:rgba(24,24,24,.55) !important;',
    '  --bg-bg-base-default:rgba(30,30,30,.6) !important;',
    '  --bg-bg-base-secondary:rgba(24,24,24,.55) !important;',
    '  --bg-bg-base-tertiary:rgba(45,45,45,.55) !important;',
    '  --bg-bg-input:rgba(30,30,30,.65) !important;',
    '  --ocwp-popup-bg:#252526 !important;',
    '  --vscode-menu-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorHoverWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-notifications-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-quickInput-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-icube--bg-bg-menu:var(--ocwp-popup-bg) !important;',
    '  --vscode-icube--bg-bg-tooltip:var(--ocwp-popup-bg) !important;}'
  ].join('\n');
  document.head.appendChild(style);

  /* ── 主题变量运行时覆盖 ────────────────────────
   * 内联 !important 覆盖两套变量（打赢应用的 body[data-vscode-theme-name] 高特异性规则），
   * 并监听主题名 / 内联样式变化自动重新覆盖（值相同则不写，收敛）。
   * 界面不透明度统一走 --ocwp-ui-alpha（custom.css 或选择器可改，改完即时生效）。 */
  var UI_A = 'var(--ocwp-ui-alpha,.55)';     // 浅色主题界面不透明度（可被 custom.css 覆盖）
  var UI_A_DARK = 'var(--ocwp-ui-alpha,.6)'; // 深色主题界面不透明度

  function lightVars() {
    return {
      '--vscode-editor-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-sideBar-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-activityBar-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-titleBar-activeBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-titleBar-inactiveBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-statusBar-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-statusBar-noFolderBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-panel-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-editorGroupHeader-tabsBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-editorGroupHeader-noTabsBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-input-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-dropdown-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-tab-activeBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-tab-inactiveBackground': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-breadcrumb-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-terminal-background': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube-colorBg1': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube-colorBg2': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube-colorBg3': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube-colorBg4': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube-colorBg5': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube-colorBgCode': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-base-default': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-base-secondary': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-base-tertiary': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-overlay-l1': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-overlay-l2': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-overlay-l3': 'rgba(255,255,255,' + UI_A + ')',
      '--vscode-icube--bg-bg-overlay-l4': 'rgba(255,255,255,' + UI_A + ')',
      '--bg-bg-base-default': 'rgba(255,255,255,' + UI_A + ')',
      '--bg-bg-base-secondary': 'rgba(255,255,255,' + UI_A + ')',
      '--bg-bg-base-tertiary': 'rgba(255,255,255,' + UI_A + ')',
      '--bg-bg-input': 'rgba(255,255,255,' + UI_A + ')',
      '--ocwp-popup-bg': '#ffffff',
      '--vscode-menu-background': '#ffffff',
      '--vscode-editorWidget-background': '#ffffff',
      '--vscode-editorHoverWidget-background': '#ffffff',
      '--vscode-notifications-background': '#ffffff',
      '--vscode-quickInput-background': '#ffffff',
      '--vscode-icube--bg-bg-menu': '#ffffff',
      '--vscode-icube--bg-bg-tooltip': '#ffffff'
    };
  }
  function darkVars() {
    return {
      '--vscode-editor-background': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-sideBar-background': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-activityBar-background': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-titleBar-activeBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-titleBar-inactiveBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-statusBar-background': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-statusBar-noFolderBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-panel-background': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-editorGroupHeader-tabsBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-editorGroupHeader-noTabsBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-input-background': 'rgba(45,45,45,' + UI_A_DARK + ')',
      '--vscode-dropdown-background': 'rgba(45,45,45,' + UI_A_DARK + ')',
      '--vscode-tab-activeBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-tab-inactiveBackground': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-breadcrumb-background': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-terminal-background': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-icube-colorBg1': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-icube-colorBg2': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube-colorBg3': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube-colorBg4': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube-colorBg5': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube-colorBgCode': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-base-default': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-base-secondary': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-base-tertiary': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-overlay-l1': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-overlay-l2': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-overlay-l3': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--vscode-icube--bg-bg-overlay-l4': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--bg-bg-base-default': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--bg-bg-base-secondary': 'rgba(24,24,24,' + UI_A_DARK + ')',
      '--bg-bg-base-tertiary': 'rgba(45,45,45,' + UI_A_DARK + ')',
      '--bg-bg-input': 'rgba(30,30,30,' + UI_A_DARK + ')',
      '--ocwp-popup-bg': '#252526',
      '--vscode-menu-background': '#252526',
      '--vscode-editorWidget-background': '#252526',
      '--vscode-editorHoverWidget-background': '#252526',
      '--vscode-notifications-background': '#252526',
      '--vscode-quickInput-background': '#252526',
      '--vscode-icube--bg-bg-menu': '#252526',
      '--vscode-icube--bg-bg-tooltip': '#252526'
    };
  }

  function isDarkTheme() {
    var name = '', kind = '';
    try {
      name = (document.body.getAttribute('data-vscode-theme-name') || '') + ' ' + (document.body.className || '');
      kind = document.body.getAttribute('data-vscode-theme-kind') || '';
    } catch (e) {}
    return /dark|night/i.test(name + ' ' + kind);
  }

  /* CSSOM 改写：应用在这些变量上的原始声明按原色改写成半透明（保留 RGB 只压 alpha）。
     只动「背景基色」令牌；菜单/提示/弹层令牌不在清单内（保持不透明） */
  var MANAGED = {};
  (function () {
    var names = [
      /* 标准 VS Code 主题变量 */
      '--vscode-editor-background',
      '--vscode-sideBar-background',
      '--vscode-activityBar-background',
      '--vscode-titleBar-activeBackground',
      '--vscode-titleBar-inactiveBackground',
      '--vscode-statusBar-background',
      '--vscode-statusBar-noFolderBackground',
      '--vscode-panel-background',
      '--vscode-editorGroupHeader-tabsBackground',
      '--vscode-editorGroupHeader-noTabsBackground',
      '--vscode-input-background',
      '--vscode-dropdown-background',
      '--vscode-tab-activeBackground',
      '--vscode-tab-inactiveBackground',
      '--vscode-breadcrumb-background',
      '--vscode-terminal-background',
      /* Trae/icube 皮肤令牌（SOLO 外壳 body 背景即 colorBg1） */
      '--vscode-icube-colorBg1',
      '--vscode-icube-colorBg2',
      '--vscode-icube-colorBg3',
      '--vscode-icube-colorBg4',
      '--vscode-icube-colorBg5',
      '--vscode-icube-colorBgCode',
      '--vscode-icube--bg-bg-base-default',
      '--vscode-icube--bg-bg-base-secondary',
      '--vscode-icube--bg-bg-base-tertiary',
      '--vscode-icube--bg-bg-overlay-l1',
      '--vscode-icube--bg-bg-overlay-l2',
      '--vscode-icube--bg-bg-overlay-l3',
      '--vscode-icube--bg-bg-overlay-l4',
      /* SOLO 外壳的无前缀设计令牌（主面板/输入框的实底背景） */
      '--bg-bg-base-default',
      '--bg-bg-base-secondary',
      '--bg-bg-base-tertiary',
      '--bg-bg-input'
    ];
    for (var i = 0; i < names.length; i++) MANAGED[names[i]] = 1;
  })();
  var BG_ALPHA = '0.5'; // 改写后的不透明度（0~1，越小越透）

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

  /* 递归改写一条规则里被管理的变量声明 */
  function rewriteRuleStyle(s) {
    for (var j = s.length - 1; j >= 0; j--) {
      var prop = s[j];
      if (!MANAGED[prop]) continue;
      var rgb = parseColor(s.getPropertyValue(prop));
      if (rgb) s.setProperty(prop, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + BG_ALPHA + ')', 'important');
      /* var() 引用链不动 —— 被引用的变量本身也会被改写成半透明 */
    }
  }

  function rewriteSheetRules(rules) {
    for (var i = 0; i < rules.length; i++) {
      var r = rules[i];
      if (r.style) rewriteRuleStyle(r.style);
      if (r.cssRules && r.cssRules.length) rewriteSheetRules(r.cssRules);
    }
  }

  function rewriteAllSheets() {
    /* 界面不透明度：每轮从 --ocwp-ui-alpha 读取（custom.css / 选择器可改，改动即时生效） */
    var uiAlpha = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--ocwp-ui-alpha'));
    if (!isNaN(uiAlpha)) BG_ALPHA = String(uiAlpha);
    for (var s = 0; s < document.styleSheets.length; s++) {
      var sheet = document.styleSheets[s];
      if (isOwnSheet(sheet)) continue;
      var rules;
      try { rules = sheet.cssRules; } catch (e) { continue; }
      rewriteSheetRules(rules);
    }
    /* 构造式样式表：document / shadow root 的 adoptedStyleSheets */
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

  /* ── adopted 镜像表：应用若把皮肤规则装载在构造式样式表（adoptedStyleSheets）里，
     级联顺序排在普通 <style> 之后，同权重 !important 时它赢。
     把全部透明化规则镜像进一个挂到末尾的 adopted 表，后挂者赢 → 压制皮肤纯色 ── */
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

  /* 完整覆盖一轮：CSSOM 改写 + 内联变量 + adopted 镜像 */
  function __ocwpFullPass() {
    try { rewriteAllSheets(); assertThemeVars(); ensureAdoptedSheet(); } catch (e) {}
  }
  __ocwpFullPass();

  /* link 样式表异步加载完成不会触发 head 的 DOM 变更 → 监听资源 load 事件（不冒泡，用 capture）
     再加多级重试兜底，覆盖 CSS-in-JS 延迟注入、皮肤延迟加载等场景 */
  document.addEventListener('load', __ocwpFullPass, true);
  document.addEventListener('DOMContentLoaded', __ocwpFullPass);
  window.addEventListener('load', __ocwpFullPass);
  [500, 1500, 4000, 8000].forEach(function (t) { setTimeout(__ocwpFullPass, t); });
  /* 皮肤系统可能整体替换 adoptedStyleSheets，低频兜底；页面隐藏时跳过（恢复可见时
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

  /* head 里新增 <style>（CSS-in-JS 按需注入）或主题切换时也要重新覆盖一轮。
     回调做 200ms 防抖合并，隐藏期间跳过（恢复可见时 visibilitychange 会补一轮） */
  var __ocwpMo = null, __moTimer = null;
  function __moFire() {
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
      __ocwpMo.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class', 'data-vscode-theme-name', 'data-vscode-theme-kind'] });
      __ocwpMo.observe(document.body, { attributes: true, attributeFilter: ['style', 'class', 'data-vscode-theme-name', 'data-vscode-theme-kind'] });
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
      customLink.id = 'ocwp-custom';
      customLink.href = WALLPAPER_DIR + 'custom.css';
      document.head.appendChild(customLink);
    } catch (e) {}
  }

  /* 重载 custom.css（选择器改了透明度等参数后由 refresh 标记触发） */
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

  /* 清空壁纸层（Trusted Types 安全：不用 innerHTML） */
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
     位图变化即带缓存穿透重探壁纸，免重启生效。页面隐藏时跳过 ── */
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
