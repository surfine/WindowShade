import type { ReactNode } from 'react';
import { LID_DEGREES, foldSeries, lidPlay, shadeFold } from '../motion/site';
import { dolly } from '../motion/direction';
import { DOLLY_AT, LID_PLAYS } from '../timeline';
import type { Layout } from '../layout';

// 开盖只在第一段。之后盖子不动。
const LID_FRAMES = 900;
const lidAt = (f: number) => Math.max(0, ...LID_PLAYS.map((s) => lidPlay(f, s)));
const FOLD = foldSeries(LID_FRAMES, lidAt);

/** site/style.css 的 MacBook：盖子占 88%，边框 1.8% / 2.6%，玻璃 16:10，透视 2400px（按 780px 宽）。 */
export function Laptop({ L, frame, page, over }: { L: Layout; frame: number; page: ReactNode; over: ReactNode }) {
  const { x, y, w, h } = L.screen;
  const lidW = w / 0.964;
  const pad = 0.018 * lidW, padBottom = 0.026 * lidW;
  const laptopW = lidW / 0.88;
  const k = laptopW / 780;
  const lidH = pad + h + padBottom;
  const deckH = 18 * k; // clamp(10px, 2.2vw, 18px) 在桌面宽度下取到 18px
  const boxH = lidH + deckH;
  const lx = x - pad - (laptopW - lidW) / 2, ly = y - pad;

  const lid = frame < LID_FRAMES ? lidAt(frame) : 0;
  const amount = frame < LID_FRAMES ? FOLD[frame] : 0;
  const fold = amount > 0 ? shadeFold(amount, w, h) : null;
  const s = L.far + (1 - L.far) * dolly(frame, DOLLY_AT);
  const cx = x + w / 2, cy = y + h / 2;

  return (
    <div style={{ position: 'absolute', inset: 0, transformOrigin: `${cx}px ${cy}px`, transform: `scale(${s})` }}>
      <div style={{ position: 'absolute', left: lx, top: ly, width: laptopW, height: boxH, perspective: 2400 * k, perspectiveOrigin: '50% -30%' }}>
        <div
          style={{
            position: 'absolute', left: (laptopW - lidW) / 2, top: 0, width: lidW, height: lidH,
            transformOrigin: '50% 100%', transform: `rotateX(${lid * LID_DEGREES}deg)`,
            background: '#0b0b0d', borderRadius: `${22 * k}px ${22 * k}px ${8 * k}px ${8 * k}px`,
            boxShadow: `inset 0 0 0 ${1.5 * k}px #26272b, 0 0 0 ${k}px #45474d, 0 ${-k}px 0 ${k}px #1b1c1f`,
          }}
        >
          <div style={{ position: 'absolute', left: pad, top: pad, width: w, height: h, overflow: 'hidden', borderRadius: `${10 * k}px ${10 * k}px ${3 * k}px ${3 * k}px`, background: '#050506' }}>
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
        <div
          style={{
            position: 'absolute', left: 0, top: lidH, width: laptopW, height: deckH,
            borderRadius: `${3 * k}px ${3 * k}px 40% 40% / ${3 * k}px ${3 * k}px 100% 100%`,
            background: 'linear-gradient(#e4e6ea 0%,#c3c6cc 45%,#8e9299 100%)',
            boxShadow: `0 ${22 * k}px ${40 * k}px ${-14 * k}px rgba(0,0,0,.9)`,
          }}
        />
      </div>
    </div>
  );
}
