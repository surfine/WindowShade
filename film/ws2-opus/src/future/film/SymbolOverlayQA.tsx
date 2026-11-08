// 符號疊圖驗收台的「我們的另一半」：把本專案生產用的 `<Sym>`（真 SF Symbol 向量）
// 畫成 512×512 的白字黑底，跟 AppKit 官方那份（`out/future/symbols/official-*.png`）
// 拿去像素比對。用 Remotion 畫，跟片子走同一條渲染路，不再自己寫光柵器。
//
// 每一顆符號畫兩格：
//   上：官方（staticFile 的 PNG，已經裁到墨跡框）
//   下：我們的 `<Sym>`（size 給 512，它自己會依長寬比填高）
// 版面固定 512×1024，之後由 `tools/overlay-symbols.mjs` 逐格裁開比對。
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from 'remotion';
import { Sym } from '../glyphs';
import type { SymName } from '../symbols';

const BOX = 512;

export const OVERLAY_SYMBOLS: SymName[] = [
  'faceid', 'checkmark', 'checkmark.circle.fill', 'xmark.circle.fill', 'iphone', 'lock.fill', 'lock.open.fill',
];

function Cell({ children }: { children: React.ReactNode }) {
  // 兩格都用白底黑字：官方 PNG 是「透明底、黑字」，白底才看得到；
  // 我們的 `Sym` 也跟著用黑，這樣兩邊的遮罩判準一致（暗＝墨跡）。
  return (
    <div style={{ width: BOX, height: BOX, position: 'relative', background: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      {children}
    </div>
  );
}

export function SymbolOverlayQA() {
  const name = OVERLAY_SYMBOLS[useCurrentFrame()];
  return (
    <AbsoluteFill style={{ background: '#fff', flexDirection: 'column' }}>
      <Cell>
        <Img src={staticFile(`sym-official/${name}.png`)} style={{ maxWidth: BOX, maxHeight: BOX, objectFit: 'contain' }} />
      </Cell>
      <Cell>
        <Sym name={name} size={480} color="#000" />
      </Cell>
    </AbsoluteFill>
  );
}
