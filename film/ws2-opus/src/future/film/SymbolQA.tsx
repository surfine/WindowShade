// 符號驗收台：現況（手畫）與新版（真 SF Symbols）並排，同一個名目尺寸、同一條中線，
// 量的是「換了來源有沒有變大一號／變細」。下面再單獨放大畫一次真符號，
// 用來跟 SF Symbols.app 裡的官方圖目視比對（同一個圖形、同樣筆畫）。
//
// 這裡的 Old* 是改動前 `glyphs.tsx` 的原樣拷貝，只為了對照，不參與片子。
import { AbsoluteFill } from 'remotion';
import { Check, FaceGlyph, IPhone, Lock, Sym, XMark } from '../glyphs';
import { clamp01, mix } from '../time';
import { SYMBOLS, type SymName } from '../symbols';

type P = { size: number; color?: string };

// ── 改動前的原樣（對照組） ───────────────────────────────────────────────
function OldFaceGlyph({ size, scan, ok, sweep }: { size: number; scan: number; ok: number; sweep: number }) {
  const C = 50, ticks = 56;
  const green = '#30D158';
  const ink = ok > 0.02 ? green : '#fff';
  const corner = (rot: number) => (
    <path key={rot} d="M 22 8 H 16 A 8 8 0 0 0 8 16 V 22" fill="none" stroke={ink} strokeWidth={3.2} strokeLinecap="round" transform={`rotate(${rot} 50 50) translate(${-ok * 3} ${-ok * 3})`} />
  );
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" style={{ overflow: 'visible' }}>
      {Array.from({ length: ticks }, (_, i) => {
        const a = (i / ticks) * Math.PI * 2 - Math.PI / 2;
        const u = i / ticks;
        const lag = ((sweep - u) % 1 + 1) % 1;
        const lit = clamp01(scan) > u ? 0.42 + 0.58 * Math.max(0, 1 - lag * 3.2) : 0.12;
        const done = clamp01(ok * 2.2 - u * 0.6);
        const r0 = 62 + done * 2, r1 = mix(71, 76, done) + (lag < 0.08 && ok < 0.01 ? 4 : 0);
        return <line key={i} x1={C + Math.cos(a) * r0} y1={C + Math.sin(a) * r0} x2={C + Math.cos(a) * r1} y2={C + Math.sin(a) * r1} stroke={done > 0.01 ? green : '#fff'} strokeOpacity={Math.max(lit, done)} strokeWidth={2.6} strokeLinecap="round" />;
      })}
      {[0, 90, 180, 270].map(corner)}
      <path d="M 33 51 L 45 63 L 68 38" fill="none" stroke={green} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - clamp01((ok - 0.35) / 0.55)} />
    </svg>
  );
}
const OldIPhone = ({ size, color = '#fff' }: P) => (
  <svg width={size * 0.56} height={size} viewBox="0 0 14 25">
    <rect x={1} y={1} width={12} height={23} rx={3.2} fill="none" stroke={color} strokeWidth={1.6} />
    <rect x={5.1} y={2.8} width={3.8} height={1.3} rx={0.65} fill={color} />
  </svg>
);
const OldLock = ({ size, color = '#fff', open = 0 }: P & { open?: number }) => (
  <svg width={size} height={size} viewBox="0 0 20 20">
    <path d={`M 6 9 V 6.4 A 4 4 0 0 1 14 6.4 V ${mix(9, 6.6, open)}`} transform={`translate(${open * 5.2} 0)`} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
    <rect x={3.6} y={8.6} width={12.8} height={9.4} rx={2.4} fill={color} />
  </svg>
);
const OldCheck = ({ size, color = '#30D158', draw = 1, ring = true }: P & { draw?: number; ring?: boolean }) => (
  <svg width={size} height={size} viewBox="0 0 30 30">
    {ring && <circle cx={15} cy={15} r={13.5} fill={color} />}
    <path d="M 8.6 15.6 L 13 20 L 21.6 10.6" fill="none" stroke={ring ? '#000' : color} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - clamp01(draw)} />
  </svg>
);
const OldXMark = ({ size, color = '#8e8e93' }: P) => (
  <svg width={size} height={size} viewBox="0 0 30 30">
    <circle cx={15} cy={15} r={13.5} fill={color} />
    <path d="M 10.2 10.2 L 19.8 19.8 M 19.8 10.2 L 10.2 19.8" stroke="#000" strokeWidth={2.8} strokeLinecap="round" />
  </svg>
);

// ── 版面 ────────────────────────────────────────────────────────────────
const CELL = 240;
const INK = 46; // 片中 Unlock 那一格的 `size`
const CYAN = 'rgba(80,220,255,.9)';

function Half({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={{ width: CELL, height: CELL, position: 'relative', flex: 'none' }}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{children}</div>
      {/* 名目外框 + 中線：換來源之後尺寸有沒有跑掉，看這兩條就知道 */}
      <div style={{ position: 'absolute', left: CELL / 2 - INK / 2, top: CELL / 2 - INK / 2, width: INK, height: INK, border: `1px dashed ${CYAN}` }} />
      <div style={{ position: 'absolute', left: CELL / 2 - 0.5, top: 0, width: 1, height: CELL, background: CYAN }} />
      <div style={{ position: 'absolute', left: 0, top: CELL / 2 - 0.5, width: CELL, height: 1, background: CYAN }} />
      <div style={{ position: 'absolute', left: 0, bottom: 4, right: 0, textAlign: 'center', color: '#9aa3ad', fontSize: 12 }}>{label}</div>
    </div>
  );
}

const ROWS: { group: string; old: React.ReactNode; nu: React.ReactNode }[] = [
  { group: 'faceid 掃描中（Unlock size=46）', old: <OldFaceGlyph size={INK} scan={1} ok={0} sweep={0} />, nu: <FaceGlyph size={INK} scan={1} ok={0} /> },
  { group: 'faceid 認出來（Unlock size=46）', old: <OldFaceGlyph size={INK} scan={1} ok={1} sweep={0} />, nu: <FaceGlyph size={INK} scan={1} ok={1} /> },
  { group: 'iphone（Unlock size=30）', old: <OldIPhone size={30} />, nu: <IPhone size={30} /> },
  { group: 'lock 關（size=20）', old: <OldLock size={20} />, nu: <Lock size={20} /> },
  { group: 'lock 開（size=20）', old: <OldLock size={20} open={1} />, nu: <Lock size={20} open={1} /> },
  { group: 'check（size=34）', old: <OldCheck size={34} />, nu: <Check size={34} /> },
  { group: 'check ring=false（size=34）', old: <OldCheck size={34} ring={false} />, nu: <Check size={34} ring={false} /> },
  { group: 'xmark（size=32）', old: <OldXMark size={32} />, nu: <XMark size={32} /> },
];

/** 真符號單獨放大：跟 SF Symbols.app 的官方圖目視比對用。 */
const LARGE: SymName[] = ['faceid', 'iphone', 'lock.fill', 'checkmark', 'checkmark.circle.fill', 'xmark.circle.fill'];

export function SymbolQA() {
  return (
    <AbsoluteFill style={{ background: '#12141a', fontFamily: 'ui-sans-serif, system-ui', flexDirection: 'column' }}>
      <div style={{ height: 56, flex: 'none', display: 'flex', alignItems: 'center', gap: 40, padding: '0 20px', color: '#fff', fontSize: 15, borderBottom: '1px solid rgba(255,255,255,.22)' }}>
        <span style={{ width: 260, color: '#9aa3ad', fontSize: 13 }}>左＝現況（手畫）　右＝新版（真 SF Symbols）</span>
        <span style={{ color: '#9aa3ad', fontSize: 13 }}>青色虛線＝該符號的 `size × size` 名目框；十字是它的中心；`size` 與片中呼叫點相同</span>
      </div>
      {ROWS.map((r, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', height: CELL, flex: 'none', borderBottom: '1px solid rgba(255,255,255,.1)' }}>
          <div style={{ width: 300, color: '#c9d1d9', fontSize: 14, paddingLeft: 20 }}>{r.group}</div>
          <Half label="現況">{r.old}</Half>
          <Half label="新版">{r.nu}</Half>
        </div>
      ))}
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 34, padding: '22px 30px 10px', borderTop: '1px solid rgba(255,255,255,.22)' }}>
        {LARGE.map((n) => (
          <div key={n} style={{ textAlign: 'center', color: '#c9d1d9', fontSize: 13 }}>
            <Sym name={n} size={190} />
            <div style={{ marginTop: 8 }}>{n}</div>
            <div style={{ color: '#7d8792' }}>{SYMBOLS[n].viewBox.split(' ').slice(2).join('×')} units</div>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
}
