// 一台 MacBook 的实体：CSS 3D。尺寸、圆角、键位、触控板都来自 machines.ts（USDZ 量测）。
// 盖子绕转轴后仰 lean（约 20°，开合约 110°），不是立成 90°。
// 摄像头左右位置没有量到：画在上边框 / 刘海的中线上，亮的时候就是那一颗灯。
import type { CSSProperties, ReactNode } from 'react';
import { CJK, SF } from '../glyphs';
import type { KeyCap } from './measured';
import type { Machine } from './machines';

const SLICES = 12;
const mixc = (a: number, b: number, t: number) => Math.round(a + (b - a) * t);

export function Body({ M, U, at, screen, led, glow = 0.5 }: { M: Machine; U: number; at: [number, number, number]; screen: ReactNode; led: boolean; glow?: number }) {
  const W = M.w * U, D = M.depth * U, T = M.thick * U, L = M.lidLen * U;
  const p3: CSSProperties = { position: 'absolute', transformStyle: 'preserve-3d' };
  const g = M.glass, s = M.screen, c = M.color;
  const baseR = `${M.corner * U}px`;
  const lidTop = (M.lidLen - g.to) * U;
  return (
    <div style={{ ...p3, left: 0, top: 0, transform: `translate3d(${at[0] * U}px, ${at[1] * U}px, ${at[2] * U}px)` }}>
      <div style={{ ...p3, left: -W * 0.62, top: T, width: W * 1.24, height: D * 1.3, transformOrigin: '50% 0', transform: `rotateX(90deg) translateY(${-D * 0.12}px)`, background: 'radial-gradient(50% 46% at 50% 50%, rgba(0,0,0,.55), rgba(0,0,0,.22) 60%, rgba(0,0,0,0) 100%)', filter: `blur(${(0.6 * U).toFixed(1)}px)` }} />
      {Array.from({ length: SLICES }, (_, i) => {
        const k = (SLICES - i) / SLICES;
        const [r, gg, b] = c.edge;
        return <div key={i} style={{ ...p3, left: -W / 2, top: k * T, width: W, height: D, transformOrigin: '50% 0', transform: 'rotateX(90deg)', borderRadius: baseR, background: `rgb(${mixc(r, r * 0.72, k)},${mixc(gg, gg * 0.72, k)},${mixc(b, b * 0.72, k)})` }} />;
      })}
      <div style={{ ...p3, left: -W / 2, top: 0, width: W, height: D, transformOrigin: '50% 0', transform: 'rotateX(90deg)', borderRadius: baseR, background: c.deck, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.14)' }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: `radial-gradient(70% 60% at 50% 0%, rgba(120,160,255,${0.16 * glow}), rgba(0,0,0,0) 70%)` }} />
        <Deck M={M} U={U} />
      </div>
      <div style={{ ...p3, left: -M.hinge.w * U / 2, top: -M.hinge.dia * U * 0.5, width: M.hinge.w * U, height: M.hinge.dia * U, transformOrigin: '50% 50%', transform: `translateZ(${-M.hingeFromBack * U}px) rotateX(90deg)`, borderRadius: M.hinge.dia * U, background: c.chin }} />
      <div style={{ ...p3, left: -W / 2, top: -L, width: W, height: L, transformOrigin: '50% 100%', transform: `translateZ(${-M.hingeFromBack * U}px) rotateX(${M.lean}deg)`, borderRadius: `${M.lidR * U}px ${M.lidR * U}px ${M.lidRBottom * U}px ${M.lidRBottom * U}px`, background: c.lid, boxShadow: '0 0 0 1px rgba(0,0,0,.22)' }}>
        <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: lidTop, width: g.w * U, height: (g.to - g.from) * U, borderRadius: `${g.r * U}px ${g.r * U}px 0 0`, background: '#000' }} />
        <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: (M.lidLen - g.from) * U, width: g.w * U, height: g.from * U, background: c.chin }} />
        <div style={{ position: 'absolute', left: (W - s.w * U) / 2, top: (M.lidLen - s.from - s.h) * U, width: s.w * U, height: s.h * U, borderRadius: `${s.r * U}px ${s.r * U}px 0 0`, overflow: 'hidden', background: '#000' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, width: M.pt.w, height: M.pt.h, transformOrigin: '0 0', transform: `scale(${(s.w * U) / M.pt.w})` }}>{screen}</div>
        </div>
        <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: lidTop, width: g.w * U, height: (g.to - g.from) * U, borderRadius: `${g.r * U}px ${g.r * U}px 0 0`, background: 'linear-gradient(115deg, rgba(255,255,255,0) 30%, rgba(255,255,255,.04) 42%, rgba(255,255,255,0) 54%)', pointerEvents: 'none' }} />
        {/* 灯：中线。左右位置未核验，不另画一颗偏移的点。 */}
        <div style={{ position: 'absolute', left: W / 2 - 0.11 * U, top: (M.lidLen - M.camAt) * U - 0.11 * U, width: 0.22 * U, height: 0.22 * U, borderRadius: '50%', background: led ? '#3dff6e' : 'radial-gradient(circle at 38% 36%, #3a4a66 0%, #12161e 45%, #050507 70%)', boxShadow: led ? `0 0 ${0.28 * U}px rgba(61,255,110,.85)` : 'inset 0 0 0 1px rgba(255,255,255,.12)' }} />
      </div>
    </div>
  );
}

function Deck({ M, U }: { M: Machine; U: number }) {
  const W = M.w * U, c = M.color, w = M.well, p = M.pad;
  return (
    <>
      <div style={{ position: 'absolute', left: (W - w.w * U) / 2, top: w.from * U, width: w.w * U, height: w.depth * U, borderRadius: w.r * U, background: c.well, boxShadow: 'inset 0 1px 3px rgba(0,0,0,.22)' }} />
      {M.keys.map((k, i) => <Key key={i} k={k} U={U} W={W} fill={c.keys} ink={c.legend} />)}
      <div style={{ position: 'absolute', left: (W - p.w * U) / 2, top: p.from * U, width: p.w * U, height: p.depth * U, borderRadius: p.r * U, background: c.pad, boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.14), inset 0 1px 0 rgba(255,255,255,.2)' }} />
    </>
  );
}

function Key({ k, U, W, fill, ink }: { k: KeyCap; U: number; W: number; fill: string; ink: string }) {
  const [x, z, w, h, lab, kind, r] = k;
  const bump = kind === 'bump';
  return (
    <div style={{ position: 'absolute', left: W / 2 + x * U, top: z * U, width: w * U, height: h * U, borderRadius: Math.min(r, w / 2, h / 2) * U, background: fill, boxShadow: bump ? 'inset 0 0 0 1px rgba(0,0,0,.28), 0 1px 0 rgba(255,255,255,.35)' : '0 1px 0 rgba(255,255,255,.22), inset 0 0.5px 0 rgba(255,255,255,.28)', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {lab && !bump ? <Legend lab={lab} U={U} w={w} h={h} ink={ink} /> : null}
    </div>
  );
}

function Legend({ lab, U, w, h, ink }: { lab: string; U: number; w: number; h: number; ink: string }) {
  const lines = lab.split('\n');
  const main = lines[lines.length - 1];
  const fs = Math.max(6, Math.min(U * h * 0.34, (U * w * 0.86) / Math.max(main.length, 1) / 0.62));
  const font = /[\u4e00-\u9fff]/.test(lab) ? CJK : SF;
  return (
    <div style={{ color: ink, fontFamily: font, fontWeight: 500, lineHeight: 1.05, textAlign: 'center', fontSize: fs }}>
      {lines.length > 1 && <div style={{ fontSize: fs * 0.62, opacity: 0.8 }}>{lines[0]}</div>}
      <div>{main}</div>
    </div>
  );
}
