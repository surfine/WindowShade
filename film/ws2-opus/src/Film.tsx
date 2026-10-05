import { useRef, useState, type ReactNode } from 'react';
import { AbsoluteFill, Audio, staticFile, useCurrentFrame, useDelayRender } from 'remotion';
import { cameraAt } from './camera';
import { LANDSCAPE, type Layout, type Rect } from './layout';
import { CAPTION_IN } from './motion/direction';
import { FPS, NOTCH, TEACH_TUCKED, clamp01, mix, pt, seg } from './motion/site';
import { approach } from './motion/springs';
import { CONDUCT_IN, CONDUCT_SEND, CONDUCT_TONE, MUSIC_PLAY } from './timeline';
import { CAPTIONS, FADE_TO_BLACK, WORDMARK_AT, captionOpacity, shotStartAt, srcAt } from './cut';
import { MIX_FILE } from './music';
import { shutterSamples } from './shutter';
import {
  DRAGGED_APP, DRAG_PRESS, HANDLE_POS, ICON_SIZE, STROKE, chatBackAt, clutterAt, conductAt, conductStrokeAt, deviceAt, dragIconAt, draftAt, handleAt, phoneAt,
  pointerAt, screenDark, slotsAt, termDoneAt,
} from './scene';
import { Air } from './parts/Air';
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
      {blind ? <style>{'.ws-blind *{color:transparent!important;-webkit-text-fill-color:transparent!important;text-shadow:none!important}.ws-blind text{fill:transparent!important;stroke:none!important}'}</style> : <Audio src={staticFile(MIX_FILE)} volume={0.977} />}
      {times.map((t, j) => (
        <AbsoluteFill key={j} style={{ opacity: 1 / (j + 1) }}>
          <FilmFrame L={L} drawn={drawn} out={t} />
        </AbsoluteFill>
      ))}
    </AbsoluteFill>
  );
}

/** 螢幕貼圖：跟成片同一套介面，兩倍像素，給顯示網格的 UV 用。 */
export const SCREEN_PLATE = {
  width: Math.round(LANDSCAPE.screen.w * 2),
  height: Math.round(LANDSCAPE.screen.h * 2),
};

export function ScreenPlate() {
  const out = useCurrentFrame();
  const L: Layout = { ...LANDSCAPE, width: SCREEN_PLATE.width, height: SCREEN_PLATE.height };
  return <FilmFrame L={L} drawn out={out} plate />;
}

/** 机身外面的底色：比第一版亮一档，偏冷的灰蓝，刘海的纯黑在上面看得出轮廓。 */
const BACKDROP = 'radial-gradient(110% 85% at 50% 32%, #2b303c 0%, #181b23 58%, #0d0f13 100%)';
/** 屏里整体提亮一点、对比加一点（刘海不在这一层，保持纯黑）。 */
const SCREEN_LIFT = 'brightness(1.1) contrast(1.06) saturate(1.05)';
/** 点刘海那一下（scene.ts 里 P5 主屏幕从这一帧进场）：启动台从刘海里长出来，走 teach.js 的位置弹簧。 */
const LAUNCH_AT = 3021;

/** drawn：画出来的界面（B 版）；否则是写着要录什么的占位块。两版共用同一条时间线。
 * out 是成片的帧号（快门取样时带小数）；frame 是它对应的母带帧号，屏里屏外的东西都按 frame 画，标题、片名和景别按 out。 */
function FilmFrame({ L, drawn, out, plate = false }: { L: Layout; drawn: boolean; out: number; plate?: boolean }) {
  const frame = srcAt(out);
  // 介面按兩倍畫進貼圖，特寫時字才不會糊。相機對位仍用原來的 L.screen。
  // plate：這塊就是貼圖本身，尺寸已經是整數像素。
  const HS: Layout = plate
    ? { ...L, screen: { x: 0, y: 0, w: L.width, h: L.height } }
    : { ...L, screen: { ...L.screen, w: L.screen.w * 2, h: L.screen.h * 2 } };
  const cqw = HS.screen.w / 100;
  const { delayRender, continueRender } = useDelayRender();
  const [paintHandle] = useState(() => (plate ? 0 : delayRender('screen-ui')));
  const painted = useRef(false);
  const ready = () => {
    if (painted.current) return;
    painted.current = true;
    continueRender(paintHandle);
  };

  const page = drawn ? (
    <div style={{ position: 'absolute', inset: 0, filter: SCREEN_LIFT }}>
      <Wallpaper />
      <DrawnDesk frame={frame} L={HS} />
      <Handle frame={frame} L={HS} />
      <LockScreen frame={frame} L={HS} />
    </div>
  ) : (
    <>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(160deg,#252a34 0%,#161920 55%,#101217 100%)' }} />
      {slotsAt(frame).map((s) => <Placeholder key={s.id} L={HS} slot={s} />)}
      <Handle frame={frame} L={HS} />
      <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: screenDark(frame) }} />
    </>
  );
  const over = (
    <>
      <Island frame={frame} cqw={cqw} drawn={drawn} />
      {drawn ? <Arrow frame={frame} L={HS} /> : <Pointer frame={frame} L={HS} />}
    </>
  );

  if (plate) {
    return (
      <AbsoluteFill style={{ background: '#000', overflow: 'hidden' }}>
        {page}
        {over}
      </AbsoluteFill>
    );
  }

  return (
    <AbsoluteFill style={{ background: BACKDROP, overflow: 'hidden' }}>
      <Air L={L} out={out} frame={frame} onReady={ready} />
      <Camera out={out} L={L}>
        <Phone frame={frame} L={L} />
        {drawn && <Device frame={frame} L={L} />}
      </Camera>
      {drawn && <Remote frame={frame} L={L} />}
      <Headline out={out} L={L} />
      <Wordmark out={out} L={L} />
      <AbsoluteFill style={{ background: '#000', opacity: seg(out, FADE_TO_BLACK[0], FADE_TO_BLACK[1]) }} />
    </AbsoluteFill>
  );
}

/** 鏡頭跟 dolly 走，景別是目標，不是停住的畫幅。 */
function Camera({ out, L, children }: { out: number; L: Layout; children: ReactNode }) {
  const { z, ax, ay, tx, ty } = cameraAt(out, L);
  return <div style={{ position: 'absolute', inset: 0, transformOrigin: '0 0', transform: `translate(${tx}px, ${ty}px) scale(${z}) translate(${-ax}px, ${-ay}px)` }}>{children}</div>;
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
        <div style={{ position: 'absolute', left: (d.x / 100) * L.screen.w, top: (d.y / 100) * L.screen.h, width: (d.w / 100) * L.screen.w, height: (d.h / 100) * L.screen.h, borderRadius: pt(22 / 1.684) * cqw, pointerEvents: 'none', boxShadow: `inset 0 0 0 ${0.14 * cqw}px rgba(255,255,255,.4)`, opacity: draft.outline }} />
      )}
      {slots.map((s) => {
        const b = box(s.rect);
        switch (s.id) {
          case 'P1': return <MusicWin key={s.id} box={b} opacity={s.opacity} playing={frame >= MUSIC_PLAY} />;
          case 'P4': return <TermWin key={s.id} box={b} opacity={s.opacity} scale={s.scale} radius={s.radius} />;
          case 'P9': return <TermWin key={s.id} box={b} opacity={s.opacity} done={termDoneAt(frame)} />;
          case 'P5': {
            const grow = approach(((frame - LAUNCH_AT) / FPS) * 1000, 'expand');
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

/** 箭头尖端按指针位置画。物理刘海是網格上的洞，尖端走进去就被機身擋住。 */
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
      <div style={{ position: 'absolute', top: 8 * cqw, width: '100%', fontSize: 1.15 * cqw, fontWeight: 600, opacity: 0.85 }}>10月4日 星期日</div>
      <div style={{ position: 'absolute', top: 10 * cqw, width: '100%', fontFamily: LATIN, fontSize: 5.6 * cqw, fontWeight: 600, letterSpacing: '-0.03em', opacity: 0.92 }}>9:41</div>
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

/**
 * 《指挥模式》的 iPhone 遥控器：触控区画一笔，侧边按钮说一句，松开是草稿，播放键发出去。
 * 摆在暗背景上，不跟镜头走，也不畫在 Mac 觸控板上。
 */
function Remote({ frame, L }: { frame: number; L: Layout }) {
  const phase = conductAt(frame);
  if (phase === 'off' || phase === 'result') return null;
  const fadeIn = clamp01((frame - CONDUCT_IN) / 12);
  const fadeOut = clamp01((frame - (CONDUCT_SEND + 28)) / 16);
  const opacity = fadeIn * (1 - fadeOut);
  if (opacity <= 0.01) return null;
  const h = L.height * (L.name === 'landscape' ? 0.5 : 0.32);
  const w = h * 0.48;
  const left = L.name === 'landscape' ? 44 : L.width * 0.06;
  const top = L.height * (L.name === 'landscape' ? 0.3 : 0.62);
  const stroke = conductStrokeAt(frame);
  const n = Math.max(2, Math.round(stroke * (STROKE.length - 1)));
  const pad = STROKE.slice(0, n + 1);
  const d = pad.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ');
  const talking = phase === 'talk';
  const toned = phase === 'tone' || frame >= CONDUCT_TONE;
  const sent = phase === 'sent' || frame >= CONDUCT_SEND;
  const showDraft = phase === 'draft' || phase === 'sent';
  const showTone = toned && !talking && !showDraft;
  return (
    <div style={{ position: 'absolute', left, top, width: w, height: h, opacity, borderRadius: w * 0.18, background: 'linear-gradient(160deg,#c8c6c2,#6e6c69 28%,#3a3937 70%,#8d8a86)', boxShadow: `0 ${w * 0.08}px ${w * 0.2}px rgba(0,0,0,.55)` }}>
      <div style={{ position: 'absolute', top: h * 0.16, bottom: h * 0.22, right: -w * 0.012, width: w * 0.035, borderRadius: w * 0.02, background: talking ? '#f2f2f4' : '#2a2928', boxShadow: talking ? '0 0 12px rgba(255,255,255,.35)' : undefined }} />
      <div style={{ position: 'absolute', inset: w * 0.045, borderRadius: w * 0.14, background: '#0c0d10', overflow: 'hidden', fontFamily: CJK, color: '#fff' }}>
        <div style={{ position: 'absolute', left: '50%', top: h * 0.02, width: w * 0.28, height: w * 0.07, transform: 'translateX(-50%)', borderRadius: 99, background: '#000' }} />
        <div style={{ position: 'absolute', left: w * 0.06, right: w * 0.06, top: h * 0.085, fontSize: w * 0.055, color: 'rgba(255,255,255,.55)', textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>WindowShade · Claude</div>
        <div style={{ position: 'absolute', left: w * 0.08, right: w * 0.08, top: h * 0.14, height: h * 0.36, borderRadius: w * 0.06, background: '#1a1c22' }}>
          {(stroke > 0.02 || showTone) && (
            <svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none">
              <path d={showTone ? STROKE.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ') : d} fill="none" stroke="#f5f5f7" strokeWidth={3.2} strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          )}
        </div>
        {showTone && (
          <div style={{ position: 'absolute', left: w * 0.08, right: w * 0.08, top: h * 0.54, textAlign: 'center' }}>
            <div style={{ fontSize: w * 0.08, fontWeight: 700, lineHeight: 1.2 }}>三声 · high</div>
            <div style={{ marginTop: h * 0.01, fontSize: w * 0.055, color: 'rgba(255,255,255,.62)' }}>下一轮</div>
          </div>
        )}
        {talking && (
          <div style={{ position: 'absolute', left: 0, right: 0, top: h * 0.55, display: 'flex', justifyContent: 'center', gap: w * 0.025 }}>
            {[0.35, 0.7, 1, 0.55, 0.8].map((k, i) => <i key={i} style={{ width: w * 0.025, height: h * 0.06 * k, borderRadius: 99, background: 'rgba(255,255,255,.85)', alignSelf: 'center' }} />)}
          </div>
        )}
        {showDraft && (
          <div style={{ position: 'absolute', left: w * 0.08, right: w * 0.08, top: h * 0.55, textAlign: 'center' }}>
            <div style={{ fontSize: w * 0.075, fontWeight: 600, lineHeight: 1.25 }}>{sent ? '发出去了' : '核对三处引文'}</div>
            <div style={{ marginTop: h * 0.012, fontSize: w * 0.058, color: 'rgba(255,255,255,.62)' }}>{sent ? '三声 · high' : '草稿'}</div>
          </div>
        )}
        <div style={{ position: 'absolute', left: '50%', bottom: h * 0.045, width: w * 0.16, height: w * 0.16, transform: 'translateX(-50%)', borderRadius: '50%', background: sent ? '#0a84ff' : 'rgba(255,255,255,.14)', display: 'grid', placeItems: 'center' }}>
          <div style={{ width: 0, height: 0, borderLeft: `${w * 0.055}px solid #fff`, borderTop: `${w * 0.038}px solid transparent`, borderBottom: `${w * 0.038}px solid transparent`, marginLeft: w * 0.012 }} />
        </div>
      </div>
    </div>
  );
}

/** 每段一句大标题在画面上方，下面一行英文小字；进场 0.3 秒淡入、往上升一点（正弦缓动），不跟着镜头。 */
function Headline({ out, L }: { out: number; L: Layout }) {
  const c = CAPTIONS.find((k) => out >= k.from && out < k.to);
  if (!c) return null;
  const { zh, en, top } = headSize(L);
  const o = captionOpacity(out, c.from, c.to);
  return (
    <div style={{ position: 'absolute', left: 0, width: L.width, top: L.height * top, textAlign: 'center', opacity: o }}>
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
      <div style={{ fontFamily: LATIN, fontSize: zh * 1.45, fontWeight: 600, color: '#f4f5f7', letterSpacing: '-0.02em', lineHeight: 1.05 }}>WindowShade 2</div>
      <div style={{ fontFamily: LATIN, fontSize: en * 0.62, fontWeight: 500, color: 'rgba(244,245,247,.5)', marginTop: en * 0.7 }}>windowshade.aaronlau.me</div>
    </div>
  );
}
