#!/usr/bin/env node
/* patch-inplace.js — asar 原地补丁（零依赖，不重组归档）
 *
 * 与"解包→重打包"不同，本脚本保留归档数据区原样：
 *   1. 解析 asar 头部（Chromium Pickle 格式）
 *   2. 删除引用了磁盘上不存在文件的 unpacked 悬空条目（WorkBuddy 安装器只落盘 x64，
 *      但索引里残留 arm64/darwin/linux 引用），腾出头部字节预算
 *   3. 在指定目录新增注入脚本条目；index.html 插入 <script> 引用，
 *      内容追加到归档末尾，条目的 offset/size/integrity（SHA256 + 4MB 分块）同步更新
 *   4. 新头部 JSON 若不比原来长 → 尾部补空格使头部长度不变，仅改写头部 + 末尾追加（秒级）；
 *      否则 → 流式重写（数据区字节原样拷贝，条目偏移相对数据区所以依然有效）
 *   5. 全量自校验：重新解析，逐文件重算 SHA256 与头部比对，全部通过才替换原文件
 *   6. 可选 --exe <主程序>：Electron 启用 asar 完整性 fuse 时（如 WorkBuddy，Electron 37），
 *      主程序内嵌 JSON 数组存有 app.asar 头部哈希，头部变更会被静默处决。
 *      本脚本自动把 exe 中旧头部哈希（64 位 hex 字符串）替换为新哈希（等长原地替换）。
 *
 * 用法：
 *   node patch-inplace.js <app.asar> <renderer目录> <index.html名> <注入js文件名> <注入js源文件> [bundle前缀]
 *                          [--exe <主程序路径>]
 *                          [--also-patch <归档内文件路径> <查找正则文件> <替换文本文件> <追加文本文件>]
 *   bundle前缀：主 bundle 文件名前缀（默认 index，OpenCode 桌面端为 main）
 *   --also-patch：对归档内另一个文件做"正则替换(必须恰好1处) + 末尾追加文本"，
 *                 内容同样写到归档尾部并更新条目 integrity（OpenCode 主进程 wp:// 桥用）
 *   node patch-inplace.js --stat <app.asar>
 *   node patch-inplace.js --resolve <app.asar> <归档内目录> <文件名前缀>   （打印带哈希的主 bundle 文件名）
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const BLOCK_SIZE = 4 * 1024 * 1024;

function die(msg) { console.error('[patch-inplace] ' + msg); process.exit(1); }

function integrityOf(buf) {
  const hash = crypto.createHash('SHA256').update(buf).digest('hex');
  const blocks = [];
  for (let off = 0; off < buf.length; off += BLOCK_SIZE) {
    blocks.push(crypto.createHash('SHA256').update(buf.subarray(off, Math.min(off + BLOCK_SIZE, buf.length))).digest('hex'));
  }
  if (buf.length === 0) blocks.push(crypto.createHash('SHA256').update(buf).digest('hex'));
  return { algorithm: 'SHA256', hash, blockSize: BLOCK_SIZE, blocks };
}

/* ── asar 头部解析（与 @electron/asar lib/disk.js 的磁盘布局一致） ── */
function readHeader(fd) {
  const sizeBuf = Buffer.alloc(8);
  if (fs.readSync(fd, sizeBuf, 0, 8, 0) !== 8) die('无法读取头部大小');
  const headerSize = sizeBuf.readUInt32LE(4); // sizePickle = [u32 payloadLen=4][u32 headerSize]
  const headerBuf = Buffer.alloc(headerSize);
  if (fs.readSync(fd, headerBuf, 0, headerSize, 8) !== headerSize) die('无法读取头部内容');
  /* headerPickle 布局：[u32 payloadSize][u32 strLen][json][pad4]，字符串从偏移 8 开始 */
  const strLen = headerBuf.readUInt32LE(4);
  const json = headerBuf.toString('utf8', 8, 8 + strLen);
  return { headerSize, headerBuf, json, header: JSON.parse(json) };
}

/* ── 头部 Pickle 编码：[u32 payloadLen][u32 strLen][utf8][pad4] ── */
function headerPickle(json) {
  const strBuf = Buffer.from(json, 'utf8');
  const pad = (4 - (strBuf.length % 4)) % 4;
  const out = Buffer.alloc(8 + strBuf.length + pad);
  out.writeUInt32LE(4 + strBuf.length + pad, 0);
  out.writeUInt32LE(strBuf.length, 4);
  strBuf.copy(out, 8);
  return out;
}

function getNode(header, parts) {
  let node = header;
  for (const part of parts) {
    if (!node.files || !node.files[part]) return null;
    node = node.files[part];
  }
  return node;
}

/* ── 收集 unpacked 悬空条目 ──
   磁盘枚举只发生在主流程（对已校验的 asarPath + '.unpacked' 这一条字面量路径，
   带 root 前缀逃逸防护）；本函数是纯集合差集：归档头部清单里声明 unpacked、
   而磁盘上不存在的条目。头部文件名可能被构造，绝不拿它拼接磁盘路径，
   只做名字合法性校验（无分隔符/点项/绝对路径）。 */
function diffStaleEntries(header, onDisk) {
  const stale = [];
  (function walk(node, rel) {
    for (const [name, child] of Object.entries(node.files)) {
      if (name === '..' || name === '.' || name.includes('/') || name.includes('\\') || path.isAbsolute(name)) continue;
      const childRel = rel ? rel + '/' + name : name;
      if (child.files) { walk(child, childRel); continue; }
      if (child.unpacked && !onDisk.has(childRel)) stale.push(childRel);
    }
  })(header, '');
  return stale;
}

function removeStale(header, staleList) {
  for (const rel of staleList) {
    const parts = rel.split('/');
    const name = parts.pop();
    const parent = getNode(header, parts);
    if (parent && parent.files && parent.files[name]) delete parent.files[name];
  }
}

/* ── 主流程 ── */
const args = process.argv.slice(2);
const statOnly = args[0] === '--stat';
/* --resolve <归档内目录> <文件名前缀>：打印目录下匹配前缀的文件名（主 bundle 文件名带哈希，换版本会变） */
const resolveMode = args[0] === '--resolve';
/* --out <路径>：补丁结果写到指定路径、不替换原文件（MSIX 包目录内新建文件会被拒，
   由调用方拿到输出后覆写原 asar 的文件内容） */
let outPath = null;
let positional = [], exePath = null, alsoPatch = null;
if (statOnly) {
  positional = [args[1]];
} else if (resolveMode) {
  positional = [args[1], args[2], 'x', 'x', 'x'];
} else {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--exe') { exePath = args[++i]; continue; }
    if (args[i] === '--out') { outPath = args[++i]; continue; }
    if (args[i] === '--also-patch') {
      alsoPatch = { relPath: args[++i], findFile: args[++i], replaceFile: args[++i], appendFile: args[++i] };
      continue;
    }
    positional.push(args[i]);
  }
}
const [asarPath, rendererDir, indexName, injectName, injectSrc, bundleName] = positional;
if (statOnly ? !asarPath : (!asarPath || !rendererDir || !indexName || !injectName || !injectSrc)) {
  die('用法: node patch-inplace.js <app.asar> <renderer目录> <index.html名> <注入js文件名> <注入js源文件> [bundle前缀] [--exe <主程序路径>] | --stat <app.asar>');
}

/* 输入路径硬化：只接受"本机存在的 .asar 文件 + 绝对路径"。本工具仅在本机对
   目标应用原地打补丁，后续全部 fs 访问都基于这一条已校验路径，不拼接任何
   来自归档头部的名字；归档内文件名只做集合比对/合法性校验（见 diffStaleEntries）。 */
if (!path.isAbsolute(asarPath) || !/\.asar$/i.test(asarPath)) {
  die('asar 路径必须是 .asar 文件的绝对路径');
}
if (!fs.existsSync(asarPath)) die(`asar 文件不存在: ${asarPath}`);

const unpackedDir = asarPath + '.unpacked';
const fd = fs.openSync(asarPath, 'r');
const archiveSize = fs.fstatSync(fd).size;
const { headerSize, headerBuf, json: oldJson, header } = readHeader(fd);
const dataStart = 8 + headerSize;

/* Electron 头部完整性校验所用的旧哈希（对头部 JSON 字节做 SHA256） */
const oldHeaderHash = crypto.createHash('SHA256').update(Buffer.from(oldJson, 'utf8')).digest('hex');

if (!statOnly) {
  const targetDir = getNode(header, rendererDir.split('/'));
  if (!targetDir || !targetDir.files) die(`归档中未找到目录 ${rendererDir}`);
  if (targetDir.files[injectName]) die(`${rendererDir}/${injectName} 已存在——看起来已打过补丁`);
}
/* 枚举磁盘上的 .unpacked 目录（唯一 fs 访问点：asarPath 已在上方校验为
   本机存在的 .asar 绝对路径；root 前缀比对防符号链接/重解析点逃逸） */
const onDiskUnpacked = new Set();
try {
  for (const rel of fs.readdirSync(unpackedDir, { recursive: true })) {
    const abs = path.resolve(unpackedDir, rel);
    if (!abs.startsWith(path.resolve(unpackedDir) + path.sep)) continue;
    onDiskUnpacked.add(rel.split('\\').join('/'));
  }
} catch (e) { /* 目录不存在 → 所有 unpacked 条目均视为悬空 */ }
const staleList = diffStaleEntries(header, onDiskUnpacked);
/* --resolve 模式只输出纯文件名一行：调用方（apply-patch.ps1）直接取整行结果，
   任何额外输出（尤其中文在 GBK 控制台的乱码）都会污染捕获 */
if (resolveMode) {
  const dir = getNode(header, args[2].split('/'));
  const prefix = args[3];
  const hits = dir && dir.files ? Object.keys(dir.files).filter(n => n.startsWith(prefix) && n.endsWith('.js')) : [];
  if (hits.length !== 1) die(`--resolve: ${args[2]} prefix ${prefix} hit ${hits.length} files (expect 1)`);
  console.log(hits[0]);
  fs.closeSync(fd);
  process.exit(0);
}
console.log(`[patch-inplace] 头部 ${headerSize} B，悬空 unpacked 条目 ${staleList.length} 个`);
if (statOnly) { fs.closeSync(fd); process.exit(0); }

/* index.html 旧内容与插入点 */
const targetDir = getNode(header, rendererDir.split('/'));
const indexEntry = targetDir.files[indexName];
if (!indexEntry || indexEntry.files || indexEntry.unpacked) die(`${rendererDir}/${indexName} 不是归档内文件`);
const oldIndexAbs = dataStart + Number(indexEntry.offset);
const oldIndexHtml = Buffer.alloc(indexEntry.size);
fs.readSync(fd, oldIndexHtml, 0, indexEntry.size, oldIndexAbs);
let html = oldIndexHtml.toString('utf8');
if (html.includes(injectName)) die(`${indexName} 已包含 ${injectName} 引用`);
const bundleRe = new RegExp('(<script type="module" crossorigin src="\\./assets/' + (bundleName || 'index') + '-[^"]+\\.js"></script>)');
if (!bundleRe.test(html)) die(`${indexName} 中未找到主 bundle <script> 标签（前缀 ${bundleName || 'index'}）`);
html = html.replace(bundleRe, `<script src="./${injectName}"></script>$1`);
const newIndexHtml = Buffer.from(html, 'utf8');
const injectBuf = fs.readFileSync(injectSrc);

/* ── 可选：对归档内另一文件做正则替换 + 末尾追加（如 OpenCode 主进程 wp:// 桥） ── */
let alsoEntryBuf = null;
if (alsoPatch) {
  const alsoNode = getNode(header, alsoPatch.relPath.split('/'));
  if (!alsoNode || alsoNode.files || alsoNode.unpacked) {
    die(`--also-patch：归档中未找到可补丁文件 ${alsoPatch.relPath}`);
  }
  const alsoAbs = dataStart + Number(alsoNode.offset);
  const alsoOrig = Buffer.alloc(alsoNode.size);
  fs.readSync(fd, alsoOrig, 0, alsoNode.size, alsoAbs);
  let text = alsoOrig.toString('utf8');
  const findSrc = fs.readFileSync(alsoPatch.findFile, 'utf8').trim();
  const replaceText = fs.readFileSync(alsoPatch.replaceFile, 'utf8');
  const hits = text.match(new RegExp(findSrc, 'g'));
  if (!hits || hits.length !== 1) {
    die(`--also-patch：${alsoPatch.relPath} 中定位到 ${hits ? hits.length : 0} 处（预期恰好 1 处），中止`);
  }
  text = text.replace(new RegExp(findSrc), () => replaceText);
  const appendText = fs.readFileSync(alsoPatch.appendFile, 'utf8');
  text += '\n' + appendText;
  alsoEntryBuf = { node: alsoNode, buf: Buffer.from(text, 'utf8') };
  console.log(`[patch-inplace] --also-patch：${alsoPatch.relPath} 替换 1 处 + 追加 ${appendText.length} B`);
}

/* 末尾追加区：index.html 新副本 + 注入脚本（各自 8 字节对齐），偏移相对数据区 */
const align8 = (base) => base + ((8 - (base % 8)) % 8);
const dataIndexBase = archiveSize - dataStart;
const newIndexRel = align8(dataIndexBase);
const injectRel = align8(newIndexRel + newIndexHtml.length);
const tailParts = [
  Buffer.alloc(newIndexRel - dataIndexBase),
  newIndexHtml,
  Buffer.alloc(injectRel - newIndexRel - newIndexHtml.length),
  injectBuf,
];
let cursorRel = injectRel + injectBuf.length;
if (alsoEntryBuf) {
  const alsoRel = align8(cursorRel);
  tailParts.push(Buffer.alloc(alsoRel - cursorRel), alsoEntryBuf.buf);
  alsoEntryBuf.node.size = alsoEntryBuf.buf.length;
  alsoEntryBuf.node.offset = String(alsoRel);
  alsoEntryBuf.node.integrity = integrityOf(alsoEntryBuf.buf);
  cursorRel = alsoRel + alsoEntryBuf.buf.length;
}
const tail = Buffer.concat(tailParts);

/* 更新树：删悬空条目、加注入脚本条目、更新 index.html 条目 */
removeStale(header, staleList);
targetDir.files[injectName] = { size: injectBuf.length, offset: String(injectRel), integrity: integrityOf(injectBuf) };
indexEntry.size = newIndexHtml.length;
indexEntry.offset = String(newIndexRel);
indexEntry.integrity = integrityOf(newIndexHtml);

let newJson = JSON.stringify(header);
/* 头部长度以 UTF-8 字节计（文件名含中文等多字节字符），补齐到与原头部完全等长 */
const oldBytes = Buffer.byteLength(oldJson, 'utf8');
const newBytes = Buffer.byteLength(newJson, 'utf8');
const padded = newBytes <= oldBytes;
if (padded) newJson += ' '.repeat(oldBytes - newBytes);
console.log(`[patch-inplace] 新头部 JSON ${newBytes} B（原 ${oldBytes} B，悬空条目已移除）→ ${padded ? '原地改写头部' : '流式重写'}`);

const newHeaderBuf = headerPickle(newJson);
if (padded && newHeaderBuf.length !== headerBuf.length) {
  die(`头部 pickle 长度不符（${newHeaderBuf.length} != ${headerBuf.length}）`);
}
/* --out 模式：临时文件写到调用方指定路径（如 %TEMP%），MSIX 包目录内新建文件会被系统拒绝 */
const tmpPath = outPath || (asarPath + '.zwp-tmp');
let newFileSize;
if (padded) {
  fs.copyFileSync(asarPath, tmpPath);
  const out = fs.openSync(tmpPath, 'r+');
  fs.writeSync(out, newHeaderBuf, 0, newHeaderBuf.length, 8);
  fs.closeSync(out);
  fs.appendFileSync(tmpPath, tail);
  newFileSize = archiveSize + tail.length;
} else {
  const sizeBuf = Buffer.alloc(8);
  sizeBuf.writeUInt32LE(4, 0);
  sizeBuf.writeUInt32LE(newHeaderBuf.length, 4);
  const out = fs.openSync(tmpPath, 'w');
  fs.writeSync(out, sizeBuf);
  fs.writeSync(out, newHeaderBuf);
  const src = fs.openSync(asarPath, 'r');
  const chunk = Buffer.alloc(8 * 1024 * 1024);
  let pos = dataStart;
  while (pos < archiveSize) {
    const n = fs.readSync(src, chunk, 0, chunk.length, pos);
    if (n <= 0) break;
    fs.writeSync(out, chunk, 0, n);
    pos += n;
  }
  fs.closeSync(src);
  fs.writeSync(out, tail);
  fs.closeSync(out);
  newFileSize = 8 + newHeaderBuf.length + (archiveSize - dataStart) + tail.length;
}

/* ── 全量自校验：重新解析临时文件，逐文件重算 SHA256 ── */
console.log('[patch-inplace] 自校验（逐文件 SHA256）...');
{
  const vfd = fs.openSync(tmpPath, 'r');
  const vSize = fs.fstatSync(vfd).size;
  if (vSize !== newFileSize) die(`临时文件大小不符（${vSize} != ${newFileSize}）`);
  const v = readHeader(vfd);
  const vDataStart = 8 + v.headerSize;
  let checked = 0, unpackedCount = 0;
  const buf = Buffer.alloc(0);
  (function verify(node, rel) {
    for (const [name, child] of Object.entries(node.files)) {
      const childRel = rel ? rel + '/' + name : name;
      if (child.files) { verify(child, childRel); continue; }
      if (child.unpacked) { unpackedCount++; continue; }
      if (vDataStart + Number(child.offset) + child.size > vSize) die(`校验失败：${childRel} 越界`);
      const content = child.size > 0 ? Buffer.alloc(child.size) : buf;
      if (child.size > 0) fs.readSync(vfd, content, 0, child.size, vDataStart + Number(child.offset));
      if (integrityOf(content).hash !== child.integrity.hash) die(`校验失败：${childRel} 哈希不符`);
      checked++;
    }
  })(v.header, '');
  fs.closeSync(vfd);
  const patchedIndex = getNode(v.header, rendererDir.split('/')).files[indexName];
  const idxBuf = Buffer.alloc(patchedIndex.size);
  {
    const vfd2 = fs.openSync(tmpPath, 'r');
    fs.readSync(vfd2, idxBuf, 0, patchedIndex.size, vDataStart + Number(patchedIndex.offset));
    fs.closeSync(vfd2);
  }
  if (!idxBuf.toString('utf8').includes(`<script src="./${injectName}">`)) die('校验失败：index.html 未包含注入引用');
  if (!getNode(v.header, rendererDir.split('/')).files[injectName]) die('校验失败：注入脚本条目缺失');
  console.log(`[patch-inplace] 校验通过：${checked} 个归档内文件哈希一致（unpacked 引用 ${unpackedCount} 个）`);
}

fs.closeSync(fd);
if (outPath) {
  /* --out 模式：产物留在指定路径，由调用方覆写原 asar（包目录内无法新建/改名文件） */
  console.log(`[patch-inplace] OK：补丁产物已写出 ${outPath}（原文件由调用方覆写）`);
} else {
  fs.renameSync(tmpPath, asarPath);
  console.log(`[patch-inplace] OK：${asarPath} 已打补丁`);
}

/* ── 可选：同步更新主程序内嵌的 asar 头部哈希 ── */
if (exePath) {
  const newHeaderHash = crypto.createHash('SHA256').update(Buffer.from(newJson, 'utf8')).digest('hex');
  if (newHeaderHash === oldHeaderHash) die('内部错误：新头部哈希与旧值相同');
  const exeBuf = fs.readFileSync(exePath);
  const oldHex = Buffer.from(oldHeaderHash, 'latin1');
  let count = 0, idx = -1;
  while ((idx = exeBuf.indexOf(oldHex, idx + 1, 'latin1')) !== -1) {
    exeBuf.write(newHeaderHash, idx, 'latin1');
    count++;
  }
  if (count === 0) {
    die(`主程序 ${exePath} 中未找到旧头部哈希——它可能未启用头部完整性校验（无害），或已更新过。请人工确认后去掉 --exe 参数重试。`);
  }
  const exeTmp = exePath + '.zwp-tmp';
  fs.writeFileSync(exeTmp, exeBuf);
  fs.renameSync(exeTmp, exePath);
  console.log(`[patch-inplace] OK：${exePath} 已更新内嵌头部哈希（${count} 处）→ ${newHeaderHash.slice(0, 16)}…`);
}
