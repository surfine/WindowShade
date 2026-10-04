import type { ReactNode } from 'react';
import { AIR, type Layout } from '../layout';

/**
 * [B 站版] 开头、结尾的整机：盖子开到约 110°，镜头略高往下看 14°，看得见键盘面。
 * 屏幕、边框、转轴前那截的尺寸和 Laptop 一样取自 AIR；键盘面深度按 15 英寸 Air 的 23.76 cm 机身减去盖子算。
 * 摆法：转轴（盖子下沿）在 Laptop 里同一个位置，盖子往后仰、键盘面往镜头这边平躺，两块共用一个透视。
 */
const LID_OPEN = 110;
const ELEVATION = 14;
/** 键盘面深度 / 盖子高度（机身 237.6 mm、盖子约 224 mm 含转轴）。 */
const DECK_RATIO = 1.02;

export function Hero({ L, page, over }: { L: Layout; page: ReactNode; over: ReactNode }) {
  const { x, y, w, h } = L.screen;
  const q = w / AIR.glassW;
  const pad = AIR.bezel * q;
  const lidW = w + 2 * pad, lidH = pad + h + AIR.chin * q;
  const baseW = AIR.baseW * q * 0.9;
  const deckD = lidH * DECK_RATIO;
  const hingeY = y - pad + lidH;
  const cx = x + w / 2;
  const k = lidW / 0.88 / 780;
  const lidTilt = LID_OPEN - 90 - ELEVATION;
  const deckTilt = 90 - ELEVATION;
  const kb = { w: baseW * 0.8, top: deckD * 0.06, h: deckD * 0.42 };
  const pad2 = { w: baseW * 0.4, top: deckD * 0.55, h: deckD * 0.33 };

  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: L.width, height: L.height, perspective: 2400 * k, perspectiveOrigin: `${cx}px ${hingeY - lidH * 1.4}px` }}>
      {/* 桌面上的影子 */}
      <div style={{ position: 'absolute', left: cx - baseW * 0.62, top: hingeY - deckD * 0.05, width: baseW * 1.24, height: deckD * 1.15, transformOrigin: '50% 0', transform: `rotateX(${deckTilt}deg)`, background: 'radial-gradient(closest-side, rgba(0,0,0,.55), rgba(0,0,0,0))' }} />
      {/* 键盘面：银色铝，黑色键位一块，前面是触控板，最前沿一道开盖凹口 */}
      <div
        style={{
          position: 'absolute', left: cx - baseW / 2, top: hingeY, width: baseW, height: deckD, transformOrigin: '50% 0', transform: `rotateX(${deckTilt}deg)`,
          borderRadius: `${AIR.baseBottomR * q * 0.6}px ${AIR.baseBottomR * q * 0.6}px ${AIR.baseBottomR * q * 2}px ${AIR.baseBottomR * q * 2}px`,
          background: 'linear-gradient(#c9ccd1, #dfe1e5 40%, #d2d4d8)',
          boxShadow: `inset 0 0 0 ${2 * k}px rgba(255,255,255,.55), inset 0 ${-6 * k}px ${10 * k}px rgba(0,0,0,.12)`,
        }}
      >
        <div
          style={{
            position: 'absolute', left: (baseW - kb.w) / 2, top: kb.top, width: kb.w, height: kb.h, borderRadius: 6 * k,
            background: '#16171a',
            backgroundImage: `repeating-linear-gradient(90deg, transparent 0 ${kb.w / 14.5 - 1.3 * k}px, #c9ccd1 ${kb.w / 14.5 - 1.3 * k}px ${kb.w / 14.5}px), repeating-linear-gradient(0deg, transparent 0 ${kb.h / 6 - 1.3 * k}px, #c9ccd1 ${kb.h / 6 - 1.3 * k}px ${kb.h / 6}px)`,
          }}
        />
        <div style={{ position: 'absolute', left: (baseW - pad2.w) / 2, top: pad2.top, width: pad2.w, height: pad2.h, borderRadius: 8 * k, background: 'linear-gradient(#d6d8dc,#cdd0d4)', boxShadow: `inset 0 0 0 ${1.5 * k}px rgba(0,0,0,.1)` }} />
        <div style={{ position: 'absolute', left: (baseW - AIR.scoopW * q) / 2, bottom: 0, width: AIR.scoopW * q, height: 5 * k, borderRadius: `${5 * k}px ${5 * k}px 0 0`, background: 'rgba(0,0,0,.18)' }} />
      </div>
      {/* 盖子：和 Laptop 同一套边框，往后仰 */}
      <div
        style={{
          position: 'absolute', left: cx - lidW / 2, top: hingeY - lidH, width: lidW, height: lidH, transformOrigin: '50% 100%', transform: `rotateX(${lidTilt}deg)`,
          background: `linear-gradient(#0b0b0d 0, #0b0b0d ${pad + h + AIR.chinGlass * q}px, #242527 ${pad + h + AIR.chinGlass * q}px, #101011 100%)`,
          borderRadius: `${AIR.lidR * q}px ${AIR.lidR * q}px ${AIR.lidBottomR * q}px ${AIR.lidBottomR * q}px`,
          boxShadow: `inset 0 0 0 ${AIR.rim * q}px #7f8185, 0 ${30 * k}px ${60 * k}px rgba(0,0,0,.35)`,
        }}
      >
        <div style={{ position: 'absolute', left: pad, top: pad, width: w, height: h, overflow: 'hidden', borderRadius: `${AIR.glassR * q}px ${AIR.glassR * q}px 0 0`, background: '#050506' }}>
          {page}
          {over}
          <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(115deg,rgba(255,255,255,.07) 0%,transparent 38%)' }} />
        </div>
      </div>
    </div>
  );
}
