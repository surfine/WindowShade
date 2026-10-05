import type { ReactNode } from 'react';
import { LID_DEGREES, foldSeries, lidPlay, shadeFold } from '../motion/site';
import { dolly } from '../motion/direction';
import { DOLLY_AT, LID_PLAYS } from '../timeline';
import { AIR, type Layout } from '../layout';

// 开盖只在第一段。之后盖子不动。
const LID_FRAMES = 900;
const lidAt = (f: number) => Math.max(0, ...LID_PLAYS.map((s) => lidPlay(f, s)));
const FOLD = foldSeries(LID_FRAMES, lidAt);

/**
 * 15 英寸 MacBook Air 的正面轮廓，数字见 layout.ts 的 AIR（量自 Apple 官方 Product Bezels）。
 * 透视沿用 site/style.css：2400px，按盖子占 88% 的 780px 机身算。
 */
export function Laptop({ L, frame, page, over }: { L: Layout; frame: number; page: ReactNode; over: ReactNode }) {
  const { x, y, w, h } = L.screen;
  const q = w / AIR.glassW;
  const pad = AIR.bezel * q;
  const lidW = w + 2 * pad, lidH = pad + h + AIR.chin * q;
  const baseW = AIR.baseW * q, baseH = AIR.baseH * q, deckH = AIR.deckH * q;
  const footH = AIR.footH * q;
  const k = lidW / 0.88 / 780;
  const boxH = lidH + baseH + footH;
  const lx = x - pad - (baseW - lidW) / 2, ly = y - pad;

  const lid = frame < LID_FRAMES ? lidAt(frame) : 0;
  const amount = frame < LID_FRAMES ? FOLD[frame] : 0;
  const fold = amount > 0 ? shadeFold(amount, w, h) : null;
  const s = L.far + (1 - L.far) * dolly(frame, DOLLY_AT);
  const cx = x + w / 2, cy = y + h / 2;

  return (
    <div style={{ position: 'absolute', inset: 0, transformOrigin: `${cx}px ${cy}px`, transform: `scale(${s})` }}>
      <div style={{ position: 'absolute', left: lx, top: ly, width: baseW, height: boxH, perspective: 2400 * k, perspectiveOrigin: '50% -30%' }}>
        {[0, 1].map((i) => (
          <div
            key={i}
            style={{
              position: 'absolute', top: lidH + baseH, width: AIR.footW * q, height: footH,
              left: i ? baseW - (AIR.footInset + AIR.footW) * q : AIR.footInset * q,
              borderRadius: `0 0 ${footH}px ${footH}px`, background: '#4a4b4f',
            }}
          />
        ))}
        <div
          style={{
            position: 'absolute', left: 0, top: lidH, width: baseW, height: baseH, overflow: 'hidden',
            borderRadius: `${4 * q}px ${4 * q}px ${AIR.baseBottomR * q}px ${AIR.baseBottomR * q}px`,
            background: `linear-gradient(#e2e3e6 0, #d3d5d9 ${deckH}px, #85878b ${deckH}px, #9b9da1 ${deckH + (baseH - deckH) * 0.35}px, #c8cacd 100%)`,
            boxShadow: `0 ${22 * k}px ${40 * k}px ${-14 * k}px rgba(0,0,0,.9)`,
          }}
        >
          <div
            style={{
              position: 'absolute', left: (baseW - AIR.scoopW * q) / 2, top: 0, width: AIR.scoopW * q, height: deckH,
              borderRadius: `0 0 ${deckH * 0.6}px ${deckH * 0.6}px`, background: 'linear-gradient(#eceef0,#f2f3f5)',
            }}
          />
        </div>
        <div
          style={{
            position: 'absolute', left: (baseW - lidW) / 2, top: 0, width: lidW, height: lidH,
            transformOrigin: '50% 100%', transform: `rotateX(${lid * LID_DEGREES}deg)`,
            background: `linear-gradient(#0b0b0d 0, #0b0b0d ${pad + h + AIR.chinGlass * q}px, #242527 ${pad + h + AIR.chinGlass * q}px, #101011 100%)`,
            borderRadius: `${AIR.lidR * q}px ${AIR.lidR * q}px ${AIR.lidBottomR * q}px ${AIR.lidBottomR * q}px`,
            boxShadow: `inset 0 0 0 ${AIR.rim * q}px #7f8185`,
          }}
        >
          <div style={{ position: 'absolute', left: pad, top: pad, width: w, height: h, overflow: 'hidden', borderRadius: `${AIR.glassR * q}px ${AIR.glassR * q}px 0 0`, background: '#050506' }}>
            <div style={{ position: 'absolute', inset: 0, transformOrigin: '0 0', transform: fold?.matrix ?? 'none' }}>{page}</div>
            {fold && (
              <>
                {[
                  { blur: fold.blurTop / 3, mask: 'linear-gradient(to top,transparent,#000 20%)' },
                  { blur: (fold.blurTop * 2) / 3, mask: 'linear-gradient(to top,transparent 15%,#000 50%)' },
                  { blur: fold.blurTop, mask: 'linear-gradient(to top,transparent 45%,#000 85%)' },
                ].map((d, i) => (
                  <div key={i} style={{ position: 'absolute', inset: 0, filter: `blur(${d.blur}px)`, WebkitMaskImage: d.mask, maskImage: d.mask }}>
                    <div style={{ position: 'absolute', inset: 0, transformOrigin: '0 0', transform: fold.matrix }}>{page}</div>
                  </div>
                ))}
                <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(to top, rgb(0 0 0 / ${fold.shadeHinge}), rgb(0 0 0 / ${fold.shadeTop}))` }} />
              </>
            )}
            {over}
            <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(115deg,rgba(255,255,255,.07) 0%,transparent 38%)', pointerEvents: 'none' }} />
          </div>
        </div>
      </div>
    </div>
  );
}
