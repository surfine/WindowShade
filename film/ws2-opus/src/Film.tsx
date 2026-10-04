import type { ReactNode } from 'react';
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import type { Layout, Rect } from './layout';
import { CAPTION_IN, dolly } from './motion/direction';
import { NOTCH, TEACH_TUCKED, clamp01, seg } from './motion/site';
import { MUSIC_PLAY } from './timeline';
import { CAPTIONS, FADE_TO_BLACK, OPEN_PULL, WORDMARK_AT, captionOpacity, punchAt, srcAt } from './cut';
import {
  DRAGGED_APP, DRAG_PRESS, HANDLE_POS, ICON_SIZE, chatBackAt, deviceAt, dragIconAt, draftAt, fingerAt, handleAt, headAt, phoneAt,
  pointerAt, screenDark, slotsAt, termDoneAt, trackpadAt, zoomAt,
} from './scene';
import { Laptop } from './parts/Laptop';
import { Island } from './parts/Island';
import { Placeholder } from './parts/Placeholder';
import { AppIcon, ChatWin, DraftWin, HomeScreen, MenuBar, MusicWin, NotesWin, TermWin, WALL } from './parts/Mock';

const CJK = '"Source Han Sans SC","Noto Sans SC","PingFang SC",sans-serif';
const LATIN = 'Inter, "Helvetica Neue", sans-serif';

/** drawn：画出来的界面（B 版）；否则是写着要录什么的占位块。两版共用同一条时间线。
 * out 是成片的帧号；frame 是它对应的母带帧号，屏里屏外的东西都按 frame 画，字幕、标签、片名和成片镜头按 out。 */
export function Film({ L, drawn }: { L: Layout; drawn: boolean }) {
  const out = useCurrentFrame();
  const frame = srcAt(out);
  const cqw = L.screen.w / 100;

  const page = drawn ? (
    <>
      <div style={{ position: 'absolute', inset: 0, background: WALL }} />
      <DrawnDesk frame={frame} L={L} />
      <Handle frame={frame} L={L} />
      {/* 锁屏：窗口都藏起来，只剩压暗的墙纸，刘海的轮廓看得出来。 */}
      <div style={{ position: 'absolute', inset: 0, background: WALL, opacity: screenDark(frame) }}>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.55)' }} />
      </div>
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
      <Camera out={out} frame={frame} L={L}>
        <Laptop L={L} frame={frame} page={page} over={over} />
        <Trackpad frame={frame} L={L} />
        <Phone frame={frame} L={L} />
        <Head frame={frame} L={L} />
        {drawn && <Device frame={frame} L={L} />}
      </Camera>
      <CaptionScrim out={out} frame={frame} L={L} />
      <Caption out={out} L={L} />
      <Wordmark out={out} L={L} />
      <AbsoluteFill style={{ background: '#000', opacity: seg(out, FADE_TO_BLACK[0], FADE_TO_BLACK[1]) }} />
    </AbsoluteFill>
  );
}

/**
 * 推近刘海：整块画面（机身和屏外线稿）绕刘海放大，刘海移到画面上方；字幕在外层，不跟着放大。
 * [片子新增] 倍数：读口型、认人两处横版 3.2、竖版 3.1，让紧凑态两边的点和字在 1080p 上看得清、提醒展开也不出画；
 * 冷开场 2.4，刘海贴近画面上沿，下面露出整扇终端窗口的宽度，看得见它被吸上去。
 */
const PUSH = { landscape: { scale: 3.2, y: 0.36 }, portrait: { scale: 3.1, y: 0.3 } } as const;
const OPEN = { landscape: { scale: 2.4, y: 0.14 }, portrait: { scale: 2.4, y: 0.2 } } as const;

/** 此刻推近多少（0–1）、推到几倍、刘海停在画面多高。冷开场按成片帧号，其余按母带帧号。 */
function pushAt(out: number, frame: number, L: Layout) {
  const open = 1 - dolly(out, OPEN_PULL);
  const near = zoomAt(frame);
  return open >= near ? { p: open, ...OPEN[L.name] } : { p: near, ...PUSH[L.name] };
}

function Camera({ out, frame, L, children }: { out: number; frame: number; L: Layout; children: ReactNode }) {
  const { p, scale, y } = pushAt(out, frame, L);
  const punch = punchAt(out);
  if (p <= 0 && punch <= 0) return <>{children}</>;
  const cqw = L.screen.w / 100;
  const fx = L.screen.x + L.screen.w / 2, fy = L.screen.y + (NOTCH.h * cqw) / 2;
  const z = (1 + (scale - 1) * p) * (1 + punch);
  const tx = fx + (L.width / 2 - fx) * p, ty = fy + (L.height * y - fy) * p;
  return <div style={{ position: 'absolute', inset: 0, transformOrigin: '0 0', transform: `translate(${tx}px, ${ty}px) scale(${z}) translate(${-fx}px, ${-fy}px)` }}>{children}</div>;
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
  const draft = draftAt(frame);
  const chat = chatBackAt(frame);
  const d = draft.rect;
  return (
    <>
      <MenuBar cqw={cqw} h={NOTCH.h} />
      <DraftWin box={box(d)} marks={draft.marks} />
      {draft.outline > 0 && (
        <div style={{ position: 'absolute', left: (d.x / 100) * L.screen.w - 0.4 * cqw, top: (d.y / 100) * L.screen.h - 0.4 * cqw, width: (d.w / 100) * L.screen.w + 0.8 * cqw, height: (d.h / 100) * L.screen.h + 0.8 * cqw, borderRadius: 3 * cqw, boxShadow: `inset 0 0 0 ${0.28 * cqw}px rgba(255,255,255,.85)`, opacity: draft.outline }} />
      )}
      {slots.map((s) => {
        const b = box(s.rect);
        switch (s.id) {
          case 'P1': return <MusicWin key={s.id} box={b} opacity={s.opacity} playing={frame >= MUSIC_PLAY} />;
          case 'P4': return <TermWin key={s.id} box={b} opacity={s.opacity} scale={s.scale} radius={s.radius} />;
          case 'P9': return <TermWin key={s.id} box={b} opacity={s.opacity} done={termDoneAt(frame)} />;
          case 'P5': return <HomeScreen key={s.id} cqw={cqw} sw={L.screen.w} sh={L.screen.h} opacity={s.opacity} hide={frame >= DRAG_PRESS ? DRAGGED_APP : undefined} />;
          case 'P8': return <ChatWin key={s.id} box={b} opacity={s.opacity} scale={s.scale} radius={s.radius} />;
          default: return null;
        }
      })}
      {side.length > 0 && <NotesWin box={box(side[0].rect)} opacity={sideOpacity} />}
      {chat && <ChatWin box={box(chat.rect)} scale={chat.scale} radius={chat.radius} />}
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

/** 屏外戴着耳机的侧脸线稿，朝着屏幕。只画轮廓和耳机，不画五官细节；点头绕脖子转。 */
function Head({ frame, L }: { frame: number; L: Layout }) {
  const h = headAt(frame);
  if (!h) return null;
  const size = Math.min(L.side.w, L.side.h) * 0.8;
  return (
    <svg style={{ position: 'absolute', left: L.side.x + (L.side.w - size) / 2, top: L.side.y + (L.side.h - size) / 2, opacity: h.opacity, overflow: 'visible' }} width={size} height={size} viewBox="0 0 100 100" fill="none" stroke="rgba(255,255,255,.75)" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
      <g transform={`rotate(${-h.tilt} 56 78)`}>
        <path d="M 62 82 L 62 72 C 74 68 80 56 78 42 C 76 26 64 16 50 16 C 36 16 26 26 25 38 L 20 50 L 25 52 L 25 60 C 25 66 30 68 36 67 L 40 67 L 40 82" />
        <g stroke="rgba(255,255,255,.95)"><circle cx={60} cy={44} r={3.2} /><line x1={60} y1={47.2} x2={60} y2={56} /></g>
      </g>
    </svg>
  );
}

/** 推近时画面铺满到字幕后面：字幕底下垫一条暗带，跟推近的程度、字幕本身一起出现。 */
function CaptionScrim({ out, frame, L }: { out: number; frame: number; L: Layout }) {
  const { p } = pushAt(out, frame, L);
  if (p <= 0) return null;
  const c = CAPTIONS.find((k) => out >= k.from && out < k.to);
  const o = p * (c ? captionOpacity(out, c.from, c.to) : 0);
  if (o <= 0) return null;
  const top = L.caption.cy - L.caption.size * 1.6, bottom = L.caption.cy + L.caption.size * 1.6;
  return <div style={{ position: 'absolute', left: 0, right: 0, top, height: bottom - top, opacity: o, background: 'linear-gradient(rgba(10,11,14,0), rgba(10,11,14,.88) 30%, rgba(10,11,14,.88) 70%, rgba(10,11,14,0))' }} />;
}

function Caption({ out, L }: { out: number; L: Layout }) {
  const c = CAPTIONS.find((k) => out >= k.from && out < k.to);
  if (!c) return null;
  const { cx, cy, size } = L.caption;
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: cy - size * 0.7, textAlign: 'center', fontFamily: CJK, fontSize: size, fontWeight: 600, color: '#f2f3f5', opacity: captionOpacity(out, c.from, c.to), letterSpacing: '0.02em', lineHeight: 1.4, transform: `translateX(${cx - L.width / 2}px)` }}>
      {c.text}
    </div>
  );
}

function Wordmark({ out, L }: { out: number; L: Layout }) {
  if (out < WORDMARK_AT) return null;
  const { cy, size } = L.wordmark;
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: cy - size * 0.7, textAlign: 'center', fontFamily: LATIN, fontSize: size, fontWeight: 600, color: '#f2f3f5', opacity: clamp01((out - WORDMARK_AT) / CAPTION_IN), letterSpacing: '-0.01em' }}>
      WindowShade 2
    </div>
  );
}
