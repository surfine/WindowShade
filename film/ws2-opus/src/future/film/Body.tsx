// 一台 MacBook 的实体：CSS 3D。底座是同一块圆角板一层层叠出厚度；盖子从转轴往上，后仰 23°。
// 屏幕内容是平的 DOM，跟着盖子一起透视。
import type { CSSProperties, ReactNode } from 'react';
import { LEAN, type Machine } from './machines';

const SLICES = 12;
const mixc = (a: number, b: number, t: number) => Math.round(a + (b - a) * t);

export function Body({ M, U, at, screen, led, glow = 0.5 }: { M: Machine; U: number; at: [number, number, number]; screen: ReactNode; led: boolean; glow?: number }) {
  const W = M.w * U, D = M.depth * U, T = M.thick * U, L = M.lidLen * U;
  const p3: CSSProperties = { position: 'absolute', transformStyle: 'preserve-3d' };
  const g = M.glass, s = M.screen, c = M.color;
  const baseR = `${0.5 * U}px ${0.5 * U}px ${1.3 * U}px ${1.3 * U}px`;
  const ledX = M.notch ? W / 2 + 0.55 * U : W / 2 + 0.47 * U;
  return (
    <div style={{ ...p3, left: 0, top: 0, transform: `translate3d(${at[0] * U}px, ${at[1] * U}px, ${at[2] * U}px)` }}>
      <div style={{ ...p3, left: -W * 0.62, top: T, width: W * 1.24, height: D * 1.3, transformOrigin: '50% 0', transform: `rotateX(90deg) translateY(${-D * 0.12}px)`, background: 'radial-gradient(50% 46% at 50% 50%, rgba(0,0,0,.55), rgba(0,0,0,.22) 60%, rgba(0,0,0,0) 100%)', filter: `blur(${(0.6 * U).toFixed(1)}px)` }} />
      {Array.from({ length: SLICES }, (_, i) => {
        const k = (SLICES - i) / SLICES;
        const [r, gg, b] = c.edge;
        return <div key={i} style={{ ...p3, left: -W / 2, top: k * T, width: W, height: D, transformOrigin: '50% 0', transform: 'rotateX(90deg)', borderRadius: baseR, background: `rgb(${mixc(r, r * 0.6, k)},${mixc(gg, gg * 0.6, k)},${mixc(b, b * 0.6, k)})` }} />;
      })}
      <div style={{ ...p3, left: -W / 2, top: 0, width: W, height: D, transformOrigin: '50% 0', transform: 'rotateX(90deg)', borderRadius: baseR, background: `linear-gradient(180deg,${c.deck[0]} 0%,${c.deck[1]} 100%)`, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.18)' }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: `radial-gradient(70% 60% at 50% 0%, rgba(120,160,255,${0.2 * glow}), rgba(0,0,0,0) 70%)` }} />
        <Keyboard M={M} U={U} />
        <div style={{ position: 'absolute', left: (W - M.pad.w * U) / 2, top: M.pad.from * U, width: M.pad.w * U, height: M.pad.depth * U, borderRadius: 0.55 * U, background: `linear-gradient(180deg,${c.pad[0]},${c.pad[1]})`, boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.12), inset 0 1px 0 rgba(255,255,255,.18)' }} />
      </div>
      <div style={{ ...p3, left: -W / 2, top: -L, width: W, height: L, transformOrigin: '50% 100%', transform: `rotateX(${LEAN}deg)`, borderRadius: `${M.lidR * U}px ${M.lidR * U}px ${0.2 * U}px ${0.2 * U}px`, background: `linear-gradient(180deg,${c.lid[0]},${c.lid[1]})`, boxShadow: '0 0 0 1px rgba(0,0,0,.25)' }}>
        <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: (M.lidLen - g.to) * U, width: g.w * U, height: (g.to - g.from) * U, borderRadius: `${Math.max(0, M.lidR - 0.1) * U}px ${Math.max(0, M.lidR - 0.1) * U}px 2px 2px`, background: '#060607' }} />
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: g.from * U, borderRadius: `0 0 ${0.2 * U}px ${0.2 * U}px`, background: 'linear-gradient(180deg,#2a2b2e,#4b4d51 70%,#5a5c60)' }} />
        <div style={{ position: 'absolute', left: (W - s.w * U) / 2, top: (M.lidLen - s.from - s.h) * U, width: s.w * U, height: s.h * U, borderRadius: `${s.r * U}px ${s.r * U}px 0 0`, overflow: 'hidden', background: '#000' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, width: M.pt.w, height: M.pt.h, transformOrigin: '0 0', transform: `scale(${(s.w * U) / M.pt.w})` }}>{screen}</div>
        </div>
        <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: (M.lidLen - g.to) * U, width: g.w * U, height: (g.to - g.from) * U, background: 'linear-gradient(115deg, rgba(255,255,255,0) 30%, rgba(255,255,255,.04) 42%, rgba(255,255,255,0) 54%)', pointerEvents: 'none' }} />
        {/* 摄像头：Neo 在边框里，Air 在刘海里（刘海本身是屏幕上的黑） */}
        <div style={{ position: 'absolute', left: W / 2 - 0.13 * U, top: (M.lidLen - M.camAt) * U - 0.13 * U, width: 0.26 * U, height: 0.26 * U, borderRadius: '50%', background: 'radial-gradient(circle at 38% 36%, #3a4a66 0%, #12161e 45%, #050507 70%)' }} />
        <div style={{ position: 'absolute', left: ledX, top: (M.lidLen - M.camAt) * U - 0.05 * U, width: 0.1 * U, height: 0.1 * U, borderRadius: '50%', background: led ? '#3dff6e' : '#0b0b0c', boxShadow: led ? `0 0 ${0.25 * U}px rgba(61,255,110,.8)` : 'none' }} />
      </div>
    </div>
  );
}

const ROWS: number[][] = [
  [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
  [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1.8, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.7],
  [2.3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.2],
  [1, 1, 1, 1.25, 5.2, 1.25, 1, 1, 1],
];

function Keyboard({ M, U }: { M: Machine; U: number }) {
  const w = M.well, c = M.color;
  const pitch = 1.88 * U, gap = 0.17 * U;
  const rowH = (i: number) => (i === 0 ? 0.95 : 1.62) * U;
  const kbW = 14.5 * pitch;
  return (
    <div style={{ position: 'absolute', left: (M.w * U - w.w * U) / 2, top: w.from * U, width: w.w * U, height: w.depth * U, borderRadius: 0.5 * U, background: `linear-gradient(180deg,${c.well[0]},${c.well[1]})`, boxShadow: 'inset 0 1px 3px rgba(0,0,0,.25)' }}>
      <div style={{ position: 'absolute', left: (w.w * U - kbW) / 2, top: 0.35 * U, width: kbW, display: 'flex', flexDirection: 'column', gap }}>
        {ROWS.map((row, i) => (
          <div key={i} style={{ display: 'flex', gap, height: rowH(i) - gap }}>
            {row.map((k, j) => <div key={j} style={{ flex: `${k} 0 0`, minWidth: 0, borderRadius: 0.22 * U, background: `linear-gradient(180deg,${c.keys[0]},${c.keys[1]})`, boxShadow: '0 1px 0 rgba(255,255,255,.14), inset 0 0.5px 0 rgba(255,255,255,.08)' }} />)}
          </div>
        ))}
      </div>
    </div>
  );
}
