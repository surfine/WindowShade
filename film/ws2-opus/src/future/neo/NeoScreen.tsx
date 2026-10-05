// Neo 屏幕上的 macOS Golden Gate（1408 × 881 点）。没有实体刘海：岛是画在屏幕上的，
// 停着时是菜单栏正中一颗胶囊（design-system §5.3），所以指针可以落在它上面，看得见。
// 脸、嘴、头都不画人：刷脸是系统的 Face ID 符号，读唇是一条线描的口型，点头是耳机在点。
import type { CSSProperties, ReactNode } from 'react';
import { Img } from 'remotion';
import { DOCK, ICON, LAUNCH, PLATE } from '../assets';
import { Browser, Notes, Terminal, Win } from '../Desktop';
import { AirPods, Battery, Check, CJK, ControlCenter, FaceGlyph, Lock, Pointer, SF, SFD, Search, Wifi } from '../glyphs';
import { clamp01, mix } from '../time';
import { NPT } from './geom';

export type IslandState =
  | { kind: 'rest' }
  | { kind: 'hover' }
  | { kind: 'face'; scan: number; ok: number; sweep: number }
  | { kind: 'lips'; open: number; text: string; caret: boolean }
  | { kind: 'nod'; tilt: number; ok: number }
  | { kind: 'lock' };

export type ScreenState = {
  lock: number;
  island: IslandState;
  launch?: number;
  cursor?: { x: number; y: number; press: number };
  ghost?: boolean;
};

const BLUE = '#0a84ff';

export function NeoScreen({ s }: { s: ScreenState }) {
  const desk = 1 - s.lock;
  const lp = s.launch ?? 0;
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: NPT.w, height: NPT.h, overflow: 'hidden', background: '#000', fontFamily: SF }}>
      <Img src={PLATE.wall} style={{ position: 'absolute', left: 0, top: (NPT.h - NPT.w) / 2, width: NPT.w, height: NPT.w, objectFit: 'cover' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(4,8,20,.22)' }} />
      {desk > 0 && (
        <div style={{ position: 'absolute', inset: 0, opacity: desk * (1 - lp) }}>
          <Win r={{ x: 800, y: 120, w: 540, h: 430 }} z={1}><Notes /></Win>
          <Win r={{ x: 70, y: 400, w: 640, h: 360 }} z={2} radius={16}><Terminal f={400} /></Win>
          <Win r={{ x: 300, y: 70, w: 720, h: 560 }} z={3} active><Browser w={720} h={560} /></Win>
          <Dock />
        </div>
      )}
      {s.ghost && <div style={{ position: 'absolute', left: 8, top: NPT.menu + 8, width: NPT.w / 2 - 12, height: NPT.h - NPT.menu - 98, borderRadius: 22, zIndex: 5, background: 'rgba(255,255,255,.08)', boxShadow: 'inset 0 0 0 1.5px rgba(255,255,255,.55), 0 20px 50px rgba(0,0,0,.3)' }} />}
      {lp > 0 && <Launchpad p={lp} />}
      {s.lock > 0 && <LockScreen a={s.lock} />}
      <MenuBar desk={desk} />
      <Island st={s.island} />
      {s.cursor && <Cursor {...s.cursor} />}
    </div>
  );
}

function MenuBar({ desk }: { desk: number }) {
  const t: CSSProperties = { fontSize: 13, color: '#fff', textShadow: '0 0 6px rgba(0,0,0,.28)', whiteSpace: 'nowrap' };
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: NPT.w, height: NPT.menu, display: 'flex', alignItems: 'center', padding: '0 12px', gap: 19, zIndex: 20 }}>
      <div style={{ display: 'flex', gap: 19, alignItems: 'center', opacity: desk }}>
        <span style={{ ...t, fontSize: 15, marginLeft: 6, marginTop: -2 }}>{''}</span>
        <span style={{ ...t, fontWeight: 700 }}>Safari 浏览器</span>
        {['文件', '编辑', '显示', '历史记录', '书签', '窗口', '帮助'].map((m) => <span key={m} style={{ ...t, fontFamily: CJK }}>{m}</span>)}
      </div>
      <div style={{ marginLeft: 'auto', display: 'flex', gap: 15, alignItems: 'center', filter: 'drop-shadow(0 0 3px rgba(0,0,0,.3))' }}>
        <Battery size={23} />
        <Wifi size={16} />
        <Search size={14} />
        <ControlCenter size={15} />
        <span style={{ ...t, fontFamily: CJK, fontVariantNumeric: 'tabular-nums', opacity: desk }}>10月4日 周日 21:41</span>
      </div>
    </div>
  );
}

function LockScreen({ a }: { a: number }) {
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: a }}>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(rgba(0,0,0,.18),rgba(0,0,0,0) 40%,rgba(0,0,0,.25))' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 84, textAlign: 'center', color: 'rgba(255,255,255,.86)', fontFamily: CJK, fontSize: 19, fontWeight: 600 }}>10月4日 星期日</div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 100, textAlign: 'center', fontFamily: SFD, fontSize: 124, fontWeight: 700, letterSpacing: -3, lineHeight: 1, color: 'rgba(255,255,255,.82)', fontVariantNumeric: 'tabular-nums' }}>21:41</div>
      {/* 头像用首字母，不放人像 */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 92, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9 }}>
        <div style={{ width: 58, height: 58, borderRadius: '50%', background: 'linear-gradient(#9aa3b2,#6b7384)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontFamily: SFD, fontSize: 26, fontWeight: 600, boxShadow: '0 0 0 1.5px rgba(255,255,255,.3)' }}>A</div>
        <div style={{ color: '#fff', fontSize: 14, fontWeight: 600 }}>Aaron</div>
      </div>
    </div>
  );
}

const DOCK_ICON = 46;
function Dock() {
  const n = DOCK.length, pad = 6, gap = 4;
  const width = n * DOCK_ICON + (n - 1) * gap + 2 * pad;
  return (
    <div style={{ position: 'absolute', left: (NPT.w - width) / 2, bottom: 5, width, height: DOCK_ICON + 2 * pad, borderRadius: 22, background: 'linear-gradient(rgba(255,255,255,.20),rgba(255,255,255,.10))', boxShadow: 'inset 0 0.8px 0 rgba(255,255,255,.55), inset 0 0 0 0.6px rgba(255,255,255,.22), 0 10px 30px rgba(0,0,0,.28)', display: 'flex', alignItems: 'center', padding: `0 ${pad}px`, gap }}>
      {DOCK.map((k) => <Img key={k} src={ICON[k]} style={{ width: DOCK_ICON, height: DOCK_ICON }} />)}
    </div>
  );
}

// ---- 岛 ----
const ISLAND = {
  rest: { w: 80, h: 18, r: 9 },
  hover: { w: 80, h: 18, r: 9 },
  face: { w: 132, h: 132, r: 40 },
  lips: { w: 400, h: 92, r: 32 },
  nod: { w: 400, h: 92, r: 32 },
  lock: { w: 132, h: 132, r: 40 },
};
const ISLAND_TOP = 3;
export const ISLAND_CENTER = { x: NPT.w / 2, y: ISLAND_TOP + ISLAND.rest.h / 2 };

function Island({ st }: { st: IslandState }) {
  // 停着时什么都不画：顶边干净；指针过来才浮出一颗胶囊。
  if (st.kind === 'rest') return null;
  const box = ISLAND[st.kind];
  return (
    <div style={{ position: 'absolute', left: (NPT.w - box.w) / 2, top: ISLAND_TOP, width: box.w, height: box.h, borderRadius: box.r, background: '#000', zIndex: 30, boxShadow: '0 0 0 0.5px rgba(255,255,255,.10), 0 10px 30px rgba(0,0,0,.35)', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {st.kind === 'face' && <FaceGlyph size={84} scan={st.scan} ok={st.ok} sweep={st.sweep} />}
      {st.kind === 'lock' && <Lock size={62} />}
      {st.kind === 'lips' && (
        <Row icon={<LipGlyph open={st.open} />} label="看口型">
          <Typed text={st.text} caret={st.caret} />
        </Row>
      )}
      {st.kind === 'nod' && (
        <Row icon={<NodGlyph tilt={st.tilt} ok={st.ok} />} label="点头确认，摇头取消">
          <span>放到左半屏？</span>
        </Row>
      )}
    </div>
  );
}

function Row({ icon, label, children }: { icon: ReactNode; label: string; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, width: '100%', padding: '0 18px 0 14px' }}>
      <div style={{ width: 66, height: 66, borderRadius: 20, background: '#141416', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>{icon}</div>
      <div style={{ fontFamily: CJK, color: '#fff', minWidth: 0 }}>
        <div style={{ fontSize: 13, color: '#8e8e93', fontWeight: 500 }}>{label}</div>
        <div style={{ fontSize: 24, fontWeight: 600, marginTop: 3, letterSpacing: 0.2 }}>{children}</div>
      </div>
    </div>
  );
}

function Typed({ text, caret }: { text: string; caret: boolean }) {
  return (
    <span>
      {text}
      <i style={{ display: 'inline-block', width: 2.5, height: 24, marginLeft: 3, verticalAlign: -4, background: BLUE, opacity: caret ? 1 : 0 }} />
    </span>
  );
}

/** 读唇：一条线描的口型（上唇、下唇、中缝），加一圈跟踪点。只有线，没有脸。 */
export function LipGlyph({ open, size = 50 }: { open: number; size?: number }) {
  const o = clamp01(open);
  const up = `M 8 30 C 20 ${23 - o * 3} 32 ${17 - o * 3} 43 ${21 - o * 2} Q 50 ${18 - o * 2} 57 ${21 - o * 2} C 68 ${17 - o * 3} 80 ${23 - o * 3} 92 30`;
  const mid = `M 14 30 C 30 ${30 - o * 4} 70 ${30 - o * 4} 86 30 C 70 ${31 + o * 9} 30 ${31 + o * 9} 14 30`;
  const low = `M 8 30 C 22 ${40 + o * 10} 36 ${45 + o * 12} 50 ${45 + o * 12} C 64 ${45 + o * 12} 78 ${40 + o * 10} 92 30`;
  const dots: [number, number][] = [
    [8, 30], [26, 21 - o * 3], [43, 21 - o * 2], [50, 19 - o * 2], [57, 21 - o * 2], [74, 21 - o * 3], [92, 30],
    [74, 41 + o * 11], [50, 45 + o * 12], [26, 41 + o * 11], [30, 30 - o * 3], [70, 30 - o * 3], [50, 31 + o * 7],
  ];
  return (
    <svg width={size} height={size * 0.6} viewBox="0 0 100 60" style={{ overflow: 'visible' }}>
      <path d={up} fill="none" stroke="#fff" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" />
      <path d={low} fill="none" stroke="#fff" strokeWidth={3} strokeLinecap="round" />
      <path d={mid} fill="rgba(10,132,255,.22)" stroke="rgba(255,255,255,.55)" strokeWidth={2} />
      {dots.map(([x, y], i) => <circle key={i} cx={x} cy={y} r={2.6} fill={BLUE} />)}
    </svg>
  );
}

/** 点头：耳机往下点，旁边一道上下的弧；确认后变成勾。 */
export function NodGlyph({ tilt, ok, size = 40 }: { tilt: number; ok: number; size?: number }) {
  if (ok > 0.5) return <Check size={size} draw={(ok - 0.5) * 2} />;
  return (
    <div style={{ position: 'relative', width: size, height: size }}>
      <AirPods size={size} tilt={tilt} />
      <svg width={14} height={34} viewBox="0 0 14 34" style={{ position: 'absolute', right: -16, top: 3 }}>
        <path d="M 4 3 Q 12 17 4 31" fill="none" stroke={BLUE} strokeWidth={2.4} strokeLinecap="round" />
        <path d="M 1 27 L 4 31 L 8.5 28.6" fill="none" stroke={BLUE} strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </div>
  );
}

// ---- 启动台：图标从岛里倒出来 ----
const COLS = 7, CELL_W = 150, CELL_H = 138, ICON_PT = 76, GRID_Y = 110;
const GRID_X = (NPT.w - COLS * CELL_W) / 2;

function Launchpad({ p }: { p: number }) {
  const bg = clamp01(p * 3);
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <div style={{ position: 'absolute', inset: 0, opacity: bg }}>
        <Img src={PLATE.wall} style={{ position: 'absolute', left: -60, top: (NPT.h - NPT.w) / 2 - 60, width: NPT.w + 120, height: NPT.w + 120, objectFit: 'cover', filter: 'blur(30px) saturate(140%)' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,10,.30)' }} />
      </div>
      {LAUNCH.map(([k, name], i) => {
        const c = i % COLS, r = Math.floor(i / COLS);
        const d = Math.hypot(c - (COLS - 1) / 2, r * 1.15);
        const q = clamp01((p - d * 0.07) / 0.55);
        if (q <= 0) return null;
        const e = 1 - Math.pow(1 - q, 3);
        const to = { x: GRID_X + c * CELL_W + CELL_W / 2, y: GRID_Y + r * CELL_H + ICON_PT / 2 };
        const x = mix(ISLAND_CENTER.x, to.x, e), y = mix(ISLAND_CENTER.y, to.y, e);
        return (
          <div key={k} style={{ position: 'absolute', left: x - ICON_PT / 2, top: y - ICON_PT / 2, width: ICON_PT, height: ICON_PT, transform: `scale(${mix(0.16, 1, e)})` }}>
            <Img src={ICON[k]} style={{ width: ICON_PT, height: ICON_PT, filter: 'drop-shadow(0 4px 8px rgba(0,0,0,.25))' }} />
            <div style={{ position: 'absolute', top: ICON_PT + 6, left: -40, right: -40, textAlign: 'center', fontFamily: CJK, fontSize: 12.5, color: '#fff', opacity: clamp01((e - 0.85) / 0.15), whiteSpace: 'nowrap' }}>{name}</div>
          </div>
        );
      })}
    </div>
  );
}

function Cursor({ x, y, press }: { x: number; y: number; press: number }) {
  return (
    <div style={{ position: 'absolute', left: x, top: y, zIndex: 50 }}>
      {press > 0 && <div style={{ position: 'absolute', left: -16, top: -16, width: 32, height: 32, borderRadius: '50%', boxShadow: `0 0 0 2px rgba(255,255,255,${0.7 * press})`, transform: `scale(${mix(0.6, 1.2, press)})` }} />}
      <div style={{ transform: `scale(${1 - press * 0.12})`, transformOrigin: '0 0' }}>
        <Pointer size={16} />
      </div>
    </div>
  );
}
