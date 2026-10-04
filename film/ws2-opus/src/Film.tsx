import { AbsoluteFill, useCurrentFrame } from 'remotion';
import type { Layout, Rect } from './layout';
import { CAPTION_IN, CAPTION_OUT } from './motion/direction';
import { NOTCH, TEACH_TUCKED, clamp01, seg } from './motion/site';
import { CAPTIONS, FADE_TO_BLACK, MUSIC_PLAY, SEGMENTS, WORDMARK_AT } from './timeline';
import {
  DRAFT, DRAGGED_APP, DRAG_PRESS, HANDLE_POS, ICON_SIZE, deviceAt, dragIconAt, fingerAt, handleAt, phoneAt, pointerAt,
  screenDark, slotsAt, trackpadAt,
} from './scene';
import { Laptop } from './parts/Laptop';
import { Island } from './parts/Island';
import { Placeholder } from './parts/Placeholder';
import { AppIcon, ChatWin, DraftWin, HomeScreen, MenuBar, MusicWin, NotesWin, TermWin, WALL } from './parts/Mock';

const CJK = '"Source Han Sans SC","Noto Sans SC","PingFang SC",sans-serif';
const LATIN = 'Inter, "Helvetica Neue", sans-serif';

/** drawn：画出来的界面（B 版）；否则是写着要录什么的占位块。两版共用同一条时间线。 */
export function Film({ L, drawn }: { L: Layout; drawn: boolean }) {
  const frame = useCurrentFrame();
  const cqw = L.screen.w / 100;

  const page = drawn ? (
    <>
      <div style={{ position: 'absolute', inset: 0, background: WALL }} />
      <DrawnDesk frame={frame} L={L} />
      <Handle frame={frame} L={L} />
      <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: screenDark(frame) }} />
    </>
  ) : (
    <>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(160deg,#252a34 0%,#161920 55%,#101217 100%)' }} />
      {slotsAt(frame).map((s) => <Placeholder key={s.id} L={L} slot={s} />)}
      <Handle frame={frame} L={L} />
      <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: screenDark(frame) }} />
    </>
  );
  const over = (
    <>
      <Island frame={frame} cqw={cqw} drawn={drawn} />
      {drawn ? <Arrow frame={frame} L={L} /> : <Pointer frame={frame} L={L} />}
    </>
  );

  return (
    <AbsoluteFill style={{ background: '#0a0b0e', overflow: 'hidden' }}>
      <Laptop L={L} frame={frame} page={page} over={over} />
      <Trackpad frame={frame} L={L} />
      <Phone frame={frame} L={L} />
      {drawn && <Device frame={frame} L={L} />}
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

/** 画出来的桌面：菜单栏、后面那扇草稿，再按占位块的位置和运动画对应的窗口。 */
function DrawnDesk({ frame, L }: { frame: number; L: Layout }) {
  const cqw = L.screen.w / 100;
  const box = (rect: Rect) => ({ rect, cqw, sw: L.screen.w, sh: L.screen.h });
  const slots = slotsAt(frame);
  const side = slots.filter((s) => s.id === 'P6' || s.id === 'P7');
  const sideOpacity = Math.max(0, ...side.map((s) => s.opacity));
  const icon = dragIconAt(frame);
  return (
    <>
      <MenuBar cqw={cqw} h={NOTCH.h} />
      <DraftWin box={box(DRAFT)} />
      {slots.map((s) => {
        const b = box(s.rect);
        switch (s.id) {
          case 'P1': return <MusicWin key={s.id} box={b} opacity={s.opacity} playing={frame >= MUSIC_PLAY} />;
          case 'P4': return <TermWin key={s.id} box={b} opacity={s.opacity} scale={s.scale} radius={s.radius} />;
          case 'P5': return <HomeScreen key={s.id} cqw={cqw} sw={L.screen.w} sh={L.screen.h} opacity={s.opacity} hide={frame >= DRAG_PRESS ? DRAGGED_APP : undefined} />;
          case 'P8': return <ChatWin key={s.id} box={b} opacity={s.opacity} scale={s.scale} radius={s.radius} />;
          default: return null;
        }
      })}
      {side.length > 0 && <NotesWin box={box(side[0].rect)} opacity={sideOpacity} />}
      {icon && (
        <div style={{ position: 'absolute', left: (icon.x / 100) * L.screen.w, top: (icon.y / 100) * L.screen.h, transform: 'translate(-50%,-50%) scale(1.06)' }}>
          <AppIcon k={DRAGGED_APP} cqw={cqw} size={ICON_SIZE} />
        </div>
      )}
    </>
  );
}

/** 画出来的那一版用箭头指针，尖端在 (x, y)。 */
function Arrow({ frame, L }: { frame: number; L: Layout }) {
  const p = pointerAt(frame);
  if (!p) return null;
  const s = L.screen.w * 0.022;
  return (
    <svg style={{ position: 'absolute', left: (p.x / 100) * L.screen.w, top: (p.y / 100) * L.screen.h, opacity: p.opacity, overflow: 'visible', transform: `scale(${1 - 0.1 * p.pressed})`, transformOrigin: '0 0' }} width={s} height={s} viewBox="0 0 20 20">
      <path d="M1 1 L1 15.5 L4.8 12 L7.4 18 L10 16.9 L7.5 11 L12.6 11 Z" fill="#000" stroke="#fff" strokeWidth={1.3} strokeLinejoin="round" />
    </svg>
  );
}

/** 屏外的实物线稿：一对耳机、一只鼠标。连上的那一刻线变亮。 */
function Device({ frame, L }: { frame: number; L: Layout }) {
  const d = deviceAt(frame);
  if (!d) return null;
  const size = Math.min(L.side.w, L.side.h) * 0.7;
  const stroke = `rgba(255,255,255,${0.35 + 0.55 * d.on})`;
  return (
    <svg style={{ position: 'absolute', left: L.side.x + (L.side.w - size) / 2, top: L.side.y + (L.side.h - size) / 2, opacity: d.opacity }} width={size} height={size} viewBox="0 0 100 100" fill="none" stroke={stroke} strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
      {d.kind === 'pods'
        ? <g><path d="M30 30 a10 10 0 1 1 0 20 l0 28" /><path d="M70 30 a10 10 0 1 0 0 20 l0 28" /></g>
        : <g><rect x={34} y={18} width={32} height={64} rx={16} /><line x1={50} y1={24} x2={50} y2={36} /></g>}
    </svg>
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
