// 15 英寸 MacBook Air 正面，尺寸照 layout.ts 的 AIR（Apple Product Bezels 实测）。
// 加了实拍该有的东西：铝的高光、盖子边缘的轮廓光、屏幕玻璃的反光、桌面上的倒影和屏幕照在桌上的光。
import type { ReactNode } from 'react';
import { Img } from 'remotion';
import { AIR, type Rect } from '../layout';
import { PLATE } from './assets';
import { PT } from './shape';

export function MacBook({ screen, glow, camOn, children }: { screen: Rect; glow: number; camOn: boolean; children: ReactNode }) {
  const { x, y, w, h } = screen;
  const q = w / AIR.glassW;
  const pad = AIR.bezel * q;
  const lidW = w + 2 * pad, lidH = pad + h + AIR.chin * q;
  const baseW = AIR.baseW * q, baseH = AIR.baseH * q, deckH = AIR.deckH * q;
  const footH = AIR.footH * q;
  const lx = x - pad, ly = y - pad;
  const bx = x + w / 2 - baseW / 2, by = ly + lidH;
  const k = w / PT.w;
  return (
    <>
      {/* 屏幕照在桌上的光 */}
      <div style={{ position: 'absolute', left: x - w * 0.35, top: by - baseH, width: w * 1.7, height: h * 0.75, background: 'radial-gradient(50% 42% at 50% 12%, rgba(120,150,255,.20), rgba(90,110,220,.06) 55%, transparent 75%)', opacity: glow, mixBlendMode: 'screen' }} />
      {/* 桌面倒影：屏幕倒过来、糊开、渐隐 */}
      <div style={{ position: 'absolute', left: x, top: by + baseH + footH, width: w, height: h * 0.45, overflow: 'hidden', opacity: 0.16 * glow, filter: 'blur(14px)', WebkitMaskImage: 'linear-gradient(#000,transparent 70%)', maskImage: 'linear-gradient(#000,transparent 70%)' }}>
        <Img src={PLATE.wall} style={{ width: w, height: w, objectFit: 'cover', transform: 'scaleY(-1)', marginTop: -w * 0.5 }} />
      </div>
      {/* 接触阴影 */}
      <div style={{ position: 'absolute', left: bx + baseW * 0.02, top: by + baseH - 6 * q * 10, width: baseW * 0.96, height: baseH * 1.4, borderRadius: '50%', background: 'rgba(0,0,0,.85)', filter: `blur(${Math.max(6, baseH * 0.5)}px)` }} />
      {/* 底座 */}
      <div
        style={{
          position: 'absolute', left: bx, top: by, width: baseW, height: baseH, overflow: 'hidden',
          borderRadius: `${4 * q}px ${4 * q}px ${AIR.baseBottomR * q}px ${AIR.baseBottomR * q}px`,
          background: `linear-gradient(#cfd1d5 0, #b9bbc0 ${deckH * 0.5}px, #a4a6ab ${deckH}px, #5e6064 ${deckH}px, #8b8d92 ${deckH + (baseH - deckH) * 0.4}px, #3b3c40 100%)`,
        }}
      >
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(90deg, rgba(0,0,0,.35), rgba(255,255,255,.18) 30%, rgba(255,255,255,.32) 50%, rgba(255,255,255,.14) 70%, rgba(0,0,0,.4))', mixBlendMode: 'overlay' }} />
        <div style={{ position: 'absolute', left: (baseW - AIR.scoopW * q) / 2, top: 0, width: AIR.scoopW * q, height: deckH * 0.9, borderRadius: `0 0 ${deckH * 0.6}px ${deckH * 0.6}px`, background: 'linear-gradient(#9c9ea3,#c3c5ca)' }} />
        <div style={{ position: 'absolute', left: 0, right: 0, top: deckH - 0.6, height: 1.2, background: 'rgba(255,255,255,.55)' }} />
      </div>
      {[0, 1].map((i) => (
        <div key={i} style={{ position: 'absolute', top: by + baseH - 1, width: AIR.footW * q, height: footH, left: bx + (i ? baseW - (AIR.footInset + AIR.footW) * q : AIR.footInset * q), borderRadius: `0 0 ${footH}px ${footH}px`, background: '#1a1a1c' }} />
      ))}
      {/* 盖子：铝边一圈 + 黑玻璃 */}
      <div
        style={{
          position: 'absolute', left: lx, top: ly, width: lidW, height: lidH,
          borderRadius: `${AIR.lidR * q}px ${AIR.lidR * q}px ${AIR.lidBottomR * q}px ${AIR.lidBottomR * q}px`,
          background: `linear-gradient(#060607 0, #060607 ${pad + h + AIR.chinGlass * q}px, #1d1e20 ${pad + h + AIR.chinGlass * q}px, #0c0c0d 100%)`,
          boxShadow: `inset 0 0 0 ${AIR.rim * q}px #6d6f74, inset 0 ${AIR.rim * q * 0.6}px 0 ${AIR.rim * q}px rgba(220,224,232,.55), 0 0 ${w * 0.02}px rgba(120,150,255,${0.12 * glow})`,
        }}
      >
        <div style={{ position: 'absolute', left: pad, top: pad, width: w, height: h, overflow: 'hidden', borderRadius: `${AIR.glassR * q}px ${AIR.glassR * q}px 0 0`, background: '#000' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, width: PT.w, height: PT.h, transformOrigin: '0 0', transform: `scale(${k})` }}>{children}</div>
          {/* 玻璃：一道斜的反光、上沿一点冷光 */}
          <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(118deg, rgba(255,255,255,.075) 0%, rgba(255,255,255,.025) 26%, transparent 42%, transparent 78%, rgba(255,255,255,.03) 100%)', pointerEvents: 'none' }} />
        </div>
        {/* 摄像头：刘海正中，屏幕上沿往上一点 */}
        <div style={{ position: 'absolute', left: lidW / 2 - 7 * q * 2, top: pad + 18 * q, width: 14 * q * 2, height: 14 * q * 2, borderRadius: '50%', background: 'radial-gradient(circle at 40% 35%, #2a3550 0, #0b0d14 45%, #000 70%)', opacity: 0.9 }} />
        {/* 摄像头在用时旁边那颗绿灯 */}
        {camOn && <div style={{ position: 'absolute', left: lidW / 2 + 22 * q, top: pad + 27 * q, width: 7 * q, height: 7 * q, borderRadius: '50%', background: '#3dff6e', boxShadow: `0 0 ${6 * q}px #3dff6e` }} />}
      </div>
    </>
  );
}
