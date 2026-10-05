// MacBook Neo 实体：CSS 3D 搭出来，盖子按实物后仰 23°，镜头在上方略偏一侧往下看。
// 屏幕内容是平的 DOM，跟着盖子一起透视，所以文字、图标都在同一个面上。
import type { ReactNode } from 'react';
import { LEAN, NEO, NPT } from './geom';

/** 镜头：elev 俯角、yaw 侧转（度），dolly 往前推多少像素，focus 是要对准的点（cm，模型坐标）。 */
export type Cam = { elev: number; yaw: number; dolly: number; focus: [number, number, number] };

const rad = (d: number) => (d * Math.PI) / 180;
const mix = (a: number, b: number, t: number) => Math.round(a + (b - a) * t);
const SLICES = 14;
const baseR = (U: number) => `${0.5 * U}px ${0.5 * U}px ${1.3 * U}px ${1.3 * U}px`;

/** 盖子上离转轴 s 厘米、离中线 x 厘米的点（模型坐标，y 向下，z 朝镜头）。 */
export function lidPoint(s: number, x = 0): [number, number, number] {
  return [x, -s * Math.cos(rad(LEAN)), -s * Math.sin(rad(LEAN))];
}

/** 屏幕上的点（点坐标）换成模型坐标。 */
export function screenPoint(px: number, py: number): [number, number, number] {
  const { screen } = NEO;
  return lidPoint(screen.from + ((NPT.h - py) / NPT.h) * screen.h, (px / NPT.w - 0.5) * screen.w);
}

export function Neo({ cam, U, persp, screen, camOn = false, glow = 0.5 }: { cam: Cam; U: number; persp: number; screen: ReactNode; camOn?: boolean; glow?: number }) {
  const W = NEO.w * U, D = NEO.depth * U, T = NEO.thick * U, L = NEO.lidLen * U;
  const [fx, fy, fz] = cam.focus.map((v) => v * U);
  const world = `translateZ(${cam.dolly}px) rotateX(${-cam.elev}deg) rotateY(${cam.yaw}deg) translate3d(${-fx}px, ${-fy}px, ${-fz}px)`;
  const p3: React.CSSProperties = { position: 'absolute', transformStyle: 'preserve-3d' };
  const g = NEO.glass, s = NEO.screen;
  const camS = (s.from + s.h + g.to) / 2;
  return (
    <div style={{ position: 'absolute', inset: 0, perspective: persp, perspectiveOrigin: '50% 50%' }}>
      <div style={{ ...p3, left: '50%', top: '50%', width: 0, height: 0, transform: world }}>
        {/* 桌面上的影子 */}
        <div style={{ ...p3, left: -W * 0.62, top: T, width: W * 1.24, height: D * 1.3, transformOrigin: '50% 0', transform: `rotateX(90deg) translateY(${-D * 0.12}px)`, background: 'radial-gradient(50% 46% at 50% 50%, rgba(0,0,0,.55), rgba(0,0,0,.22) 60%, rgba(0,0,0,0) 100%)', filter: `blur(${0.6 * U}px)` }} />
        {/* 底座：同一块圆角板一层层往下叠出厚度，圆角处不会露缝 */}
        {Array.from({ length: SLICES }, (_, i) => {
          const k = (SLICES - i) / SLICES;
          return <div key={i} style={{ ...p3, left: -W / 2, top: k * T, width: W, height: D, transformOrigin: '50% 0', transform: 'rotateX(90deg)', borderRadius: baseR(U), background: `rgb(${mix(196, 120, k)},${mix(198, 123, k)},${mix(202, 128, k)})` }} />;
        })}
        <div style={{ ...p3, left: -W / 2, top: 0, width: W, height: D, transformOrigin: '50% 0', transform: 'rotateX(90deg)', borderRadius: baseR(U), background: 'linear-gradient(180deg,#b9bcc1 0%,#d3d5d9 30%,#dfe1e4 100%)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.35)' }}>
          {/* 屏幕的光落在键盘上 */}
          <div style={{ position: 'absolute', inset: 0, borderRadius: 'inherit', background: `radial-gradient(70% 60% at 50% 0%, rgba(120,160,255,${0.22 * glow}), rgba(0,0,0,0) 70%)` }} />
          <Keyboard U={U} />
          <div style={{ position: 'absolute', left: (W - NEO.pad.w * U) / 2, top: NEO.pad.from * U, width: NEO.pad.w * U, height: NEO.pad.depth * U, borderRadius: 0.55 * U, background: 'linear-gradient(180deg,#ccced2,#d6d8db)', boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.10), inset 0 1px 0 rgba(255,255,255,.4)' }} />
        </div>
        {/* 盖子：从转轴往上，后仰 */}
        <div style={{ ...p3, left: -W / 2, top: -L, width: W, height: L, transformOrigin: '50% 100%', transform: `rotateX(${LEAN}deg)`, borderRadius: `${NEO.lidR * U}px ${NEO.lidR * U}px ${0.2 * U}px ${0.2 * U}px`, background: 'linear-gradient(180deg,#a4a7ac,#878a8f)', boxShadow: '0 0 0 1px rgba(0,0,0,.25)' }}>
          {/* 黑玻璃 */}
          <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: (NEO.lidLen - g.to) * U, width: g.w * U, height: (g.to - g.from) * U, borderRadius: `${(NEO.lidR - 0.2) * U}px ${(NEO.lidR - 0.2) * U}px 2px 2px`, background: '#060607' }} />
          {/* 转轴那一截 */}
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: g.from * U, borderRadius: `0 0 ${0.2 * U}px ${0.2 * U}px`, background: 'linear-gradient(180deg,#2a2b2e,#4b4d51 70%,#6a6c70)' }} />
          {/* 显示区 */}
          <div style={{ position: 'absolute', left: (W - s.w * U) / 2, top: (NEO.lidLen - s.from - s.h) * U, width: s.w * U, height: s.h * U, borderRadius: `${NEO.screenR * U}px ${NEO.screenR * U}px 0 0`, overflow: 'hidden', background: '#000' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, width: NPT.w, height: NPT.h, transformOrigin: '0 0', transform: `scale(${(s.w * U) / NPT.w})` }}>{screen}</div>
          </div>
          {/* 玻璃反光：很淡的一道斜光 */}
          <div style={{ position: 'absolute', left: (W - g.w * U) / 2, top: (NEO.lidLen - g.to) * U, width: g.w * U, height: (g.to - g.from) * U, borderRadius: `${(NEO.lidR - 0.2) * U}px ${(NEO.lidR - 0.2) * U}px 2px 2px`, background: 'linear-gradient(115deg, rgba(255,255,255,0) 30%, rgba(255,255,255,.045) 42%, rgba(255,255,255,0) 54%)', pointerEvents: 'none' }} />
          {/* 摄像头和旁边的指示灯：在边框里，不在屏幕上 */}
          <div style={{ position: 'absolute', left: W / 2 - 0.13 * U, top: (NEO.lidLen - camS) * U - 0.13 * U, width: 0.26 * U, height: 0.26 * U, borderRadius: '50%', background: 'radial-gradient(circle at 38% 36%, #3a4a66 0%, #12161e 45%, #050507 70%)', boxShadow: '0 0 0 1px rgba(255,255,255,.05)' }} />
          <div style={{ position: 'absolute', left: W / 2 + 0.42 * U, top: (NEO.lidLen - camS) * U - 0.05 * U, width: 0.1 * U, height: 0.1 * U, borderRadius: '50%', background: camOn ? '#3dff6e' : '#0b0b0c', boxShadow: camOn ? `0 0 ${0.25 * U}px rgba(61,255,110,.8)` : 'none' }} />
        </div>
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

function Keyboard({ U }: { U: number }) {
  const w = NEO.well;
  const pitch = 1.88 * U, gap = 0.17 * U;
  const rowH = (i: number) => (i === 0 ? 0.95 : 1.62) * U;
  const kbW = 14.5 * pitch;
  return (
    <div style={{ position: 'absolute', left: (NEO.w * U - w.w * U) / 2, top: w.from * U, width: w.w * U, height: w.depth * U, borderRadius: 0.5 * U, background: 'linear-gradient(180deg,#a7aaaf,#b6b9bd)', boxShadow: 'inset 0 1px 3px rgba(0,0,0,.25)' }}>
      <div style={{ position: 'absolute', left: (w.w * U - kbW) / 2, top: 0.35 * U, width: kbW, display: 'flex', flexDirection: 'column', gap }}>
        {ROWS.map((row, i) => {
          const sum = row.reduce((a, b) => a + b, 0);
          return (
            <div key={i} style={{ display: 'flex', gap, height: rowH(i) - gap }}>
              {row.map((k, j) => (
                <div key={j} style={{ flex: `${k} 0 0`, minWidth: 0, borderRadius: 0.22 * U, background: 'linear-gradient(180deg,#2b2b2e,#1d1d20)', boxShadow: '0 1px 0 rgba(255,255,255,.18), inset 0 0.5px 0 rgba(255,255,255,.08)', maxWidth: (k / sum) * kbW }} />
              ))}
            </div>
          );
        })}
      </div>
    </div>
  );
}
