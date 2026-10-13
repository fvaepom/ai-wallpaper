#!/usr/bin/env node
/* patch-unpacked-html.js — WorkBuddy 5.8.2+ 外置 index.html 的字节中性补丁
 *
 * 背景（2026-10-13 踩坑）：Electron 的 asar 层对外置（unpacked）文件按【头部记录的
 * 原始 size】封顶读取——直接往文件里插入 <script> 会把文件尾部的字节挤出截断线，
 * 5.8.2 的 <div id="root"> 恰在尾部，被截掉后 React createRoot 拿到 null
 * （error #299），应用永远卡在骨架屏。因此注入必须【字节中性】：插入多少字节，
 * 就从文件里无害位置（空行）折叠掉多少字节，保证总大小不超过原始值。
 *
 * 用法: node patch-unpacked-html.js <index.html路径> <注入标签字符串> [asar头size]
 *   - 已包含 oc-wallpaper 标记时直接成功返回（幂等）
 *   - 锚点: 首个 "<script type=\"module\"" 前插入
 *   - 折叠规则: 把 "\r\n\r\n" → "\r\n"（LF 文件 "\n\n" → "\n"），逐处收缩，
 *     直到总长 ≤ 原长；HTML/CSS/无模板字面量的内联 JS 中删空行绝对安全
 */
'use strict';
const fs = require('fs');

function die(msg) { console.error('[patch-unpacked-html] ' + msg); process.exit(1); }

const [, , htmlPath, tag] = process.argv;
if (!htmlPath || !tag) die('用法: node patch-unpacked-html.js <index.html> <注入标签> [头size]');

const orig = fs.readFileSync(htmlPath);
if (orig.includes(Buffer.from('oc-wallpaper'))) {
  console.log('[patch-unpacked-html] 已包含壁纸脚本（幂等跳过）');
  process.exit(0);
}

const anchor = Buffer.from('<script type="module"');
const at = orig.indexOf(anchor);
if (at === -1) die('未找到模块 bundle 锚点 <script type="module"，此版本结构可能不兼容');
if (orig.indexOf(anchor, at + 1) !== -1) die('锚点不唯一（多处 <script type="module"），中止');

const tagBuf = Buffer.from(tag, 'utf8');
const head = orig.slice(0, at);
const tail = orig.slice(at);
let out = Buffer.concat([head, tagBuf, tail]);

/* 折叠空行：CRLF 文件找 \r\n\r\n（-2 字节），LF 文件找 \n\n（-1 字节） */
const CRLFCRLF = Buffer.from('\r\n\r\n');
const LFLF = Buffer.from('\n\n');
let budget = out.length - orig.length + 1; // 需要收缩的字节数（+1 保证严格 ≤ 原长）
let guard = 20000;
while (budget > 0 && guard-- > 0) {
  const pat = out.includes(CRLFCRLF) ? CRLFCRLF : (out.includes(LFLF) ? LFLF : null);
  if (!pat) die('空行预算耗尽仍未能收缩到原始大小以内（origLen=' + orig.length + '），中止');
  const i = out.indexOf(pat);
  out = Buffer.concat([out.slice(0, i), out.slice(i + pat.length - 1)]); // 保留一个换行
  budget -= pat.length - 1;
}

fs.writeFileSync(htmlPath, out);
console.log('[patch-unpacked-html] OK：注入 ' + tagBuf.length + ' B，折叠空行后总长 ' + out.length + ' B（原 ' + orig.length + ' B，asar 头 ' + (process.argv[4] || '?') + ' B）');
