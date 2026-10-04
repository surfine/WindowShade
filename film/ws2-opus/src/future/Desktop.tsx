// 这块屏上的 macOS Golden Gate：深色外观，单位是点（1710 × 1107，15 英寸 MacBook Air 默认分辨率）。
import type { CSSProperties, ReactNode } from 'react';
import { Img } from 'remotion';
import { DOCK, ICON, LAUNCH, PLATE } from './assets';
import { Battery, ControlCenter, MONO, Pointer, SF, SFD, Search, Wifi, CJK } from './glyphs';
import { CP_NEXT, NEXT_BTN } from './CarPlay';
import { NOTCH_PT, PT } from './shape';
import { clamp01, fade, mix, seg, smooth, spring } from './time';

const MENU_H = NOTCH_PT.h;
const DOCK_ICON = 54, DOCK_PAD = 7, DOCK_GAP = 5;
const DOCK_H = DOCK_ICON + 2 * DOCK_PAD;
const DOCK_BOTTOM = 6;

// ---- 什么时候发生什么 ----
/** 1 是锁屏。0–112 锁着，112 认出你；3184 走开后锁上。 */
export function lockedAt(f: number) {
  if (f < 3184) return 1 - smooth(seg(f, 112, 150));
  return smooth(seg(f, 3184, 3214));
}
/** 启动台：512 打开，960 收回（落在第 8 小节的强拍）。 */
export const LP_OPEN = 512, LP_CLOSE = 960;
/** 点头之后，最前面那扇窗滑到左半屏。 */
export const GLIDE_AT = 1890;
const W1 = { x: 168, y: 96, w: 900, h: 630 };
const LEFT = { x: 8, y: MENU_H + 8, w: PT.w / 2 - 12, h: PT.h - MENU_H - 8 - (DOCK_H + DOCK_BOTTOM + 8) };

export function Screen({ f }: { f: number }) {
  const lock = lockedAt(f);
  const lp = launchpadBg(f);
  const desk = 1 - lock;
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: PT.w, height: PT.h, overflow: 'hidden', background: '#000', fontFamily: SF }}>
      <Img src={PLATE.wall} style={{ position: 'absolute', left: 0, top: (PT.h - PT.w) / 2, width: PT.w, height: PT.w, objectFit: 'cover', transform: `scale(${1 + lock * 0.04})` }} />
      {/* 夜里：桌布压暗一点 */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(4,8,20,.22)' }} />
      <div style={{ position: 'absolute', inset: 0, opacity: desk * (1 - lp), transform: `scale(${mix(1.025, 1, desk) * mix(1, 0.94, lp)})`, transformOrigin: '50% 45%' }}>
        <Windows f={f} />
      </div>
      {lp > 0 && <LaunchpadBack lp={lp} />}
      {lp > 0 && <Launchpad f={f} />}
      <div style={{ opacity: desk * (1 - lp) }}>
        <Dock />
      </div>
      {lock > 0 && <LockScreen lock={lock} />}
      <MenuBar f={f} desk={desk} lp={lp} />
      <Ghost f={f} />
      <Cursor f={f} />
    </div>
  );
}

// ---- 菜单栏：透明，字是白的 ----
function MenuBar({ f, desk, lp }: { f: number; desk: number; lp: number }) {
  const app = f >= LP_OPEN && f < LP_CLOSE ? '访达' : 'Safari 浏览器';
  const menus = ['文件', '编辑', '显示', '历史记录', '书签', '窗口', '帮助'];
  const shadow = '0 0 6px rgba(0,0,0,.28)';
  const t: CSSProperties = { fontSize: 13.5, color: '#fff', textShadow: shadow, whiteSpace: 'nowrap' };
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: PT.w, height: MENU_H, display: 'flex', alignItems: 'center', padding: '0 14px', gap: 21 }}>
      <div style={{ display: 'flex', gap: 21, alignItems: 'center', opacity: desk * (1 - lp * 0.0) }}>
        <span style={{ ...t, fontSize: 16, marginLeft: 6, marginTop: -2 }}>{''}</span>
        <span style={{ ...t, fontWeight: 700 }}>{app}</span>
        {menus.slice(0, app === '访达' ? 5 : 7).map((m) => <span key={m} style={{ ...t, fontFamily: CJK }}>{m}</span>)}
      </div>
      <div style={{ marginLeft: 'auto', display: 'flex', gap: 17, alignItems: 'center', filter: 'drop-shadow(0 0 3px rgba(0,0,0,.3))' }}>
        <Battery size={25} />
        <Wifi size={17} />
        <Search size={15} />
        <ControlCenter size={16} />
        <span style={{ ...t, fontFamily: CJK, fontVariantNumeric: 'tabular-nums', opacity: desk }}>10月4日 周日 21:41</span>
      </div>
    </div>
  );
}

// ---- 锁屏 ----
function LockScreen({ lock }: { lock: number }) {
  const up = 1 - lock;
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: lock }}>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(rgba(0,0,0,.18),rgba(0,0,0,0) 40%,rgba(0,0,0,.25))' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 100 - up * 40, textAlign: 'center', color: 'rgba(255,255,255,.86)', fontFamily: CJK, fontSize: 21, fontWeight: 600, letterSpacing: 0.4 }}>
        10月4日 星期日
      </div>
      <div
        style={{
          position: 'absolute', left: 0, right: 0, top: 118 - up * 60, textAlign: 'center', fontFamily: SFD, fontSize: 148, fontWeight: 700, letterSpacing: -3, lineHeight: 1,
          color: 'rgba(255,255,255,.80)', textShadow: '0 1px 0 rgba(255,255,255,.35), 0 8px 40px rgba(0,20,80,.35)', fontVariantNumeric: 'tabular-nums',
        }}
      >
        21:41
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 104 + up * 20, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
        <div style={{ width: 66, height: 66, borderRadius: '50%', overflow: 'hidden', boxShadow: '0 0 0 1.5px rgba(255,255,255,.3), 0 6px 18px rgba(0,0,0,.35)' }}>
          <Img src={PLATE.face} style={{ width: 150, height: 150, marginLeft: -42, marginTop: -26, objectFit: 'cover' }} />
        </div>
        <div style={{ color: '#fff', fontSize: 15, fontWeight: 600, textShadow: '0 1px 6px rgba(0,0,0,.4)' }}>Aaron</div>
      </div>
    </div>
  );
}

// ---- 窗口 ----
function Lights({ dim }: { dim?: boolean }) {
  const c = dim ? ['#5b5b5f', '#5b5b5f', '#5b5b5f'] : ['#ff5f57', '#febc2e', '#28c840'];
  return (
    <div style={{ position: 'absolute', left: 18, top: 18, display: 'flex', gap: 8 }}>
      {c.map((x, i) => <i key={i} style={{ width: 12.5, height: 12.5, borderRadius: '50%', background: x, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,.22)' }} />)}
    </div>
  );
}

function Win({ r, children, z, active, radius = 24 }: { r: { x: number; y: number; w: number; h: number }; children: ReactNode; z: number; active?: boolean; radius?: number }) {
  return (
    <div
      style={{
        position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h, zIndex: z, borderRadius: radius, overflow: 'hidden', background: '#1c1c1e',
        boxShadow: `0 0 0 0.5px rgba(0,0,0,.9), inset 0 0 0 0.5px rgba(255,255,255,.16), 0 ${active ? 26 : 14}px ${active ? 70 : 40}px rgba(0,0,0,${active ? 0.55 : 0.4})`,
      }}
    >
      {children}
      <Lights dim={!active} />
    </div>
  );
}

const glassBtn: CSSProperties = {
  height: 30, borderRadius: 15, background: 'rgba(255,255,255,.08)', boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,.14), 0 1px 3px rgba(0,0,0,.25)',
  display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'rgba(255,255,255,.85)', fontSize: 14,
};

function Windows({ f }: { f: number }) {
  const g = spring(f, GLIDE_AT, 0.88, 0.42);
  const w1 = { x: mix(W1.x, LEFT.x, g), y: mix(W1.y, LEFT.y, g), w: mix(W1.w, LEFT.w, g), h: mix(W1.h, LEFT.h, g) };
  return (
    <>
      <Win r={{ x: 1004, y: 150, w: 560, h: 470 }} z={1}><Notes /></Win>
      <Win r={{ x: 520, y: 540, w: 760, h: 420 }} z={2} radius={16}><Terminal f={f} /></Win>
      <Win r={w1} z={3} active><Browser w={w1.w} h={w1.h} /></Win>
    </>
  );
}

function Browser({ w, h }: { w: number; h: number }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#1c1c1e' }}>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 0, height: 52, background: 'linear-gradient(#2a2a2d,#232326)', boxShadow: 'inset 0 -0.5px 0 rgba(0,0,0,.6)' }}>
        <div style={{ ...glassBtn, position: 'absolute', left: 92, top: 11, width: 38 }}>
          <svg width={16} height={14} viewBox="0 0 16 14"><rect x={1} y={1} width={14} height={12} rx={2.5} fill="none" stroke="currentColor" strokeWidth={1.3} /><line x1={6} y1={1} x2={6} y2={13} stroke="currentColor" strokeWidth={1.3} /></svg>
        </div>
        <div style={{ ...glassBtn, position: 'absolute', left: 140, top: 11, width: 66, justifyContent: 'space-around', fontSize: 17 }}><span>‹</span><span style={{ opacity: 0.4 }}>›</span></div>
        <div style={{ ...glassBtn, position: 'absolute', left: '50%', top: 11, width: Math.min(420, w * 0.44), transform: 'translateX(-50%)', fontSize: 13.5, gap: 6 }}>
          <svg width={10} height={12} viewBox="0 0 10 12"><path d="M 2.5 5 V 3.6 A 2.5 2.5 0 0 1 7.5 3.6 V 5" fill="none" stroke="currentColor" strokeWidth={1.3} /><rect x={1.2} y={5} width={7.6} height={6} rx={1.4} fill="currentColor" /></svg>
          <span>sspai.com</span>
        </div>
        <div style={{ ...glassBtn, position: 'absolute', right: 16, top: 11, width: 104, justifyContent: 'space-around', fontSize: 18 }}><span>⇪</span><span>+</span><span>⧉</span></div>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 52, bottom: 0, overflow: 'hidden', background: '#141416' }}>
        <div style={{ width: Math.min(680, w - 80), margin: '0 auto', paddingTop: 34, fontFamily: CJK, color: '#e9e9ee' }}>
          <div style={{ fontSize: 13, color: '#d4643f', fontWeight: 600, letterSpacing: 1 }}>效率 · 深度</div>
          <div style={{ fontSize: 31, fontWeight: 700, lineHeight: 1.32, marginTop: 10 }}>刘海里的那块黑，终于有了用处</div>
          <div style={{ fontSize: 13.5, color: '#8e8e93', marginTop: 12 }}>阿诺 · 2026 年 10 月 4 日 · 8 分钟读完</div>
          <div style={{ height: Math.min(260, h * 0.36), marginTop: 22, borderRadius: 14, overflow: 'hidden', position: 'relative' }}>
            <Img src={PLATE.wall} style={{ width: '100%', height: 560, objectFit: 'cover', marginTop: -160 }} />
          </div>
          <p style={{ fontSize: 16, lineHeight: 1.75, color: '#c7c7cc', marginTop: 22 }}>
            换到 MacBook 的第一周，我总觉得屏幕顶上缺了一块。后来我发现，缺的那一块正是整台电脑最安静的地方：它不抢焦点，只在我需要的时候开口。
          </p>
          <p style={{ fontSize: 16, lineHeight: 1.75, color: '#c7c7cc' }}>
            打开盖子它就认出我；我不想出声的时候，它读得懂我的嘴型；我点一下头，它就照做。
          </p>
        </div>
      </div>
    </div>
  );
}

function Notes() {
  const rows = [['周日', '21:12', '把启动台改成从刘海打开'], ['周六', '18:40', '车上听完那集播客'], ['周五', '23:05', '番茄钟：专注 25 分钟']];
  return (
    <div style={{ position: 'absolute', inset: 0, display: 'flex', fontFamily: CJK }}>
      <div style={{ width: 200, background: 'rgba(40,40,44,.96)', paddingTop: 52, boxShadow: 'inset -0.5px 0 0 rgba(0,0,0,.6)' }}>
        {rows.map(([d, t, s], i) => (
          <div key={i} style={{ margin: '0 8px 4px', padding: '9px 12px', borderRadius: 10, background: i ? 'transparent' : 'rgba(255,214,10,.85)', color: i ? '#e5e5ea' : '#1c1c1e' }}>
            <div style={{ fontSize: 13, fontWeight: 650, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s}</div>
            <div style={{ fontSize: 11.5, opacity: 0.7, marginTop: 3 }}>{d} {t}</div>
          </div>
        ))}
      </div>
      <div style={{ flex: 1, padding: '54px 26px 0', color: '#e5e5ea', background: '#1e1e1e' }}>
        <div style={{ fontSize: 22, fontWeight: 700 }}>把启动台改成从刘海打开</div>
        <div style={{ fontSize: 14, lineHeight: 1.85, color: '#c7c7cc', marginTop: 12 }}>
          <div>· 点一下刘海：回到主屏幕</div>
          <div>· 图标从刘海里倒出来，收回时原路回去</div>
          <div>· 回到上一个 App，焦点不丢</div>
          <div style={{ color: '#8e8e93', marginTop: 10 }}>明天：在车上试一次</div>
        </div>
      </div>
    </div>
  );
}

const TERM = [
  ['#c0c0c8', '╭─ claude  ~/WindowShade'],
  ['#e5e5ea', '> 把收起窗口的动画改成弹簧，回弹不超过 0.2'],
  ['#8e8e93', ''],
  ['#d97757', '⏺ Read(prototype/App/Notch.swift)'],
  ['#8e8e93', '  ⎿  Read 2,312 lines'],
  ['#d97757', '⏺ Update(prototype/App/FlickMotion.swift)'],
  ['#8e8e93', '  ⎿  Updated with 12 additions and 4 removals'],
  ['#d97757', '⏺ Bash(./tests/run-silent-prep-tests.sh)'],
  ['#30d158', '  ⎿  42 passed, 0 failed'],
];
function Terminal({ f }: { f: number }) {
  const n = Math.min(TERM.length, 5 + Math.floor(Math.max(0, f - 150) / 40));
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#151517', padding: '50px 22px 0', fontFamily: MONO, fontSize: 13.2, lineHeight: 1.62 }}>
      <div style={{ position: 'absolute', top: 15, left: 0, right: 0, textAlign: 'center', fontFamily: SF, fontSize: 13, fontWeight: 600, color: '#9a9aa0' }}>claude — 120×32</div>
      {TERM.slice(0, n).map(([c, t], i) => <div key={i} style={{ color: c, whiteSpace: 'pre', fontFamily: `${MONO},${CJK}` }}>{t || ' '}</div>)}
      <div style={{ color: '#d97757', marginTop: 6, whiteSpace: 'pre', fontFamily: `${MONO},${CJK}` }}>{'✻ '}<span style={{ color: '#e5e5ea' }}>Thinking… </span><span style={{ color: '#8e8e93' }}>(esc to interrupt)</span></div>
    </div>
  );
}

// ---- 程序坞：液态玻璃 ----
function Dock() {
  const n = DOCK.length;
  const width = n * DOCK_ICON + (n - 1) * DOCK_GAP + 2 * DOCK_PAD + 14;
  const running = new Set(['finder', 'safari', 'notes', 'claude', 'cursor', 'messages']);
  return (
    <div
      style={{
        position: 'absolute', left: (PT.w - width) / 2, bottom: DOCK_BOTTOM, width, height: DOCK_H, borderRadius: 26,
        background: 'linear-gradient(rgba(255,255,255,.20),rgba(255,255,255,.10))', backdropFilter: 'blur(26px) saturate(170%)', WebkitBackdropFilter: 'blur(26px) saturate(170%)',
        boxShadow: 'inset 0 0.8px 0 rgba(255,255,255,.55), inset 0 0 0 0.6px rgba(255,255,255,.22), 0 10px 30px rgba(0,0,0,.28)',
        display: 'flex', alignItems: 'center', padding: `0 ${DOCK_PAD}px`, gap: DOCK_GAP,
      }}
    >
      {DOCK.map((k, i) => (
        <div key={k} style={{ position: 'relative', width: DOCK_ICON, height: DOCK_ICON, marginLeft: i === n - 1 ? 14 : 0 }}>
          <Img src={ICON[k]} style={{ width: DOCK_ICON, height: DOCK_ICON }} />
          {running.has(k) && <i style={{ position: 'absolute', left: DOCK_ICON / 2 - 2, bottom: -5.5, width: 4, height: 4, borderRadius: 2, background: 'rgba(255,255,255,.75)' }} />}
        </div>
      ))}
    </div>
  );
}

// ---- 启动台：图标从刘海里倒出来 ----
const COLS = 7, CELL_W = 182, CELL_H = 172, ICON_PT = 92;
const GRID_X = (PT.w - COLS * CELL_W) / 2, GRID_Y = 132;
const ORIGIN = { x: PT.w / 2, y: NOTCH_PT.h * 0.55 };

function launchpadBg(f: number) {
  if (f < LP_OPEN || f > LP_CLOSE + 60) return 0;
  return Math.min(smooth(seg(f, LP_OPEN, LP_OPEN + 24)), 1 - smooth(seg(f, LP_CLOSE + 8, LP_CLOSE + 40)));
}

function LaunchpadBack({ lp }: { lp: number }) {
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: lp }}>
      <Img src={PLATE.wall} style={{ position: 'absolute', left: -60, top: (PT.h - PT.w) / 2 - 60, width: PT.w + 120, height: PT.w + 120, objectFit: 'cover', filter: 'blur(34px) saturate(140%)' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,10,.30)' }} />
    </div>
  );
}

/** 每个图标从刘海出发的时间：离刘海越近越早，3 帧一档。 */
const ORDER = LAUNCH.map((_, i) => {
  const c = i % COLS, r = Math.floor(i / COLS);
  return Math.hypot(c - (COLS - 1) / 2, r * 1.15);
});

function iconPos(i: number) {
  const c = i % COLS, r = Math.floor(i / COLS);
  return { x: GRID_X + c * CELL_W + CELL_W / 2, y: GRID_Y + r * CELL_H + ICON_PT / 2 };
}

/** 0 在刘海里，1 在格子里。 */
export function iconProgress(f: number, i: number) {
  const d = ORDER[i];
  const go = spring(f, LP_OPEN + 4 + d * 4.2, 0.8, 0.6);
  const back = spring(f, LP_CLOSE + (5 - d) * 1.6, 1, 0.3);
  return f >= LP_CLOSE ? go * (1 - back) : go;
}

function Launchpad({ f }: { f: number }) {
  const bg = launchpadBg(f);
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <div style={{ position: 'absolute', left: (PT.w - 238) / 2, top: 64, width: 238, height: 30, borderRadius: 15, opacity: bg, background: 'rgba(255,255,255,.14)', boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,.3)', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, color: 'rgba(255,255,255,.62)', fontFamily: CJK, fontSize: 14 }}>
        <Search size={13} color="rgba(255,255,255,.62)" /> 搜索
      </div>
      {LAUNCH.map(([k, name], i) => {
        const p = iconProgress(f, i), pp = iconProgress(f - 1, i);
        if (p <= 0.001) return null;
        const to = iconPos(i);
        const x = mix(ORIGIN.x, to.x, p), y = mix(ORIGIN.y, to.y, p);
        const s = mix(0.16, 1, Math.min(1.04, p));
        const speed = Math.hypot(to.x - ORIGIN.x, to.y - ORIGIN.y) * Math.abs(p - pp);
        const blur = Math.min(5, speed * 0.16);
        const label = clamp01((p - 0.85) / 0.15);
        return (
          <div key={k} style={{ position: 'absolute', left: x - ICON_PT / 2, top: y - ICON_PT / 2, width: ICON_PT, height: ICON_PT, transform: `scale(${s})`, filter: blur > 0.3 ? `blur(${blur.toFixed(2)}px)` : undefined }}>
            <Img src={ICON[k]} style={{ width: ICON_PT, height: ICON_PT, filter: 'drop-shadow(0 4px 8px rgba(0,0,0,.25))' }} />
            <div style={{ position: 'absolute', top: ICON_PT + 8, left: -40, right: -40, textAlign: 'center', fontFamily: CJK, fontSize: 13.5, color: '#fff', opacity: label, textShadow: '0 1px 3px rgba(0,0,0,.5)', whiteSpace: 'nowrap' }}>{name}</div>
          </div>
        );
      })}
      <div style={{ position: 'absolute', left: 0, right: 0, top: 1030, display: 'flex', justifyContent: 'center', gap: 9, opacity: bg }}>
        <i style={{ width: 7, height: 7, borderRadius: 4, background: '#fff' }} />
        <i style={{ width: 7, height: 7, borderRadius: 4, background: 'rgba(255,255,255,.35)' }} />
      </div>
    </div>
  );
}

// ---- 左半屏的预览：读到「左半屏」之后出现，点头后窗口滑进去 ----
function Ghost({ f }: { f: number }) {
  const a = fade(f, 1440, GLIDE_AT + 30, 14, 24);
  if (a <= 0) return null;
  // 不用 opacity / transform：叠在窗口上的半透明层会让 Chrome 把下面那块画糊。
  const g = (1 - spring(f, 1440, 0.9, 0.4)) * 0.015;
  const r = { x: LEFT.x + LEFT.w * g, y: LEFT.y + LEFT.h * g, w: LEFT.w * (1 - 2 * g), h: LEFT.h * (1 - 2 * g) };
  return (
    <div
      style={{
        position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h, borderRadius: 24, zIndex: 5,
        background: `rgba(255,255,255,${(0.08 * a).toFixed(3)})`,
        boxShadow: `inset 0 0 0 1.5px rgba(255,255,255,${(0.55 * a).toFixed(3)}), 0 20px 50px rgba(0,0,0,${(0.3 * a).toFixed(3)})`,
      }}
    />
  );
}

// ---- 指针：点刘海开启动台，点空白收回；长按刘海开 CarPlay，在 CarPlay 里点下一首 ----
type K = [number, number, number];
const NOTCH_TIP: [number, number] = [PT.w / 2 + 6, 12];
const PATHS: { from: number; to: number; keys: K[]; press: number[]; hold?: [number, number] }[] = [
  { from: 430, to: 1000, keys: [[430, 1180, 760], [500, ...NOTCH_TIP], [700, ...NOTCH_TIP], [800, 1250, 640], [900, 1300, 1012], [970, 1300, 1012]], press: [510, 956] },
  {
    from: 2180, to: 2860,
    keys: [[2180, 1120, 520], [2226, ...NOTCH_TIP], [2300, ...NOTCH_TIP], [2400, NEXT_BTN.x - 4, NEXT_BTN.y - 6], [2500, NEXT_BTN.x - 4, NEXT_BTN.y - 6], [2600, 1180, 760], [2860, 1180, 760]],
    press: [CP_NEXT], hold: [2232, 2268],
  },
];

function Cursor({ f }: { f: number }) {
  const P = PATHS.find((p) => f >= p.from && f <= p.to);
  if (!P) return null;
  const { keys } = P;
  let x = keys[0][1], y = keys[0][2];
  for (let i = 0; i < keys.length - 1; i++) {
    const [f0, x0, y0] = keys[i], [f1, x1, y1] = keys[i + 1];
    if (f >= f0 && f <= f1) { const p = smooth(seg(f, f0, f1)); x = mix(x0, x1, p); y = mix(y0, y1, p); }
  }
  if (f > keys[keys.length - 1][0]) { x = keys[keys.length - 1][1]; y = keys[keys.length - 1][2]; }
  const held = P.hold ? Math.min(seg(f, P.hold[0], P.hold[0] + 5), 1 - seg(f, P.hold[1], P.hold[1] + 5)) : 0;
  const press = Math.max(held, ...P.press.map((t) => 1 - Math.abs(f - t) / 6), 0);
  const a = fade(f, P.from, P.to, 10, 12);
  const ring = P.hold ? seg(f, P.hold[0], P.hold[1]) : 0;
  const ringA = P.hold ? fade(f, P.hold[0], P.hold[1] + 8, 4, 8) : 0;
  return (
    <div style={{ position: 'absolute', left: x, top: y, zIndex: 50 }}>
      {ringA > 0 && (
        <svg width={44} height={44} viewBox="0 0 44 44" style={{ position: 'absolute', left: -22, top: -22, overflow: 'visible' }}>
          <circle cx={22} cy={22} r={17} fill="none" stroke={`rgba(255,255,255,${(0.25 * ringA).toFixed(3)})`} strokeWidth={3} />
          <circle cx={22} cy={22} r={17} fill="none" stroke={`rgba(255,255,255,${(0.95 * ringA).toFixed(3)})`} strokeWidth={3} strokeLinecap="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - ring} transform="rotate(-90 22 22)" />
        </svg>
      )}
      <div style={{ opacity: a, transform: `scale(${1 - press * 0.12})`, transformOrigin: '0 0' }}>
        <Pointer size={17} />
      </div>
    </div>
  );
}
