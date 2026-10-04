import { AbsoluteFill, useCurrentFrame } from 'remotion';
import type { Layout } from './layout';
import { CAPTION_IN, CAPTION_OUT } from './motion/direction';
import { TEACH_TUCKED, clamp01, seg } from './motion/site';
import { CAPTIONS, FADE_TO_BLACK, SEGMENTS, WORDMARK_AT } from './timeline';
import { HANDLE_POS, fingerAt, handleAt, phoneAt, pointerAt, screenDark, slotsAt, trackpadAt } from './scene';
import { Laptop } from './parts/Laptop';
import { Island } from './parts/Island';
import { Placeholder } from './parts/Placeholder';

const CJK = '"Source Han Sans SC","Noto Sans SC","PingFang SC",sans-serif';
const LATIN = 'Inter, "Helvetica Neue", sans-serif';

export function Film({ L }: { L: Layout }) {
  const frame = useCurrentFrame();
  const cqw = L.screen.w / 100;

  const page = (
    <>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(160deg,#252a34 0%,#161920 55%,#101217 100%)' }} />
      {slotsAt(frame).map((s) => <Placeholder key={s.id} L={L} slot={s} />)}
      <Handle frame={frame} L={L} />
      <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: screenDark(frame) }} />
    </>
  );
  const over = (
    <>
      <Island frame={frame} cqw={cqw} />
      <Pointer frame={frame} L={L} />
    </>
  );

  return (
    <AbsoluteFill style={{ background: '#0a0b0e', overflow: 'hidden' }}>
      <Laptop L={L} frame={frame} page={page} over={over} />
      <Trackpad frame={frame} L={L} />
      <Phone frame={frame} L={L} />
      <Caption frame={frame} L={L} />
      <ConceptTag frame={frame} L={L} />
      <Wordmark frame={frame} L={L} />
      <AbsoluteFill style={{ background: '#000', opacity: seg(frame, FADE_TO_BLACK[0], FADE_TO_BLACK[1]) }} />
    </AbsoluteFill>
  );
}

function Pointer({ frame, L }: { frame: number; L: Layout }) {
  const p = pointerAt(frame);
  if (!p) return null;
  const d = L.screen.w * 0.016;
  return (
    <div
      style={{
        position: 'absolute', left: (p.x / 100) * L.screen.w - d / 2, top: (p.y / 100) * L.screen.h - d / 2, width: d, height: d,
        borderRadius: '50%', opacity: p.opacity, transform: `scale(${1 - 0.16 * p.pressed})`,
        background: `rgba(255,255,255,${0.95 - 0.25 * p.pressed})`,
        boxShadow: `0 0 0 ${Math.max(1.5, d * 0.09)}px rgba(0,0,0,.55), 0 ${d * 0.15}px ${d * 0.5}px rgba(0,0,0,.45)`,
      }}
    />
  );
}

function Handle({ frame, L }: { frame: number; L: Layout }) {
  const o = handleAt(frame);
  if (o <= 0) return null;
  const w = L.screen.w * 0.005, h = L.screen.h * 0.09;
  const x = ((TEACH_TUCKED.x + TEACH_TUCKED.w) / 100) * L.screen.w;
  return <div style={{ position: 'absolute', left: x, top: (HANDLE_POS.y / 100) * L.screen.h - h / 2, width: w, height: h, borderRadius: w, background: 'rgba(255,255,255,.6)', opacity: o }} />;
}

function Trackpad({ frame, L }: { frame: number; L: Layout }) {
  const o = trackpadAt(frame);
  if (o <= 0) return null;
  const w = L.side.w, h = w / 1.45;
  const x0 = L.side.x, y0 = L.side.y + (L.side.h - h) / 2;
  const f = fingerAt(frame);
  const at = (p: { x: number; y: number }) => ({ x: (p.x / 100) * w, y: (p.y / 100) * h });
  const r = w * 0.045;
  return (
    <svg style={{ position: 'absolute', left: x0, top: y0, opacity: o, overflow: 'visible' }} width={w} height={h}>
      <rect x={0} y={0} width={w} height={h} rx={w * 0.06} fill="none" stroke="rgba(255,255,255,.45)" strokeWidth={2} />
      {f && f.trail.length > 1 && (
        <polyline
          points={f.trail.map((p) => { const q = at(p); return `${q.x},${q.y}`; }).join(' ')}
          fill="none" stroke="rgba(26,89,184,.5)" strokeWidth={r * 0.9} strokeLinecap="round" strokeLinejoin="round" opacity={f.opacity}
        />
      )}
      {f && (() => {
        const q = at(f);
        return f.down
          ? <circle cx={q.x} cy={q.y} r={r} fill="rgba(26,89,184,.66)" opacity={f.opacity} />
          : <circle cx={q.x} cy={q.y} r={r} fill="rgba(255,255,255,.08)" stroke="rgba(255,255,255,.7)" strokeWidth={1.5} opacity={f.opacity} />;
      })()}
    </svg>
  );
}

function Phone({ frame, L }: { frame: number; L: Layout }) {
  const p = phoneAt(frame);
  if (!p) return null;
  const h = L.side.h * 0.62, w = h * 0.48;
  const cx = L.side.x + L.side.w / 2, cy = L.side.y + L.side.h / 2;
  const dx = p.away * (L.width - L.side.x + w);
  return (
    <div
      style={{
        position: 'absolute', left: cx - w / 2 + dx, top: cy - h / 2, width: w, height: h, opacity: p.opacity,
        borderRadius: w * 0.2, boxShadow: 'inset 0 0 0 2px rgba(255,255,255,.55)',
      }}
    />
  );
}

function captionOpacity(frame: number, from: number, to: number) {
  return Math.min(clamp01((frame - from) / CAPTION_IN), 1 - clamp01((frame - (to - CAPTION_OUT)) / CAPTION_OUT));
}

function Caption({ frame, L }: { frame: number; L: Layout }) {
  const c = CAPTIONS.find((k) => frame >= k.from && frame < k.to);
  if (!c) return null;
  const { cx, cy, size } = L.caption;
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: cy - size * 0.7, textAlign: 'center', fontFamily: CJK, fontSize: size, fontWeight: 600, color: '#f2f3f5', opacity: captionOpacity(frame, c.from, c.to), letterSpacing: '0.02em', lineHeight: 1.4, transform: `translateX(${cx - L.width / 2}px)` }}>
      {c.text}
    </div>
  );
}

function ConceptTag({ frame, L }: { frame: number; L: Layout }) {
  const s = SEGMENTS.find((k) => k.concept && frame >= k.concept[0] && frame < k.concept[1]);
  if (!s?.concept) return null;
  const o = captionOpacity(frame, s.concept[0], s.concept[1]);
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: L.tag.y - L.tag.size * 0.7, textAlign: L.tag.align, fontFamily: CJK, fontSize: L.tag.size, color: 'rgba(255,255,255,.5)', opacity: o, letterSpacing: '0.1em' }}>
      概念示意，还没做
    </div>
  );
}

function Wordmark({ frame, L }: { frame: number; L: Layout }) {
  if (frame < WORDMARK_AT) return null;
  const { cy, size } = L.wordmark;
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: cy - size * 0.7, textAlign: 'center', fontFamily: LATIN, fontSize: size, fontWeight: 600, color: '#f2f3f5', opacity: clamp01((frame - WORDMARK_AT) / CAPTION_IN), letterSpacing: '-0.01em' }}>
      WindowShade 2
    </div>
  );
}
