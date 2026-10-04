import type { ReactNode } from 'react';
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from 'remotion';
import { SCREEN_ASPECT, type Layout, type Rect } from './layout';
import { CAPTION_IN } from './motion/direction';
import { FPS, NOTCH, TEACH_TUCKED, clamp01, mix, seg, teachPos } from './motion/site';
import { MUSIC_PLAY } from './timeline';
import { CAPTIONS, FADE_TO_BLACK, WORDMARK_AT, captionOpacity, shotAt, shotStartAt, srcAt, type Framing } from './cut';
import { MIX_FILE } from './music';
import { shutterSamples } from './shutter';
import {
  DRAGGED_APP, DRAG_PRESS, HANDLE_POS, ICON_SIZE, chatBackAt, clutterAt, deviceAt, dragIconAt, draftAt, fingerAt, handleAt, phoneAt,
  pointerAt, screenDark, slotsAt, termDoneAt, trackpadAt,
} from './scene';
import { Laptop } from './parts/Laptop';
import { Hero } from './parts/Hero';
import { Island } from './parts/Island';
import { Placeholder } from './parts/Placeholder';
import { AppIcon, ChatWin, DraftWin, HomeScreen, MenuBar, MusicWin, NotesWin, TermWin, Wallpaper } from './parts/Mock';

const CJK = '"PingFang SC",-apple-system,system-ui,sans-serif';
const LATIN = '-apple-system,system-ui,"SF Pro Display",sans-serif';

type FilmProps = { L: Layout; drawn: boolean; blind?: boolean; step?: number };

/**
 * 成片：混好的声音一轨，加上快门。快的帧在 180° 快门（半帧）里取几个时刻叠成平均，取样不跨剪接点；
 * 哪些帧快、取几样是 shutter.ts 里事先量好的常数，所以每一帧仍只看帧号。
 * blind：去掉所有文字，给 onetake 的盲读表用。step 2：30 fps 草稿，每帧走两格，快门也开两倍长。
 */
export function Film({ L, drawn, blind, step = 1 }: FilmProps) {
  const out = useCurrentFrame() * step;
  const n = shutterSamples(out);
  const start = shotStartAt(out);
  const open = 0.5 * step;
  const times = Array.from({ length: n }, (_, j) => Math.max(start, out - (n > 1 ? (open * (n - 1 - j)) / (n - 1) : 0)));
  return (
    <AbsoluteFill className={blind ? 'ws-blind' : undefined} style={{ background: BACKDROP }}>
      {blind ? <style>{'.ws-blind *{color:transparent!important;-webkit-text-fill-color:transparent!important;text-shadow:none!important}.ws-blind text{fill:transparent!important;stroke:none!important}'}</style> : <Audio src={staticFile(MIX_FILE)} />}
      {times.map((t, j) => (
        <AbsoluteFill key={j} style={{ opacity: 1 / (j + 1) }}>
          <FilmFrame L={L} drawn={drawn} out={t} />
        </AbsoluteFill>
      ))}
    </AbsoluteFill>
  );
}

/** 机身外面的底色：比第一版亮一档，偏冷的灰蓝，刘海的纯黑在上面看得出轮廓。 */
const BACKDROP = 'radial-gradient(110% 85% at 50% 32%, #2b303c 0%, #181b23 58%, #0d0f13 100%)';
/** 屏里整体提亮一点、对比加一点（刘海不在这一层，保持纯黑）。 */
const SCREEN_LIFT = 'brightness(1.1) contrast(1.06) saturate(1.05)';
/** 点刘海那一下（scene.ts 里 P5 主屏幕从这一帧进场）：启动台从刘海里长出来，走 teach.js 的位置弹簧。 */
const LAUNCH_AT = 3021;

/** drawn：画出来的界面（B 版）；否则是写着要录什么的占位块。两版共用同一条时间线。
 * out 是成片的帧号（快门取样时带小数）；frame 是它对应的母带帧号，屏里屏外的东西都按 frame 画，标题、片名和景别按 out。 */
function FilmFrame({ L, drawn, out }: { L: Layout; drawn: boolean; out: number }) {
  const frame = srcAt(out);
  const cqw = L.screen.w / 100;
  const framing = shotAt(out).framing;

  const page = drawn ? (
    <div style={{ position: 'absolute', inset: 0, filter: SCREEN_LIFT }}>
      <Wallpaper />
      <DrawnDesk frame={frame} L={L} />
      <Handle frame={frame} L={L} />
      <LockScreen frame={frame} L={L} />
    </div>
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
    <AbsoluteFill style={{ background: BACKDROP, overflow: 'hidden' }}>
      <Camera framing={framing} L={L}>
        {framing === 'wide' ? <Hero L={L} page={page} over={over} /> : <Laptop L={L} frame={frame} page={page} over={over} />}
        {framing !== 'wide' && <Trackpad frame={frame} L={L} />}
        {framing !== 'wide' && <Phone frame={frame} L={L} />}
        {drawn && framing !== 'wide' && <Device frame={frame} L={L} />}
      </Camera>
      <Headline out={out} L={L} />
      <Wordmark out={out} L={L} />
      <AbsoluteFill style={{ background: '#000', opacity: seg(out, FADE_TO_BLACK[0], FADE_TO_BLACK[1]) }} />
    </AbsoluteFill>
  );
}

/**
 * 景别：每一刀换一种，镜头在一个镜头里不动（只在剪接点变）。z 是放大倍数，把机身上的点 (ax, ay) 放到画面的 (tx, ty)。
 * close：刘海占画面宽 17%（横版屏宽 = 1.6 × 画面宽），停在画面 42% 高，上面留给标题；
 * near：屏宽 1.18 × 画面宽，刘海靠上，看得见主屏幕那一排图标；medium：屏幕铺满画面宽，从屏幕上沿往下看七成；
 * desk：整机加右边（竖版是下面）的触控板、手机；wide：Hero 整机。
 */
function framingOf(framing: Framing, L: Layout) {
  const { width: W, height: H, screen: S } = L;
  const cqw = S.w / 100;
  const notch = { x: S.x + S.w / 2, y: S.y + (NOTCH.h * cqw) / 2 };
  const top = { x: S.x + S.w / 2, y: S.y };
  const tall = L.name !== 'landscape';
  switch (framing) {
    case 'close': return { z: ((tall ? 1.7 : 1.6) * W) / S.w, a: notch, t: { x: W / 2, y: H * (tall ? 0.36 : 0.42) } };
    case 'near': return { z: ((tall ? 1.25 : 1.18) * W) / S.w, a: notch, t: { x: W / 2, y: H * (tall ? 0.3 : 0.27) } };
    case 'medium': return { z: ((tall ? 1.0 : 0.94) * W) / S.w, a: top, t: { x: W / 2, y: H * (tall ? 0.27 : 0.22) } };
    case 'desk': return tall
      ? { z: 0.9, a: top, t: { x: W / 2, y: H * 0.24 } }
      : { z: 0.84, a: { x: W / 2 + 50, y: S.y }, t: { x: W / 2, y: H * 0.2 } };
    case 'wide': return { z: tall ? 0.82 : 0.7, a: top, t: { x: W / 2, y: H * (tall ? 0.3 : 0.25) } };
  }
}

function Camera({ framing, L, children }: { framing: Framing; L: Layout; children: ReactNode }) {
  const { z, a, t } = framingOf(framing, L);
  return <div style={{ position: 'absolute', inset: 0, transformOrigin: '0 0', transform: `translate(${t.x}px, ${t.y}px) scale(${z}) translate(${-a.x}px, ${-a.y}px)` }}>{children}</div>;
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
          case 'P5': {
            const grow = teachPos(((frame - LAUNCH_AT) / FPS) * 1000);
            return (
              <div key={s.id} style={{ position: 'absolute', inset: 0, transformOrigin: '50% 0', transform: `scale(${mix(0.08, 1, grow)})`, borderRadius: mix(6, 0, grow) * cqw, overflow: 'hidden' }}>
                <HomeScreen cqw={cqw} sw={L.screen.w} sh={L.screen.h} opacity={s.opacity} hide={frame >= DRAG_PRESS ? DRAGGED_APP : undefined} />
              </div>
            );
          }
          case 'P8': return <ChatWin key={s.id} box={b} opacity={s.opacity} scale={s.scale} radius={s.radius} />;
          default: return null;
        }
      })}
      {clutterAt(frame).map((c) => {
        const p = { key: c.kind, box: box(c.rect), opacity: c.opacity, scale: c.scale, radius: c.radius };
        return c.kind === 'music' ? <MusicWin {...p} playing /> : c.kind === 'notes' ? <NotesWin {...p} /> : <ChatWin {...p} />;
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

/** 刘海下沿（屏高 %）再往下一点：真机上指针进不了刘海，点刘海时尖端停在这里。 */
const BELOW_NOTCH = NOTCH.h * SCREEN_ASPECT + 0.7;

/** 画出来的那一版用箭头指针，尖端在 (x, y)；落在刘海那块里时贴到刘海下沿。 */
function Arrow({ frame, L }: { frame: number; L: Layout }) {
  const p = pointerAt(frame);
  if (!p) return null;
  const s = L.screen.w * 0.022;
  const y = Math.abs(p.x - 50) < NOTCH.w / 2 + 1 ? Math.max(p.y, BELOW_NOTCH) : p.y;
  return (
    <svg style={{ position: 'absolute', left: (p.x / 100) * L.screen.w, top: (y / 100) * L.screen.h, opacity: p.opacity, overflow: 'visible', transform: `scale(${1 - 0.1 * p.pressed})`, transformOrigin: '0 0' }} width={s} height={s} viewBox="0 0 20 20">
      <path d="M1 1 L1 15.5 L4.8 12 L7.4 18 L10 16.9 L7.5 11 L12.6 11 Z" fill="#000" stroke="#fff" strokeWidth={1.3} strokeLinejoin="round" />
    </svg>
  );
}

/** 屏外的实物：一对 AirPods Pro、一只妙控鼠标，俯视，照真的配色和高光。连上的那一刻亮一圈。 */
function Device({ frame, L }: { frame: number; L: Layout }) {
  const d = deviceAt(frame);
  if (!d) return null;
  const size = Math.min(L.side.w, L.side.h) * 0.8;
  return (
    <svg style={{ position: 'absolute', left: L.side.x + (L.side.w - size) / 2, top: L.side.y + (L.side.h - size) / 2, opacity: d.opacity, overflow: 'visible', filter: `drop-shadow(0 ${size * 0.03}px ${size * 0.05}px rgba(0,0,0,.6))` }} width={size} height={size} viewBox="0 0 100 100">
      <defs>
        <radialGradient id="podW" cx="35%" cy="30%" r="80%"><stop offset="0" stopColor="#ffffff" /><stop offset="0.6" stopColor="#e9eaee" /><stop offset="1" stopColor="#b9bcc4" /></radialGradient>
        <linearGradient id="mouseW" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#ffffff" /><stop offset="0.55" stopColor="#eef0f3" /><stop offset="1" stopColor="#c4c7ce" /></linearGradient>
      </defs>
      {d.kind === 'pods' ? (
        <g>
          {[[33, 1], [67, -1]].map(([x, k]) => (
            <g key={x} transform={`translate(${x} 44) scale(${k} 1)`}>
              <rect x={-3.6} y={8} width={7.2} height={26} rx={3.6} fill="url(#podW)" />
              <ellipse cx={0} cy={4} rx={11} ry={12.5} fill="url(#podW)" />
              <ellipse cx={4} cy={2} rx={4.6} ry={5.6} fill="#2b2d31" />
              <ellipse cx={4} cy={2} rx={3.4} ry={4.4} fill="#5b5e64" />
              <rect x={-1.4} y={28} width={2.8} height={4} rx={1.4} fill="#1c1d20" opacity={0.6} />
            </g>
          ))}
          <circle cx={50} cy={50} r={46} fill="none" stroke="#34c759" strokeWidth={0.8} opacity={0.7 * d.on * (1 - d.on * 0.4)} />
        </g>
      ) : (
        <g>
          <rect x={32} y={12} width={36} height={76} rx={18} fill="url(#mouseW)" />
          <rect x={32} y={12} width={36} height={76} rx={18} fill="none" stroke="rgba(0,0,0,.18)" strokeWidth={0.5} />
          <path d="M 36 30 Q 50 22 64 30" fill="none" stroke="rgba(0,0,0,.06)" strokeWidth={0.6} />
          <circle cx={50} cy={50} r={46} fill="none" stroke="#34c759" strokeWidth={0.8} opacity={0.7 * d.on * (1 - d.on * 0.4)} />
        </g>
      )}
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
    <svg style={{ position: 'absolute', left: x0, top: y0, opacity: o, overflow: 'visible', filter: `drop-shadow(0 ${w * 0.03}px ${w * 0.05}px rgba(0,0,0,.55))` }} width={w} height={h}>
      {/* 妙控板：银色铝面，四边一道倒角的亮边。 */}
      <defs>
        <linearGradient id="padAl" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stopColor="#e4e6ea" /><stop offset="0.5" stopColor="#cfd2d8" /><stop offset="1" stopColor="#b6bac2" /></linearGradient>
      </defs>
      <rect x={0} y={0} width={w} height={h} rx={w * 0.05} fill="url(#padAl)" />
      <rect x={1} y={1} width={w - 2} height={h - 2} rx={w * 0.05} fill="none" stroke="rgba(255,255,255,.7)" strokeWidth={1.5} />
      {f && f.trail.length > 1 && (
        <polyline
          points={f.trail.map((p) => { const q = at(p); return `${q.x},${q.y}`; }).join(' ')}
          fill="none" stroke="rgba(10,132,255,.45)" strokeWidth={r * 0.9} strokeLinecap="round" strokeLinejoin="round" opacity={f.opacity}
        />
      )}
      {f && (() => {
        const q = at(f);
        return f.down
          ? <circle cx={q.x} cy={q.y} r={r} fill="rgba(10,132,255,.6)" stroke="rgba(255,255,255,.8)" strokeWidth={1.2} opacity={f.opacity} />
          : <circle cx={q.x} cy={q.y} r={r} fill="rgba(60,64,72,.18)" stroke="rgba(60,64,72,.55)" strokeWidth={1.5} opacity={f.opacity} />;
      })()}
    </svg>
  );
}

/** 屏外的 iPhone：钛金属边框、黑玻璃、灵动岛，锁屏亮着时间。 */
function Phone({ frame, L }: { frame: number; L: Layout }) {
  const p = phoneAt(frame);
  if (!p) return null;
  const h = L.side.h * 0.66, w = h * 0.487;
  const cx = L.side.x + L.side.w / 2, cy = L.side.y + L.side.h / 2;
  const dx = p.away * (L.width - L.side.x + w);
  const r = w * 0.2, bez = w * 0.045;
  return (
    <div style={{ position: 'absolute', left: cx - w / 2 + dx, top: cy - h / 2, width: w, height: h, opacity: p.opacity, borderRadius: r, background: 'linear-gradient(135deg,#8d8a86,#4a4846 30%,#6c6a67 55%,#3a3937 80%,#7a7774)', boxShadow: `0 ${w * 0.06}px ${w * 0.18}px rgba(0,0,0,.6)` }}>
      <div style={{ position: 'absolute', inset: bez * 0.35, borderRadius: r - bez * 0.35, background: '#050505' }} />
      <div style={{ position: 'absolute', inset: bez, borderRadius: r - bez, overflow: 'hidden', background: 'radial-gradient(120% 70% at 30% 20%,#1d3b66 0%,#0b1626 55%,#05070b 100%)' }}>
        <div style={{ position: 'absolute', left: '50%', top: h * 0.018, width: w * 0.32, height: w * 0.09, transform: 'translateX(-50%)', borderRadius: 99, background: '#000' }} />
        <div style={{ position: 'absolute', top: h * 0.1, width: '100%', textAlign: 'center', fontFamily: CJK, color: 'rgba(255,255,255,.9)', fontSize: w * 0.065, fontWeight: 600 }}>10月4日 星期日</div>
        <div style={{ position: 'absolute', top: h * 0.125, width: '100%', textAlign: 'center', fontFamily: LATIN, color: 'rgba(255,255,255,.92)', fontSize: w * 0.3, fontWeight: 700, letterSpacing: '-0.02em' }}>9:41</div>
      </div>
    </div>
  );
}

/** 锁屏（macOS Golden Gate）：墙纸照常亮着，上面是日期和大时间，下面头像、名字、Touch ID 或密码的提示。窗口都藏起来。 */
function LockScreen({ frame, L }: { frame: number; L: Layout }) {
  const o = screenDark(frame);
  if (o <= 0) return null;
  const cqw = L.screen.w / 100;
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: o, fontFamily: CJK, color: '#fff', textAlign: 'center' }}>
      <Wallpaper dim={0.12} />
      <div style={{ position: 'absolute', top: 7.2 * cqw, width: '100%', fontSize: 1.9 * cqw, fontWeight: 600, opacity: 0.85 }}>10月4日 星期日</div>
      <div style={{ position: 'absolute', top: 8.6 * cqw, width: '100%', fontFamily: LATIN, fontSize: 11 * cqw, fontWeight: 700, letterSpacing: '-0.03em', opacity: 0.88, textShadow: '0 0.3vw 2vw rgba(0,0,0,.15)' }}>9:41</div>
      <div style={{ position: 'absolute', bottom: 6 * cqw, width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0.9 * cqw }}>
        <div style={{ width: 4.6 * cqw, height: 4.6 * cqw, borderRadius: '50%', background: 'linear-gradient(160deg,#a4b0be,#6b7787)', display: 'grid', placeItems: 'center', fontFamily: LATIN, fontSize: 2 * cqw, fontWeight: 600, boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,.35)' }}>A</div>
        <div style={{ fontSize: 1.45 * cqw, fontWeight: 600 }}>Aaron</div>
        <div style={{ fontSize: 1.1 * cqw, opacity: 0.7 }}>触控 ID 或输入密码</div>
      </div>
    </div>
  );
}

/** 标题字号：横版按 1920 宽，竖版按 1080 宽等比。 */
const headSize = (L: Layout) => (L.name === 'landscape' ? { zh: 66, en: 30, top: 0.062 } : { zh: 76 * (L.width / 1080), en: 30 * (L.width / 1080), top: 0.1 });

/** 每段一句大标题在画面上方，下面一行英文小字；进场 0.3 秒淡入、往上升一点（正弦缓动），不跟着镜头。 */
function Headline({ out, L }: { out: number; L: Layout }) {
  const c = CAPTIONS.find((k) => out >= k.from && out < k.to);
  if (!c) return null;
  const { zh, en, top } = headSize(L);
  const o = captionOpacity(out, c.from, c.to);
  const rise = (1 - Math.sin((Math.PI / 2) * clamp01((out - c.from) / (CAPTION_IN * 1.5)))) * zh * 0.6;
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: L.height * top, textAlign: 'center', opacity: o, transform: `translateY(${rise}px)` }}>
      <div style={{ fontFamily: CJK, fontSize: zh, fontWeight: 600, color: '#f4f5f7', letterSpacing: '0.02em', lineHeight: 1.25 }}>{c.text}</div>
      <div style={{ fontFamily: LATIN, fontSize: en, fontWeight: 500, color: 'rgba(244,245,247,.62)', marginTop: en * 0.45, letterSpacing: '0.01em' }}>{c.en}</div>
    </div>
  );
}

/** 片名落在最后一个重拍，下面一行网址。 */
function Wordmark({ out, L }: { out: number; L: Layout }) {
  if (out < WORDMARK_AT) return null;
  const { zh, en, top } = headSize(L);
  const o = clamp01((out - WORDMARK_AT) / CAPTION_IN);
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: L.height * top, textAlign: 'center', opacity: o }}>
      <div style={{ fontFamily: LATIN, fontSize: zh * 1.15, fontWeight: 600, color: '#f4f5f7', letterSpacing: '-0.01em', lineHeight: 1.15 }}>WindowShade 2</div>
      <div style={{ fontFamily: LATIN, fontSize: en, fontWeight: 500, color: 'rgba(244,245,247,.62)', marginTop: en * 0.45 }}>windowshade.aaronlau.me</div>
    </div>
  );
}
