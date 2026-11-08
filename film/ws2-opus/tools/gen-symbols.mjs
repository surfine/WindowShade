// 把 macOS 上的真 SF Symbol 抽成 `src/future/symbols.ts`。
//
// 為什麼要這一步：專案裡的符號本來全是手寫 SVG（`glyphs.tsx` 的 `FaceGlyph` 是
// 56 根刻度繞一圈的轉盤），不是 Apple 的符號。這裡用
// `NSImage(systemSymbolName:)` → 私類別 `NSSymbolImageRep.vectorGlyph.CGPath`
// 取出 Apple 自己那份向量外框（不是點陣：`cgImage(forProposedRect:)` 與 `draw(in:)`
// 都會烤成點陣，PDF 內容流裡是 `/Im1 Do` 一張圖，所以不能用），
// 寫成 TS 常數內嵌，4K（`--scale=2`）也不會糊。
//
// 用法：node tools/gen-symbols.mjs
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');

// 要哪幾顆、用哪個字重。島上與解鎖那兩格都用 semibold：跟旁邊的標題字重同級。
const WEIGHT = 'semibold';
const PT = 160;

// name → 給人看的出處註解
const WANT = [
  ['faceid', '刷臉中：iOS 島上解鎖顯示的就是這一顆'],
  ['checkmark', '認出來之後換成這顆（真機是 faceid → checkmark）'],
  ['iphone', '旁邊那台手機，跟 faceid 並排站'],
  ['lock.fill', '關著的鎖'],
  ['lock.open.fill', '開著的鎖：跟 lock.fill 疊在同一個 viewBox 上交叉淡入，鎖扣繞鎖體轉'],
  ['checkmark.circle.fill', '實心圓勾（島上的「好了／已收進劉海」）'],
  ['xmark.circle.fill', '實心圓叉（島上的「已取消」）'],
];

mkdirSync(resolve(ROOT, 'tools/.symbol-cache'), { recursive: true });

const rows = [];
for (const [name] of WANT) {
  const out = resolve(ROOT, 'tools/.symbol-cache', `${name}.svg`);
  const stdout = execFileSync('swift', [resolve(HERE, 'extract-symbol.swift'), name, WEIGHT, String(PT), '100', out], { encoding: 'utf8' });
  const tab = stdout.indexOf('\t');
  const box = JSON.parse(stdout.slice(0, tab));
  const d = stdout.slice(tab + 1).trim();
  if (!d) throw new Error(`${name}: 抽不到 path`);
  rows.push({ name, ...box, d });
  process.stderr.write(`  ${name}: ${box.w}×${box.h} units, path ${d.length} 字元\n`);
}

// lock.fill 與 lock.open.fill 疊在同一個座標框：用兩者的聯集，
// 交叉淡入時鎖體才不會因為各自正規化而忽大忽小。
const lockF = rows.find((r) => r.name === 'lock.fill');
const lockO = rows.find((r) => r.name === 'lock.open.fill');
const lockFrame = {
  minX: Math.min(lockF.minX, lockO.minX),
  minY: Math.min(lockF.minY, lockO.minY),
  maxX: Math.max(lockF.minX + lockF.w, lockO.minX + lockO.w),
  maxY: Math.max(lockF.minY + lockF.h, lockO.minY + lockO.h),
};
lockFrame.w = lockFrame.maxX - lockFrame.minX;
lockFrame.h = lockFrame.maxY - lockFrame.minY;

const fmt = (v) => String(Math.round(v * 100) / 100);
const sym = (r) => `{\n    viewBox: '${fmt(r.minX)} ${fmt(r.minY)} ${fmt(r.w)} ${fmt(r.h)}',\n    d: '${r.d}',\n  }`;

const out = `// 這個檔案是產物，不要手改。來源：macOS 系統的 SF Symbols。
//
// 生成指令：node tools/gen-symbols.mjs        （腳本：tools/extract-symbol.swift）
// 抽取路徑：NSImage(systemSymbolName:) → NSSymbolImageRep.vectorGlyph.CGPath
//   —— Apple 自己那份向量外框。不是點陣：cgImage(forProposedRect:) 與 draw(in:)
//   都會把符號烤成點陣（PDF 內容流裡是 /Im1 Do 一張圖），4K 母帶會軟，所以沒走那條。
// 字型／來源檔：系統私有 framework SFSymbols.framework 的 CoreGlyphs.bundle/Assets.car
//   （AssetType = "Vector Glyph"，名稱就叫 faceid / iphone / lock.fill …），
//   由 macOS 的符號服務在執行期供應；抽取時字重 ${WEIGHT}、名目點數 ${PT}pt。
//
// 座標：抽取點數 ${PT} 時 CGPath 的 2 單位 = 1 pt（量過四顆符號是 1.99–2.00），
// 所以 \`size\` 用「點數」的語意、縮放是 \`size / ${PT * 2}\`。

export type SymName = ${WANT.map(([n]) => `'${n}'`).join(' | ')};

type Sym = { viewBox: string; d: string };

/** 每顆符號的墨跡框（viewBox）與向量外框。 */
export const SYMBOLS: Record<SymName, Sym> = {
${rows.map((r) => `  '${r.name}': ${sym(r)},`).join('\n')}
};

/** 鎖的兩態共用同一個框，交叉淡入時鎖體不會跳。 */
export const LOCK_FRAME = '${fmt(lockFrame.minX)} ${fmt(lockFrame.minY)} ${fmt(lockFrame.w)} ${fmt(lockFrame.h)}';
`;

writeFileSync(resolve(ROOT, 'src/future/symbols.ts'), out);
// 順手把來源清單寫出來，方便回報與日後複查
writeFileSync(
  resolve(ROOT, 'tools/.symbol-cache/sources.json'),
  JSON.stringify({ weight: WEIGHT, pointSize: PT, source: '/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/Assets.car', api: 'NSImage(systemSymbolName:) → NSSymbolImageRep.vectorGlyph.CGPath', symbols: WANT.map(([n, why]) => ({ name: n, why })), lockFrame }, null, 2),
);
console.log(`寫出 src/future/symbols.ts（${rows.length} 顆符號）`);
