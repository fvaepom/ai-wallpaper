/* zcode-wallpaper — 壁纸层 + 界面透明化注入脚本（VS Code 主题变量版，适用于 WorkBuddy 等）
 *
 * 由 apply-patch.ps1 注入到应用主窗口 index.html。
 * 壁纸查找顺序：
 *   1. 自动轮换（检测到 %USERPROFILE%\.workbuddy\wallpaper\rotate\rotate-1.* 时启用）：
 *      每次页面加载按 localStorage 计数器换下一张 rotate-N.*
 *   2. %USERPROFILE%\.workbuddy\wallpaper\wallpaper.mp4 / .webm / .gif / .webp / .png / .jpg
 *   3. 本文件同目录下的 wallpaper.*
 *   4. 都没有 → 内置"动态极光渐变"兜底
 * （__WALLPAPER_DIR__ 占位符由 apply-patch.ps1 替换为实际用户目录）
 *
 * 与 ZCode 版的唯一区别：透明化走 --vscode-* 主题变量（WorkBuddy 用 VS Code 主题体系，
 * 不存在 ZCode 的 Tailwind --color-* 语义变量）。
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
  style.textContent = '@layer ocwp;\n' + // 最早声明的层：important 声明中最早层必胜（压制皮肤表的后挂/未分层 important）
  '@layer ocwp {\n' + [
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

    /* 让界面透出壁纸：覆盖 VS Code 主题变量（CSS 兜底层）。
       注意：WorkBuddy 自带皮肤系统的选择器（如 body[data-vscode-theme-name=…]）特异性更高，
       运行时会由下面的 JS 以「内联 !important」方式再覆盖一次（内联 > 任何样式表）。
       弹层/菜单保持较高不透明度保证可读 */
    ':root,body{',
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
    '  --wb-home-bg-primary:rgba(255,255,255,.6) !important;',
    '  --wb-home-bg-secondary:rgba(255,255,255,.5) !important;',
    '  --wb-bg-primary:rgba(255,255,255,.7) !important;',
    '  --wb-bg-secondary:rgba(255,255,255,.65) !important;',
    '  --wb-bg-tertiary:rgba(255,255,255,.6) !important;',
    '  --wb-main-area-background:rgba(255,255,255,.7) !important;',
    '  /* 菜单/弹层/模态框保持完全不透明（--ocwp-popup-bg 随主题切换取值） */',
    '  --ocwp-popup-bg:#ffffff !important;',
    '  --wb-bg-popover:var(--ocwp-popup-bg) !important;',
    '  --wb-bg-modal:var(--ocwp-popup-bg) !important;',
    '  --wb-dropdown-bg-color:var(--ocwp-popup-bg) !important;',
    '  --wb-dropdown-item-hover-bg-color:rgba(0,0,0,.06) !important;',
    '  --vscode-menu-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorHoverWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-notifications-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-quickInput-background:var(--ocwp-popup-bg) !important;}',
    'html body .wb-popover{background-color:var(--ocwp-popup-bg) !important;background-image:none !important;}',

    /* 左栏其余卡片：新建任务按钮（React 内联）、任务/空间分组头、折叠目录头（AI工作台等）。
       这些背景在应用的 adoptedStyleSheets 里且带 !important（比普通 <style> 靠后），
       单靠下面的 <style> 打不过 → 由 ensureAdoptedSheet() 把全部规则镜像到 adopted 表末尾压制 */
    'html body .conversation-list{background-color:transparent !important;background-image:none !important;}',
    'html body .conversation-list-tab-button,',
    'html body .conversation-section-label,',
    'html body [class*="_header_1h739"],',
    'html body [class*="collapsible-sect"][class*="_header_"]{',
    '  background-color:transparent !important;background-image:none !important;}',

    /* 首页的"单一纱层"模型：只有 .teams-container 这一层按滑杆铺半透明底，
       嵌套的网格项 / 路由容器全部透明——多层半透明叠加会乘法变糊（25% 叠三层≈58%），
       单层模型下滑杆值即最终视觉不透明度，严格线性 */
    'html body .teams-container{background-color:rgba(255,255,255,var(--ocwp-ui-alpha,.55)) !important;',
    '  background-image:none !important;}',
    'html body [class*="_gridViewItem"],html body [class*="_gridView"],html body [class*="_grid_"],',
    'html body .wb-home-route{background-color:transparent !important;background-image:none !important;}',

    /* 首页输入框：容器是 React 内联白底，盒子是样式表渐变 */
    'html body .cr-input-container{background-color:transparent !important;background-image:none !important;}',
    'html body .cr-input-box__main{background-image:none !important;',
    '  background-color:rgba(255,255,255,var(--ocwp-ui-alpha,.55)) !important;}',
    'body[data-vscode-theme-name*="Dark" i] .teams-container,body[data-vscode-theme-name*="dark"] .teams-container,',
    'body[data-vscode-theme-name*="Night" i] .teams-container,html.dark .teams-container,body.dark .teams-container{',
    '  background-color:rgba(24,24,24,var(--ocwp-ui-alpha,.6)) !important;}',
    'body[data-vscode-theme-name*="Dark" i] .cr-input-box__main,body[data-vscode-theme-name*="dark"] .cr-input-box__main,',
    'body[data-vscode-theme-name*="Night" i] .cr-input-box__main,html.dark .cr-input-box__main,body.dark .cr-input-box__main{',
    '  background-color:rgba(45,45,45,var(--ocwp-ui-alpha,.6)) !important;}',
    'body[data-vscode-theme-name*="Dark" i],body[data-vscode-theme-name*="dark"],',
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
    '  --wb-home-bg-primary:rgba(31,31,31,.65) !important;',
    '  --wb-home-bg-secondary:rgba(20,20,20,.6) !important;',
    '  --wb-bg-primary:rgba(38,38,38,.75) !important;',
    '  --wb-bg-secondary:rgba(45,45,45,.7) !important;',
    '  --wb-bg-tertiary:rgba(58,58,58,.65) !important;',
    '  --wb-main-area-background:rgba(38,38,38,.75) !important;',
    '  --ocwp-popup-bg:#252526 !important;',
    '  --wb-bg-popover:var(--ocwp-popup-bg) !important;',
    '  --wb-bg-modal:var(--ocwp-popup-bg) !important;',
    '  --wb-dropdown-bg-color:var(--ocwp-popup-bg) !important;',
    '  --wb-dropdown-item-hover-bg-color:rgba(255,255,255,.08) !important;',
    '  --vscode-menu-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-editorHoverWidget-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-notifications-background:var(--ocwp-popup-bg) !important;',
    '  --vscode-quickInput-background:var(--ocwp-popup-bg) !important;}',
    'html,body{background:transparent !important;}',

    /* 输入框深色主题变体 */
    'body[data-vscode-theme-name*="Dark" i] .cr-input-box__main,',
    'body[data-vscode-theme-name*="dark"] .cr-input-box__main,',
    'body[data-vscode-theme-name*="Night" i] .cr-input-box__main,',
    'html.dark .cr-input-box__main,body.dark .cr-input-box__main{',
    '  background-color:rgba(45,45,45,var(--ocwp-ui-alpha,.6)) !important;}',

    /* 启动骨架屏也透出壁纸（React 挂载前的那几秒） */
    '#skeleton-root{--sk-bg:rgba(255,255,255,.55) !important;',
    '  --sk-sidebar-bg:rgba(255,255,255,.5) !important;',
  ].join('\n') + '\n}';
  document.head.appendChild(style);

  /* ── 主题变量运行时覆盖 ────────────────────────
   * 1) 内联 !important 覆盖 --vscode-*（打赢应用的 body[data-vscode-theme-name] 高特异性规则），
   *    并监听主题名 / 内联样式变化自动重新覆盖（值相同则不写，收敛）。
   *    界面不透明度统一走 --ocwp-ui-alpha（custom.css 或选择器可改，改完即时生效）。
   * 2) WorkBuddy 的页面级容器（.teams-container、各 page 根节点）会在自己的 CSS 里重新声明
   *    --wb-home-bg-* / --wb-bg-*，继承打不进去 → 直接改写应用 CSSOM：
   *    把这些变量的声明按原色改写成半透明（保留 RGB 只压 alpha），皮肤渐变图变量置 none。 */
  var UI_A = 'var(--ocwp-ui-alpha,.55)';   // 浅色主题界面不透明度（可被 custom.css 覆盖）
  var UI_A_DARK = 'var(--ocwp-ui-alpha,.6)'; // 深色主题界面不透明度
  var LIGHT_VARS = {
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
    '--wb-home-bg-primary': 'rgba(255,255,255,' + UI_A + ')',
    '--wb-home-bg-secondary': 'rgba(255,255,255,' + UI_A + ')',
    '--wb-bg-primary': 'rgba(255,255,255,' + UI_A + ')',
    '--wb-bg-secondary': 'rgba(255,255,255,' + UI_A + ')',
    '--wb-bg-tertiary': 'rgba(255,255,255,' + UI_A + ')',
    '--wb-main-area-background': 'rgba(255,255,255,' + UI_A + ')',
    '--ocwp-popup-bg': '#ffffff',
    '--wb-bg-popover': '#ffffff',
    '--wb-bg-modal': '#ffffff',
    '--wb-dropdown-bg-color': '#ffffff',
    '--vscode-menu-background': '#ffffff',
    '--vscode-editorWidget-background': '#ffffff',
    '--vscode-editorHoverWidget-background': '#ffffff',
    '--vscode-notifications-background': '#ffffff',
    '--vscode-quickInput-background': '#ffffff'
  };
  var DARK_VARS = {
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
    '--wb-home-bg-primary': 'rgba(31,31,31,' + UI_A_DARK + ')',
    '--wb-home-bg-secondary': 'rgba(20,20,20,' + UI_A_DARK + ')',
    '--wb-bg-primary': 'rgba(38,38,38,' + UI_A_DARK + ')',
    '--wb-bg-secondary': 'rgba(45,45,45,' + UI_A_DARK + ')',
    '--wb-bg-tertiary': 'rgba(58,58,58,' + UI_A_DARK + ')',
    '--wb-main-area-background': 'rgba(38,38,38,' + UI_A_DARK + ')',
    '--ocwp-popup-bg': '#252526',
    '--wb-bg-popover': '#252526',
    '--wb-bg-modal': '#252526',
    '--wb-dropdown-bg-color': '#252526',
    '--vscode-menu-background': '#252526',
    '--vscode-editorWidget-background': '#252526',
    '--vscode-editorHoverWidget-background': '#252526',
    '--vscode-notifications-background': '#252526',
    '--vscode-quickInput-background': '#252526'
  };

  function isDarkTheme() {
    var name = '';
    try { name = (document.body.getAttribute('data-vscode-theme-name') || '') + ' ' + (document.body.className || ''); } catch (e) {}
    return /dark|night/i.test(name);
  }

  /* 收集应用自定义皮肤背景图变量（--wb-custom-img-*，多为内置渐变，置空让壁纸透出） */
  var MANAGED_WB_RE = /^--(wb-home-bg|wb-bg|wb-main-area-background|wb-custom-img)/;
  /* 弹层/菜单/交互态令牌保持不透明：不改写（菜单不要透明） */
  var WB_SKIP_RE = /^--(wb-bg-(popover|modal|hover|active|overlay|dropdown|menu|input|button|tooltip)|wb-dropdown|wb-border|wb-menu)/;
  var WB_BG_ALPHA = '0.5'; // 改写后的不透明度（0~1，越小越透）

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
      if (!MANAGED_WB_RE.test(prop) || WB_SKIP_RE.test(prop)) continue;
      var val = s.getPropertyValue(prop);
      if (prop.indexOf('--wb-custom-img') === 0) {
        s.setProperty(prop, 'none', 'important');
        continue;
      }
      var rgb = parseColor(val);
      if (rgb) s.setProperty(prop, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + WB_BG_ALPHA + ')', 'important');
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
    if (!isNaN(uiAlpha)) WB_BG_ALPHA = String(uiAlpha);
    /* 1) 普通样式表（<style>/<link>） */
    for (var s = 0; s < document.styleSheets.length; s++) {
      var sheet = document.styleSheets[s];
      if (isOwnSheet(sheet)) continue;
      var rules;
      try { rules = sheet.cssRules; } catch (e) { continue; }
      rewriteSheetRules(rules);
    }
    /* 2) 构造式样式表：document / shadow root 的 adoptedStyleSheets
       （WorkBuddy 的皮肤系统用 new CSSStyleSheet() 装载主题，不在 document.styleSheets 里） */
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
    var vars = isDarkTheme() ? DARK_VARS : LIGHT_VARS;
    var targets = [document.documentElement, document.body];
    for (var t = 0; t < targets.length; t++) {
      var el = targets[t];
      if (!el) continue;
      for (var k in vars) {
        if (el.style.getPropertyValue(k) !== vars[k]) el.style.setProperty(k, vars[k], 'important');
      }
    }
    for (var c in customImgVars) {
      if (document.documentElement.style.getPropertyValue(c) !== customImgVars[c]) {
        document.documentElement.style.setProperty(c, customImgVars[c], 'important');
      }
    }
  }

  /* ── adopted 镜像表：应用的皮肤规则装载在构造式样式表（adoptedStyleSheets）里，
     级联顺序排在普通 <style> 之后，同权重 !important 时它赢。
     把全部透明化规则镜像进一个挂到末尾的 adopted 表，后挂者赢 → 压制皮肤纯色。
     皮肤系统重挂数组导致镜像丢失时，fullPass 会自动补挂。 ── */
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

  /* 完整覆盖一轮：CSSOM 改写 + 内联变量 + adopted 镜像 + 表面清理 */
  function __ocwpFullPass() {
    /* 每步独立容错：任何一步抛错都不影响其余步骤（尤其表面清理必须执行） */
    try { rewriteAllSheets(); } catch (e) {}
    try { assertThemeVars(); } catch (e) {}
    try { ensureAdoptedSheet(); } catch (e) {}
    try { __ocwpScrub(); } catch (e) {}
  }

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

  /* ── 表面清理器：皮肤系统在 adoptedStyleSheets 里给这些元素写了带 !important 的
     纯色背景，任何样式表（含后挂 adopted）都打不过 → 唯一稳定压过它们的是
     元素内联 !important。值相同不写，收敛无循环。 ── */
  var SCRUB_SELECTOR = [
    '.conversation-list',
    '.conversation-list-tab-button',
    '.conversation-section-label',
    '[class*="_header_1h739"]',
    '[class*="collapsible-sect"][class*="_header_"]',
    '.cr-input-container',
    '.cr-input-toolbar__right',
    '.cb-agent-card'
  ].join(',');
  /* 选中态/控件卡片：不钉全透明（保留选中标识），钉成跟随滑杆的半透明主题色，
     叠在纱层上自然形成浅一档的高亮 */
  var SCRUB_TINTED_SELECTOR = ['.cb-agent-card[class*="_selected_"]', '.industry-template-switcher__trigger'].join(',');
  function scrubSurfaces() {
    var col = isDarkTheme()
      ? 'rgba(70,70,70,var(--ocwp-ui-alpha,.5))'
      : 'rgba(255,255,255,var(--ocwp-ui-alpha,.5))';
    /* 大面积面板 → 全透明（浓淡由 .teams-container 的单一纱层统一控制，
       多层各自半透明会乘法叠加导致非线性观感） */
    var els = document.querySelectorAll(SCRUB_SELECTOR);
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.matches && SCRUB_TINTED_SELECTOR && el.matches(SCRUB_TINTED_SELECTOR)) continue; // 选中卡片由 tinted 分支处理
      if (el.style.getPropertyValue('background-color') !== 'transparent') {
        el.style.setProperty('background-color', 'transparent', 'important');
      }
      var bi = el.style.getPropertyValue('background-image');
      if (bi !== '' && bi !== 'none') {
        el.style.setProperty('background-image', 'none', 'important');
      }
    }
    var tinted = document.querySelectorAll(SCRUB_TINTED_SELECTOR);
    for (var t = 0; t < tinted.length; t++) {
      var te = tinted[t];
      if (te.style.getPropertyValue('background-color') !== col) {
        te.style.setProperty('background-color', col, 'important');
      }
      var tbi = te.style.getPropertyValue('background-image');
      if (tbi !== '' && tbi !== 'none') {
        te.style.setProperty('background-image', 'none', 'important');
      }
    }
  }

  var __scrubTimer = null;
  function __ocwpScrub() {
    if (__scrubTimer) return;
    __scrubTimer = setTimeout(function () {
      __scrubTimer = null;
      try { scrubSurfaces(); } catch (e) {}
    }, 150);
  }

  /* head 里新增 <style>（CSS-in-JS 按需注入）或主题切换时也要重新覆盖一轮。
     回调做 200ms 防抖合并——React/CSS-in-JS 高频 DOM 变更下全量 pass 很贵；
     隐藏期间直接跳过（恢复可见时 visibilitychange 会补一轮） */
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
      __ocwpMo.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class', 'data-vscode-theme-name'] });
      __ocwpMo.observe(document.body, { attributes: true, attributeFilter: ['style', 'class', 'data-vscode-theme-name'] });
      __ocwpMo.observe(document.head, { childList: true, subtree: true, characterData: true });
      /* 侧栏列表是虚拟滚动 + React 频繁重渲染，子树变化也要补刮 */
      __ocwpMo.observe(document.body, { childList: true, subtree: true });
      __ocwpFullPass();
      __ocwpScrub();
      return true;
    } catch (e) { __ocwpMo = null; return false; }
  }
  __ocwpFullPass(); // 此时 SCRUB_SELECTOR 等已就绪，首轮即可完成清理
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

  /* bust = 缓存穿透串（热切换重探时传时间戳）：同名文件被选择器覆盖后，
     Chromium 可能仍回旧缓存图，带 ?v= 强制按磁盘现值重载 */
  function rotateStart(bust) {
    var idx = 0;
    try { idx = parseInt(localStorage.getItem('oc-wp-idx') || '0', 10) || 0; } catch (e) {}
    tryRotate(idx + 1, bust);
    detectInterval(0, bust); // 探测 interval-N.gif → 有则启动定时换片
  }

  function detectInterval(i, bust) {
    if (i >= INTERVALS.length) return;
    var minutes = INTERVALS[i];
    var img = new Image();
    img.onload = function () {
      if (intervalTimer) clearInterval(intervalTimer); // 热切换重探后不留旧定时器
      intervalTimer = setInterval(function () {
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
     兼容只探测 1..3 的旧版已部署脚本），每 5 秒探测一次，位图变化即带缓存穿透
     重探壁纸，免重启生效。页面隐藏时跳过——不再用 Worker 心跳绕过节流（后台
     本来就不需要发现改动，恢复可见时 visibilitychange 会立即补测），常驻定时器少一半 ── */
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
