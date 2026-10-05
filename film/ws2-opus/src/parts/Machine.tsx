// 15 吋 MacBook Air，銀色。尺寸來自 Apple 的 AR 模型
// /tmp/gg/usdz/measured.json（macbook-air-15in-silver.usdz），鍵帽來自同一套量測的 keys。
// 蓋子後仰 lid_lean_deg 19.992（開合 109.992°），鏡頭再略俯，不當成一塊豎著的板。
import type { ReactNode } from 'react';
import { KEYS_AIR } from '../future/film/measured';
import type { Layout } from '../layout';
import { fingerAt } from '../scene';

/** 厘米。出處：measured.json → air。 */
const SCREEN_W = 32.573;
const BASE_W = 33.95;
const BASE_D = 23.756;
const BASE_R = 1.033;
const LID_W = 33.95;
const LID_LEN = 21.831 - -1.929;
const LID_R = 1.046;
const GLASS_W = 33.635;
const GLASS_TOP = 21.831 - 21.678;
const GLASS_SIDE = (LID_W - GLASS_W) / 2;
const ACTIVE_TOP = 21.678 - 21.142;
const BEZEL_X = (GLASS_W - SCREEN_W) / 2;
const CHIN = 1.145;
const HINGE_W = 23.785;
const HINGE_D = 0.268;
const WELL_W = 27.878;
const WELL_FROM = -9.69 + 11.878;
const WELL_D = 1.81 - -9.69;
const WELL_R = 0.455;
const PAD_W = 14.869;
const PAD_FROM = 2.059 + 11.878;
const PAD_D = 11.377 - 2.059;
const PAD_R = 0.458;
const LEAN = 19.992;
const LOOK = 12;

const SILVER = {
  lid: 'linear-gradient(#c9ccd2, #b4b8be 55%, #9ea3aa)',
  deck: 'linear-gradient(#eceef1, #d5d8dc 80%, #c2c5cb)',
  chin: 'linear-gradient(#3a3c40, #6d7076 40%, #b7bac0)',
  well: '#c4c7cc',
  key: 'linear-gradient(#3a3c42, #1c1e22)',
  pad: 'linear-gradient(#f2f3f5, #dfe1e5)',
};

export function Machine({ L, page, over, frame }: { L: Layout; page: ReactNode; over: ReactNode; frame: number }) {
  const { x, y, w, h } = L.screen;
  const U = w / SCREEN_W;
  const px = (cm: number) => cm * U;
  const notchX = x + w / 2;
  const notchY = y;
  const lidLeft = notchX - px(LID_W) / 2;
  const lidTop = y - px(GLASS_TOP + ACTIVE_TOP);
  const hingeY = y + h + px(CHIN);
  const baseLeft = notchX - px(BASE_W) / 2;
  const finger = fingerAt(frame);

  return (
    <div style={{ position: 'absolute', inset: 0, perspective: px(52), perspectiveOrigin: `${notchX}px ${notchY}px` }}>
      <div style={{ position: 'absolute', inset: 0, transformStyle: 'preserve-3d', transformOrigin: `${notchX}px ${notchY}px`, transform: `rotateX(${LOOK}deg)` }}>
        <div
          style={{
            position: 'absolute', left: baseLeft, top: hingeY, width: px(BASE_W), height: px(BASE_D),
            transformOrigin: '50% 0', transform: 'rotateX(78deg)', transformStyle: 'preserve-3d',
            borderRadius: px(BASE_R), background: SILVER.deck,
            boxShadow: `0 ${px(0.4)}px ${px(1.2)}px rgba(0,0,0,.45)`,
          }}
        >
          <div style={{ position: 'absolute', left: (px(BASE_W) - px(WELL_W)) / 2, top: px(WELL_FROM), width: px(WELL_W), height: px(WELL_D), borderRadius: px(WELL_R), background: SILVER.well }} />
          {KEYS_AIR.map((key, i) => {
            const [kx, kz, kw, kd, , kind, kr] = key;
            if (kind === 'bump') return null;
            return (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  left: px(BASE_W) / 2 + px(kx),
                  top: px(kz),
                  width: px(kw),
                  height: px(kd),
                  borderRadius: px(kr),
                  background: SILVER.key,
                  boxShadow: '0 1px 0 rgba(255,255,255,.2), inset 0 -1px 0 rgba(0,0,0,.35)',
                }}
              />
            );
          })}
          <div style={{ position: 'absolute', left: (px(BASE_W) - px(PAD_W)) / 2, top: px(PAD_FROM), width: px(PAD_W), height: px(PAD_D), borderRadius: px(PAD_R), background: SILVER.pad, boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.08)' }}>
            {finger && finger.trail.length > 1 && (
              <svg width="100%" height="100%" style={{ position: 'absolute', inset: 0, overflow: 'visible' }}>
                <polyline
                  points={finger.trail.map((p) => `${(p.x / 100) * px(PAD_W)},${(p.y / 100) * px(PAD_D)}`).join(' ')}
                  fill="none" stroke="rgba(10,132,255,.55)" strokeWidth={px(0.35)} strokeLinecap="round" opacity={finger.opacity}
                />
              </svg>
            )}
            {finger && (
              <div style={{ position: 'absolute', left: `${finger.x}%`, top: `${finger.y}%`, width: px(1.1), height: px(1.1), marginLeft: px(-0.55), marginTop: px(-0.55), borderRadius: '50%', background: finger.down ? 'rgba(10,132,255,.55)' : 'rgba(40,44,52,.2)', border: '1px solid rgba(255,255,255,.7)', opacity: finger.opacity }} />
            )}
          </div>
          <div style={{ position: 'absolute', left: (px(BASE_W) - px(HINGE_W)) / 2, top: -px(HINGE_D) / 2, width: px(HINGE_W), height: px(HINGE_D), borderRadius: px(HINGE_D), background: '#6a6d72' }} />
        </div>
        <div
          style={{
            position: 'absolute', left: lidLeft, top: lidTop, width: px(LID_W), height: px(LID_LEN),
            transformOrigin: `${notchX - lidLeft}px ${notchY - lidTop}px`,
            transform: `rotateX(${LEAN}deg)`,
            borderRadius: `${px(LID_R)}px ${px(LID_R)}px ${px(0.35)}px ${px(0.35)}px`,
            background: SILVER.lid,
            boxShadow: 'inset 0 0 0 1px rgba(0,0,0,.18)',
          }}
        >
          <div style={{ position: 'absolute', left: px(GLASS_SIDE), top: px(GLASS_TOP), width: px(GLASS_W), height: px(21.678 - -0.51), borderRadius: `${px(0.89)}px ${px(0.89)}px 0 0`, background: '#070708' }} />
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: px(CHIN), background: SILVER.chin }} />
          <div style={{ position: 'absolute', left: px(GLASS_SIDE + BEZEL_X), top: px(GLASS_TOP + ACTIVE_TOP), width: w, height: h, overflow: 'hidden', borderRadius: `${px(0.377)}px ${px(0.377)}px 0 0`, background: '#000' }}>
            {page}
            {over}
          </div>
        </div>
      </div>
    </div>
  );
}
