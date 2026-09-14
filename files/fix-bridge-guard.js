// fix-bridge-guard.js — 在已打补丁的 asar 里原位中和 isProtocolHandled 守卫（等长替换）
const fs = require('fs');
const P = 'C:\\Users\\FVAEP\\CodexPatched\\app\\resources\\app.asar';
const FROM = "if (mod.protocol.isProtocolHandled('wp')) return;";
const TO = "if(0&&mod.protocolisProtocolHandled('wp'))return;";
if (FROM.length !== TO.length) { console.error('length mismatch: ' + FROM.length + ' vs ' + TO.length); process.exit(1); }
const buf = fs.readFileSync(P);
const idx = buf.indexOf(Buffer.from(FROM, 'latin1'));
if (idx < 0) { console.error('guard not found (already fixed?)'); process.exit(0); }
Buffer.from(TO, 'latin1').copy(buf, idx);
fs.writeFileSync(P, buf);
console.log('fixed at offset ' + idx + ' (' + FROM.length + ' bytes, in-place)');
