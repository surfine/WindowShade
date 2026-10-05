// 一块屏上的 macOS Golden Gate，单位是这台机器的点。屏幕里发生什么全看帧号。
// Air 有实体刘海：岛从刘海长出来，指针进到刘海那块就被挡住（和真机一样）。
// Neo 没有刘海：岛是屏上画的，停着时不画；指针在岛上看得见。
import type { CSSProperties, ReactNode } from 'react';
import { Img } from 'remotion';
import { DOCK, ICON, LAUNCH, PLATE } from '../assets';
import { Browser, Notes, Terminal, Win } from '../Desktop';
import { Battery, Check, CJK, ControlCenter, Lock, Pointer, SF, SFD, Search, Wifi } from '../glyphs';
import { clamp01, mix, seg, smooth } from '../time';
import { LIP_TEXT, T } from './cues';
import { islandRect } from './island';
import { MACHINES, type MachineId } from './machines';
import { HOLE, SCREEN, capsuleD, fusedIslandD } from './notchPath';
import { motion } from './springs';

const RED = '#FF6B5E', GREEN = '#5FD38A';
type R4 = { x: number; y: number; w: number; h: number };

const LAYOUT: Record<MachineId, { browser: R4; notes: R4; term: R4; chat: R4 }> = {
  neo: { browser: { x: 300, y: 70, w: 720, h: 560 }, notes: { x: 820, y: 110, w: 540, h: 420 }, term: { x: 70, y: 420, w: 620, h: 350 }, chat: { x: 960, y: 300, w: 400, h: 470 } },
  air: { browser: { x: 380, y: 92, w: 880, h: 680 }, notes: { x: 1010, y: 150, w: 620, h: 520 }, term: { x: 90, y: 520, w: 760, h: 430 }, chat: { x: 1180, y: 380, w: 440, h: 520 } },
};

// ---- 状态 ----
/** 1 是锁屏。 */
function lockedAt(m: MachineId, f: number) {
  // 片尾双机：硬切后再是桌面，不在同机连续镜头里叠化自解锁（审片 C10-03）。
  if (f >= 3298) return 0;
  if (m === 'neo') return 1 - smooth(seg(f, T.unlock, T.unlock + 36));
  // Air：倒数结束锁上，并停在锁屏上直到硬切片尾（片尾第一帧不得带锁屏钟）。
  return f < 3184 ? 0 : smooth(seg(f, 3184, 3214));
}
/** Neo 醒来前屏幕是黑的。 */
const dark = (m: MachineId, f: number) => (m === 'neo' && f < 400 ? 1 - smooth(seg(f, T.wake, T.wake + 70)) : 0);

export function ScreenView({ m, f, physicalNotch = false }: { m: MachineId; f: number; physicalNotch?: boolean }) {
  const M = MACHINES[m];
  const lock = lockedAt(m, f);
  const lp = m === 'air' ? lpBg(f) : 0;
  const desk = 1 - lock;
  const d = dark(m, f);
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: M.pt.w, height: M.pt.h, overflow: 'hidden', background: '#000', fontFamily: SF }}>
      <Img src={PLATE.wall} style={{ position: 'absolute', left: 0, top: (M.pt.h - M.pt.w) / 2, width: M.pt.w, height: M.pt.w, objectFit: 'cover', transform: `scale(${1 + lock * 0.04})` }} />
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(4,8,20,.22)' }} />
      {desk > 0.001 && (
        <div style={{ position: 'absolute', inset: 0, opacity: desk * (1 - lp), transform: `scale(${mix(1.025, 1, desk)})`, transformOrigin: '50% 45%' }}>
          <Windows m={m} f={f} />
          <Dock m={m} />
        </div>
      )}
      {m === 'neo' && <Ghost f={f} />}
      {lp > 0 && <Launchpad f={f} />}
      {lock > 0.001 && <LockScreen m={m} a={lock} f={f} />}
      <MenuBar m={m} desk={desk} />
      {m === 'air' && <Cursor m={m} f={f} physicalNotch={physicalNotch} />}
      <Island m={m} f={f} />
      {m === 'neo' && <Cursor m={m} f={f} physicalNotch={physicalNotch} />}
      {/* 展開島已蓋住洞；再疊硬體洞會挡住中央字（倒數「动一下就取消」）。 */}
      {M.notch && !physicalNotch && !islandCoversHole(m, f) && <HardwareNotch w={M.pt.w} n={M.notch} />}
      {d > 0 && <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: d }} />}
    </div>
  );
}

// ---- 窗口：Neo 上点头后浏览器滑到左半屏；番茄钟时聊天、桌面收进岛 ----
function tuckP(m: MachineId, f: number, delay: number, which: 'chat' | 'all') {
  if (m !== 'neo' || f < T.pomoHover) return 0;
  const inn = which === 'chat' ? motion(f, T.pomoTap + 6, 'settle') : motion(f, T.away + delay, 'settle');
  const out = motion(f, T.back + 4 + delay, 'flyOut');
  if (which === 'chat') return f < T.away ? inn : Math.max(f < T.back + 4 ? 1 : 1 - out, 0);
  return f < T.back + 4 ? inn : 1 - out;
}

function Tucked({ m, f, r, p, children }: { m: MachineId; f: number; r: R4; p: number; children: ReactNode }) {
  if (p >= 0.999) return null;
  const I = islandRect(m, f);
  const tx = I.x + I.w / 2 - (r.x + r.w / 2), ty = I.y + I.h / 2 - (r.y + r.h / 2);
  return <div style={{ position: 'absolute', inset: 0, transform: `translate(${tx * p}px, ${ty * p}px) scale(${1 - 0.92 * p})`, transformOrigin: `${r.x + r.w / 2}px ${r.y + r.h / 2}px`, opacity: 1 - smooth(clamp01(p * 1.25 - 0.2)) }}>{children}</div>;
}

function Windows({ m, f }: { m: MachineId; f: number }) {
  const Lt = LAYOUT[m], P = MACHINES[m].pt;
  const LEFT = { x: 8, y: P.menu + 8, w: P.w / 2 - 12, h: P.h - P.menu - 98 };
  // 片尾硬切后再铺桌面，不与锁屏同镜叠化。
  const endK = f >= 3300 ? motion(f, 3300, 'settle') : 0;
  // 解锁后短收一扇进胶囊，承担开头「窗口收进刘海」（审片 C10-05）。
  const openTuck = m === 'neo' && f >= 560 && f < 640 ? motion(f, 560, 'settle') : 0;
  const g = Math.max(m === 'neo' ? motion(f, T.glide, 'catch') : 0, endK);
  const b = Lt.browser;
  const br = { x: mix(b.x, LEFT.x, g), y: mix(b.y, LEFT.y, g), w: mix(b.w, LEFT.w, g), h: mix(b.h, LEFT.h, g) };
  const all = (k: number) => tuckP(m, f, k * 4, 'all');
  const side = 1 - endK;
  return (
    <>
      <div style={{ position: 'absolute', inset: 0, opacity: side }}>
        <Tucked m={m} f={f} r={Lt.notes} p={Math.max(all(2), openTuck)}><Win r={Lt.notes} z={1}><Notes /></Win></Tucked>
        <Tucked m={m} f={f} r={Lt.term} p={all(1)}><Win r={Lt.term} z={2} radius={16}><Terminal f={400} /></Win></Tucked>
        {m === 'neo' && <Tucked m={m} f={f} r={Lt.chat} p={Math.max(tuckP(m, f, 0, 'chat'), all(3))}><Win r={Lt.chat} z={4} active={f >= T.pomoHover}><Chat /></Win></Tucked>}
      </div>
      <Tucked m={m} f={f} r={br} p={all(0)}><Win r={br} z={3} active={!(m === 'neo' && f >= T.pomoHover && f < 3300)}><Browser w={br.w} h={br.h} /></Win></Tucked>
    </>
  );
}

function Chat() {
  const rows: [string, string, boolean][] = [['小周', '周末去爬山吗？', false], ['我', '好啊，几点出发', true], ['小周', '八点，地铁站见', false], ['小周', '记得带水', false]];
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#1e1e20', fontFamily: CJK }}>
      <div style={{ position: 'absolute', top: 14, left: 0, right: 0, textAlign: 'center', fontSize: 14, fontWeight: 600, color: '#d8d8dc' }}>微信 · 小周</div>
      <div style={{ position: 'absolute', top: 52, left: 18, right: 18, display: 'flex', flexDirection: 'column', gap: 14 }}>
        {rows.map(([who, t, me], i) => (
          <div key={i} style={{ display: 'flex', flexDirection: me ? 'row-reverse' : 'row', gap: 10, alignItems: 'flex-start' }}>
            <div style={{ width: 34, height: 34, borderRadius: 8, background: me ? '#4a6fa5' : '#8a6f4e', color: '#fff', fontSize: 15, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>{who === '我' ? 'A' : '周'}</div>
            <div style={{ padding: '8px 12px', borderRadius: 8, background: me ? '#3eb575' : '#2e2e31', color: me ? '#0b2a17' : '#e9e9ee', fontSize: 15, maxWidth: 240 }}>{t}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function Ghost({ f }: { f: number }) {
  const a = Math.min(smooth(seg(f, T.ok, T.ok + 12)), 1 - smooth(seg(f, T.glide + 28, T.glide + 36)));
  if (a <= 0) return null;
  const P = MACHINES.neo.pt;
  const L = { x: 8, y: P.menu + 8, w: P.w / 2 - 12, h: P.h - P.menu - 98 };
  return <div style={{ position: 'absolute', left: L.x, top: L.y, width: L.w, height: L.h, borderRadius: 22, zIndex: 5, background: `rgba(255,255,255,${(0.06 * a).toFixed(3)})`, boxShadow: `inset 0 0 0 1.5px rgba(255,255,255,${(0.45 * a).toFixed(3)})` }} />;
}

function MenuBar({ m, desk }: { m: MachineId; desk: number }) {
  const P = MACHINES[m].pt;
  const t: CSSProperties = { fontSize: 13, color: '#fff', textShadow: '0 0 6px rgba(0,0,0,.28)', whiteSpace: 'nowrap' };
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: P.w, height: P.menu, display: 'flex', alignItems: 'center', padding: '0 12px', gap: 19, zIndex: 20 }}>
      <div style={{ display: 'flex', gap: 19, alignItems: 'center', opacity: desk }}>
        <span style={{ ...t, fontSize: 15, marginLeft: 6, marginTop: -2 }}>{''}</span>
        <span style={{ ...t, fontWeight: 700 }}>Safari 浏览器</span>
        {['文件', '编辑', '显示', '历史记录', '书签', '窗口', '帮助'].map((x) => <span key={x} style={{ ...t, fontFamily: CJK }}>{x}</span>)}
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

function LockScreen({ m, a, f }: { m: MachineId; a: number; f: number }) {
  const k = MACHINES[m].pt.w / 1408;
  const up = 1 - a;
  const filling = m === 'neo' && f >= T.pwFill && f < T.unlock + 24;
  const n = filling ? Math.min(6, Math.floor((f - T.pwFill) / 6) + 1) : 0;
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: a }}>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(rgba(0,0,0,.18),rgba(0,0,0,0) 40%,rgba(0,0,0,.25))' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 118 * k - up * 30, textAlign: 'center', color: 'rgba(255,255,255,.86)', fontFamily: CJK, fontSize: 19 * k, fontWeight: 600 }}>10月4日 星期日</div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 142 * k - up * 50, textAlign: 'center', fontFamily: SFD, fontSize: 112 * k, fontWeight: 700, letterSpacing: -3, lineHeight: 1, color: 'rgba(255,255,255,.82)', fontVariantNumeric: 'tabular-nums' }}>21:41</div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 78 * k, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9 }}>
        <div style={{ width: 58 * k, height: 58 * k, borderRadius: '50%', background: 'linear-gradient(#9aa3b2,#6b7384)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontFamily: SFD, fontSize: 26 * k, fontWeight: 600, boxShadow: '0 0 0 1.5px rgba(255,255,255,.3)' }}>A</div>
        <div style={{ color: '#fff', fontSize: 14 * k, fontWeight: 600 }}>Aaron</div>
        <div style={{ marginTop: 4 * k, width: 196 * k, height: 36 * k, borderRadius: 18 * k, background: 'rgba(255,255,255,.22)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.28)', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 * k }}>
          {n > 0
            ? Array.from({ length: 6 }, (_, i) => <span key={i} style={{ width: 8 * k, height: 8 * k, borderRadius: '50%', background: '#fff', opacity: i < n ? 1 : 0.28 }} />)
            : <span style={{ fontFamily: CJK, fontSize: 14 * k, color: 'rgba(255,255,255,.78)' }}>输入密码</span>}
        </div>
      </div>
    </div>
  );
}

function Dock({ m }: { m: MachineId }) {
  const P = MACHINES[m].pt;
  const icon = m === 'air' ? 54 : 46, pad = 6, gap = 4;
  const n = DOCK.length, width = n * icon + (n - 1) * gap + 2 * pad;
  return (
    <div style={{ position: 'absolute', left: (P.w - width) / 2, bottom: 5, width, height: icon + 2 * pad, borderRadius: icon * 0.45, background: 'linear-gradient(rgba(255,255,255,.20),rgba(255,255,255,.10))', boxShadow: 'inset 0 0.8px 0 rgba(255,255,255,.55), inset 0 0 0 0.6px rgba(255,255,255,.22), 0 10px 30px rgba(0,0,0,.28)', display: 'flex', alignItems: 'center', padding: `0 ${pad}px`, gap }}>
      {DOCK.map((k) => <Img key={k} src={ICON[k]} style={{ width: icon, height: icon }} />)}
    </div>
  );
}

// ---- 启动台（Air）：图标从刘海里倒出来，原路收回 ----
const COLS = 7, CELL_W = 182, CELL_H = 172, ICON_PT = 92;
const GRID_X = (1710 - COLS * CELL_W) / 2, GRID_Y = 132;
const ORIGIN = { x: 1710 / 2, y: 16 };
const lpBg = (f: number) => (f < T.lpOpen || f > T.lpClose + 60 ? 0 : Math.min(smooth(seg(f, T.lpOpen, T.lpOpen + 24)), 1 - smooth(seg(f, T.lpClose + 8, T.lpClose + 40))));
const ORDER = LAUNCH.map((_, i) => Math.hypot((i % COLS) - (COLS - 1) / 2, Math.floor(i / COLS) * 1.15));
export function iconP(f: number, i: number) {
  const d = ORDER[i];
  const slot = Math.min(5, Math.round(d));
  const go = motion(f, T.lpOpen + 7 + slot * 2.4, 'expand');
  const back = motion(f, T.lpClose + 2 + slot * 2.4, 'flyOut');
  return f >= T.lpClose ? go * (1 - back) : go;
}
function Launchpad({ f }: { f: number }) {
  const bg = lpBg(f);
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <div style={{ position: 'absolute', inset: 0, opacity: bg }}>
        <Img src={PLATE.wall} style={{ position: 'absolute', left: -60, top: (1107 - 1710) / 2 - 60, width: 1830, height: 1830, objectFit: 'cover', filter: 'blur(34px) saturate(140%)' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,10,.30)' }} />
      </div>
      {LAUNCH.map(([k, name], i) => {
        const p = iconP(f, i);
        if (p <= 0.001) return null;
        const c = i % COLS, r = Math.floor(i / COLS);
        const to = { x: GRID_X + c * CELL_W + CELL_W / 2, y: GRID_Y + r * CELL_H + ICON_PT / 2 };
        return (
          <div key={k} style={{ position: 'absolute', left: mix(ORIGIN.x, to.x, p) - ICON_PT / 2, top: mix(ORIGIN.y, to.y, p) - ICON_PT / 2, width: ICON_PT, height: ICON_PT, transform: `scale(${mix(0.16, 1, Math.min(1.04, p))})` }}>
            <Img src={ICON[k]} style={{ width: ICON_PT, height: ICON_PT, filter: 'drop-shadow(0 4px 8px rgba(0,0,0,.25))' }} />
            <div style={{ position: 'absolute', top: ICON_PT + 8, left: -40, right: -40, textAlign: 'center', fontFamily: CJK, fontSize: 13.5, color: '#fff', opacity: clamp01((p - 0.85) / 0.15), whiteSpace: 'nowrap' }}>{name}</div>
          </div>
        );
      })}
    </div>
  );
}

// ---- 指针 ----
type K = [number, number, number];
const PATHS: Record<MachineId, { from: number; to: number; keys: K[]; press: number[] }[]> = {
  air: [{ from: T.curIn, to: 1030, keys: [[T.curIn, 1150, 640], [T.curNotch, 858, 8], [860, 858, 8], [960, 1250, 900], [1030, 1250, 900]], press: [T.tap, T.closeTap] }],
  neo: [
    { from: 2236, to: 2420, keys: [[2236, 1100, 420], [2300, 970, 62], [2350, 970, 62], [2420, 1120, 520]], press: [T.pomoTap] },
    { from: 2690, to: 2830, keys: [[2690, 1040, 560], [2748, 720, 480], [2830, 720, 480]], press: [T.back] },
  ],
};
export function cursorAt(m: MachineId, f: number) {
  const P = PATHS[m].find((p) => f >= p.from && f <= p.to);
  if (!P) return null;
  const k = P.keys;
  let x = k[0][1], y = k[0][2];
  for (let i = 0; i < k.length - 1; i++) {
    if (f >= k[i][0] && f <= k[i + 1][0]) {
      const e = Math.min(1, motion(f, k[i][0], 'glide'));
      x = mix(k[i][1], k[i + 1][1], e); y = mix(k[i][2], k[i + 1][2], e);
    }
  }
  if (f > k[k.length - 1][0]) { x = k[k.length - 1][1]; y = k[k.length - 1][2]; }
  const press = Math.max(0, ...P.press.map((t) => 1 - Math.abs(f - t) / 6));
  const a = Math.min(smooth(seg(f, P.from, P.from + 10)), 1 - smooth(seg(f, P.to - 12, P.to)));
  return { x, y, press, a };
}
/** 指针尖进了 Air 的实体刘海就整只拿掉：刘海是机身，不是能点的屏幕。 */
function inNotch(m: MachineId, x: number, y: number) {
  const n = MACHINES[m].notch;
  if (!n) return false;
  const x0 = (MACHINES[m].pt.w - n.w) / 2;
  return x >= x0 && x <= x0 + n.w && y < n.h;
}

function HardwareNotch({ w, n }: { w: number; n: { w: number; h: number; r: number } }) {
  return <div style={{ position: 'absolute', left: (w - n.w) / 2, top: 0, width: n.w, height: n.h, borderRadius: `0 0 ${n.r}px ${n.r}px`, background: '#000', zIndex: 80 }} />;
}

/** 島已比洞大時，黑島本身就是洞；不要再蓋一層硬體洞。 */
function islandCoversHole(m: MachineId, f: number) {
  if (m !== 'air' || !MACHINES.air.notch) return false;
  const r = islandRect(m, f);
  const n = MACHINES.air.notch;
  return r.w > n.w + 0.5 || r.h > n.h + 0.5;
}

function Cursor({ m, f, physicalNotch }: { m: MachineId; f: number; physicalNotch: boolean }) {
  const c = cursorAt(m, f);
  // 貼在實體網格上時，指針畫進劉海那一塊，由網格上的缺口把它擋住。
  if (!c || (!physicalNotch && inNotch(m, c.x, c.y))) return null;
  return (
    <div style={{ position: 'absolute', left: c.x, top: c.y, zIndex: m === 'neo' ? 50 : 25, opacity: c.a }}>
      {c.press > 0 && <div style={{ position: 'absolute', left: -28, top: -28, width: 56, height: 56, borderRadius: '50%', boxShadow: `0 0 0 3px rgba(255,255,255,${(0.85 * c.press).toFixed(3)})`, transform: `scale(${mix(0.55, 1.15, c.press)})` }} />}
      <div style={{ transform: `scale(${1 - c.press * 0.12})`, transformOrigin: '0 0' }}><Pointer size={17} /></div>
    </div>
  );
}

// ---- 岛 ----
// Air：黑就是網格的洞。靜止只畫洞的輪廓；展開從這條輪廓往下長，沒有第二顆膠囊、沒有描邊和影子。
// Neo：沒有硬體劉海，屏上只有一顆黑，同樣不描邊、不加影子。
// 排版對齊 WWDC23 10194：Compact 極窄貼洞；Expanded／半島環抱感測區、同心邊距、無大額頭。
function Island({ m, f }: { m: MachineId; f: number }) {
  const r = islandRect(m, f);
  if (m === 'air') {
    const grown = r.w > HOLE.w + 0.5 || r.h > HOLE.h + 0.5;
    const island = fusedIslandD(r.w, r.h, r.r, grown);
    return (
      <>
        <svg width={SCREEN.w} height={SCREEN.h} viewBox={`0 0 ${SCREEN.w} ${SCREEN.h}`} style={{ position: 'absolute', left: 0, top: 0, zIndex: 30, overflow: 'visible' }}>
          <path d={island.d} fill="#000" fillRule="nonzero" />
        </svg>
        <div style={{ position: 'absolute', left: island.box.x, top: island.box.y, width: island.box.w, height: island.box.h, zIndex: 31, overflow: 'hidden' }}>
          <IslandContent m={m} f={f} w={island.box.w} h={island.box.h} />
        </div>
      </>
    );
  }
  if (r.w < 0.5 || r.h < 0.5) return null;
  return (
    <>
      <svg width={MACHINES.neo.pt.w} height={MACHINES.neo.pt.h} viewBox={`0 0 ${MACHINES.neo.pt.w} ${MACHINES.neo.pt.h}`} style={{ position: 'absolute', left: 0, top: 0, zIndex: 30, overflow: 'visible' }}>
        <path d={capsuleD(r.x, r.y, r.w, r.h, r.r)} fill="#000" fillRule="nonzero" />
      </svg>
      <div style={{ position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h, zIndex: 31, overflow: 'hidden', borderRadius: r.r }}>
        <IslandContent m={m} f={f} w={r.w} h={r.h} />
      </div>
    </>
  );
}

const inWin = (f: number, a: number, b: number, fi = 8, fo = 6) => Math.min(smooth(seg(f, a, a + fi)), 1 - smooth(seg(f, b - fo, b)));

/** content-replace：淡入淡出 + 輕微縮放（10194 默認過渡的味道）。 */
function FadeIn({ a, children }: { a: number; children: ReactNode }) {
  if (a <= 0.001) return null;
  return <div style={{ position: 'absolute', inset: 0, opacity: a, transform: `scale(${0.94 + 0.06 * a})`, transformOrigin: '50% 40%' }}>{children}</div>;
}

/** Expanded／半島：洞高留給感測蓋板；內容緊貼洞下橫排同心（去額頭）。左右不畫在洞高裡——3D 蓋板會擋。 */
function Peninsula({ w, h, left, right, title, sub, accent = '#fff' }: { w: number; h: number; left: ReactNode; right?: ReactNode; title: string; sub: string; accent?: string }) {
  const holeH = HOLE.depth;
  const m = Math.max(12, Math.min(20, w * 0.04));
  const top = holeH + 4;
  const band = Math.max(40, h - top - 8);
  return (
    <div style={{ position: 'relative', width: w, height: h, fontFamily: CJK }}>
      <div style={{ position: 'absolute', left: m, right: m, top, height: band, display: 'flex', alignItems: 'center', gap: 12 }}>
        {left}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 22, fontWeight: 700, color: accent, lineHeight: 1.08, letterSpacing: 0.2 }}>{title}</div>
          <div style={{ fontSize: 14, fontWeight: 600, color: 'rgba(255,255,255,.72)', marginTop: 3, lineHeight: 1.08 }}>{sub}</div>
        </div>
        {right}
      </div>
    </div>
  );
}

function Tile({ children, color = '#1c1c1e', size = 40 }: { children: ReactNode; color?: string; size?: number }) {
  const r = Math.round(size * 0.32);
  return (
    <div style={{ width: size, height: size, borderRadius: r, background: color, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', color: '#fff', boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,.12)' }}>{children}</div>
  );
}

function CompactWings({ w, h, left, right }: { w: number; h: number; left: ReactNode; right: ReactNode }) {
  const holeW = HOLE.w;
  const wing = Math.max(28, (w - holeW) / 2);
  return (
    <div style={{ position: 'relative', width: w, height: h }}>
      <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: wing, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{left}</div>
      <div style={{ position: 'absolute', right: 0, top: 0, bottom: 0, width: wing, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{right}</div>
    </div>
  );
}

function SoftAlert({ icon, title, sub, accent = '#fff' }: { icon: ReactNode; title: string; sub: string; accent?: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, fontFamily: CJK, whiteSpace: 'nowrap', padding: '0 14px', height: '100%', boxSizing: 'border-box' }}>
      {icon}
      <div style={{ minWidth: 0 }}>
        <div style={{ fontSize: 20, fontWeight: 700, color: accent, lineHeight: 1.08 }}>{title}</div>
        <div style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,.7)', marginTop: 2, lineHeight: 1.08 }}>{sub}</div>
      </div>
    </div>
  );
}

function TypeLine({ children, size = 28 }: { children: ReactNode; size?: number }) {
  return <span style={{ fontFamily: CJK, fontSize: size, fontWeight: 700, color: '#fff', whiteSpace: 'nowrap', letterSpacing: 0.2 }}>{children}</span>;
}

function IslandContent({ m, f, w, h }: { m: MachineId; f: number; w: number; h: number }) {
  if (f >= 3300) {
    return (
      <FadeIn a={inWin(f, 3310, 3700, 12, 8)}>
        {m === 'air'
          ? <Peninsula w={w} h={h} left={<Tile color="#3a2a1a"><Bag size={22} /></Tile>} right={<span style={{ fontFamily: CJK, fontSize: 13, fontWeight: 700, color: '#ffb340' }}>即時</span>} title="外卖到了" sub="iPhone · 放在门口了" accent="#ffb340" />
          : <SoftAlert icon={<Tile color="#3a2a1a"><Bag size={22} /></Tile>} title="外卖到了" sub="iPhone · 放在门口了" accent="#ffb340" />}
      </FadeIn>
    );
  }
  if (m === 'neo') {
    if (f >= T.faceOn && f < T.unlock + 8) {
      const face = f >= T.faceOk ? 'ok' : 'wait';
      const phone = f >= T.phoneOk ? 'ok' : 'wait';
      return <FadeIn a={inWin(f, T.faceOn + 6, T.unlock + 8, 10, 8)}><div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}><Factors face={face} phone={phone} /></div></FadeIn>;
    }
    if (f >= 560 && f < 640) {
      return <FadeIn a={inWin(f, 562, 636, 8, 6)}><SoftAlert icon={<Tile color="#163524"><Check size={22} draw={1} /></Tile>} title="备忘录" sub="已收进刘海" accent="#5FD38A" /></FadeIn>;
    }
    if (f >= 1080 && f < T.ask + 6) {
      return (
        <FadeIn a={inWin(f, 1110, T.ask + 6, 11, 6)}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 5 }}>
            <TypeLine size={28}>等你确认</TypeLine>
            <span style={{ fontFamily: CJK, fontSize: 14, fontWeight: 600, color: 'rgba(255,255,255,.7)' }}>{LIP_TEXT}</span>
          </div>
        </FadeIn>
      );
    }
    if (f >= T.ask && f < T.rest + 10) {
      const ok = seg(f, T.ok, T.ok + 14);
      const done = ok > 0.5;
      return (
        <FadeIn a={inWin(f, T.ask, T.rest + 10, 10, 10)}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 5 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <TypeLine size={26}>{done ? '已确认 · 正在落位' : '等你确认'}</TypeLine>
              {ok > 0 && <Check size={30} draw={ok} />}
            </div>
            <span style={{ fontFamily: CJK, fontSize: 14, fontWeight: 600, color: 'rgba(255,255,255,.7)' }}>{done ? '左半屏' : '放到左半屏？'}</span>
          </div>
        </FadeIn>
      );
    }
    if (f >= T.ride && f < 1800) return <FadeIn a={inWin(f, T.ride + 6, 1810)}><SoftAlert icon={<Tile color="#1a2f4a"><Car size={22} /></Tile>} title="车快到了" sub="白色轿车 · 2 分钟" accent="#64D2FF" /></FadeIn>;
    if (f >= T.pomoHover && f < T.pomoTap + 4) return <FadeIn a={inWin(f, T.pomoHover, T.pomoTap + 4, 1, 4)}><PomoIdle press={Math.max(0, 1 - Math.abs(f - T.pomoTap) / 6)} /></FadeIn>;
    if (f >= T.pomoTap && f < T.restAlert + 4) {
      const ff = smooth(seg(f, T.ffA, T.ffB));
      const left = 1500 * (1 - ff * 0.9995);
      return <FadeIn a={inWin(f, T.pomoTap + 8, T.restAlert + 4, 10, 4)}><Compact color={RED} frac={1 - left / 1500} text={fmt(left)} /></FadeIn>;
    }
    if (f >= T.restAlert && f < T.away + 4) return <FadeIn a={inWin(f, T.restAlert + 6, T.away + 4, 10, 4)}><SoftAlert icon={<Tile color="#163524"><Cup size={22} /></Tile>} title="休息 5 分钟" sub="专注完成 · 今天第 3 个" accent={GREEN} /></FadeIn>;
    if (f >= T.away && f < T.back + 4) {
      const left = restLeft(f);
      return (
        <FadeIn a={inWin(f, T.away + 10, T.back + 4, 12, 4)}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 10, fontFamily: CJK }}>
            <div style={{ width: 132, height: 132, borderRadius: '50%', border: `6px solid ${GREEN}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span style={{ color: '#fff', fontFamily: SFD, fontSize: 28, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{fmtClock(left)}</span>
            </div>
            <span style={{ color: 'rgba(255,255,255,.82)', fontSize: 18, fontWeight: 600 }}>看看远处 · 点一下回来</span>
          </div>
        </FadeIn>
      );
    }
    if (f >= T.back && f < T.pomoPre + 4) {
      const left = restLeft(f);
      return <FadeIn a={inWin(f, T.back + 8, T.pomoPre + 4, 10, 4)}><Compact color={GREEN} frac={1 - left / 300} text={`休息 ${fmtClock(left)}`} /></FadeIn>;
    }
    return null;
  }
  // Air
  if (f >= T.listenPre && f < 1080) {
    return (
      <FadeIn a={inWin(f, T.listenPre + 10, 1100)}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}><TypeLine>看口型</TypeLine></div>
      </FadeIn>
    );
  }
  if (f >= 1800 && f < T.livePre + 4) {
    if (f >= T.rideOpen && f < T.rideClose + 4) {
      return (
        <FadeIn a={inWin(f, T.rideOpen + 6, T.rideClose + 4, 10, 4)}>
          <Peninsula w={w} h={h} left={<Tile color="#1a2f4a"><Car size={20} /></Tile>} right={<span style={{ fontFamily: CJK, fontSize: 15, fontWeight: 700, color: '#64D2FF', fontVariantNumeric: 'tabular-nums' }}>2 分</span>} title="车快到了" sub="iPhone · 还有 2 分钟" accent="#64D2FF" />
        </FadeIn>
      );
    }
    if (f >= T.foodOpen && f < T.foodClose + 4) {
      return (
        <FadeIn a={inWin(f, T.foodOpen + 6, T.foodClose + 4, 10, 4)}>
          <Peninsula w={w} h={h} left={<Tile color="#3a2a1a"><Bag size={20} /></Tile>} right={<span style={{ fontFamily: CJK, fontSize: 15, fontWeight: 700, color: '#ffb340' }}>到了</span>} title="外卖到了" sub="iPhone · 放在门口了" accent="#ffb340" />
        </FadeIn>
      );
    }
    const text = f < T.rideOpen ? '2 分' : f < T.foodOpen ? '1 分' : '到了';
    const a = f < T.rideOpen ? inWin(f, 1800, T.rideOpen + 2, 1, 4) : f < T.foodOpen ? inWin(f, T.rideClose + 10, T.foodOpen + 2, 10, 4) : inWin(f, T.foodClose + 10, T.livePre + 4, 10, 4);
    return (
      <FadeIn a={a}>
        <CompactWings w={w} h={h} left={<Car size={18} />} right={<span style={{ fontFamily: CJK, fontSize: 15, fontWeight: 700, color: '#fff', fontVariantNumeric: 'tabular-nums' }}>{text}</span>} />
      </FadeIn>
    );
  }
  if (f >= T.livePre && f < 2280) {
    return (
      <FadeIn a={inWin(f, T.livePre + 10, 2300)}>
        <Peninsula w={w} h={h} left={<Tile color="#2a1a1a"><TimerIcon size={20} /></Tile>} right={<span style={{ fontFamily: CJK, fontSize: 13, fontWeight: 700, color: RED }}>专注</span>} title="番茄钟" sub="专注 25 分钟" accent={RED} />
      </FadeIn>
    );
  }
  if (f >= 2880 && f < T.ticks[0] - 8) return null;
  if (f >= T.ticks[0] - 8 && f < T.lock - 4) {
    const n = Math.max(1, 3 - T.ticks.filter((t) => f >= t).length + 1);
    const holeW = HOLE.w;
    const wing = Math.max(96, (w - holeW) / 2);
    return (
      <FadeIn a={inWin(f, T.ticks[0] - 2, T.lock - 4, 8, 4)}>
        <div style={{ display: 'flex', width: '100%', height: '100%', alignItems: 'center', fontFamily: CJK }}>
          <div style={{ width: wing, height: '100%', display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-start', gap: 8, paddingLeft: 12, boxSizing: 'border-box' }}>
            <Lock size={18} />
            <span style={{ fontSize: 15, fontWeight: 700, color: '#fff', letterSpacing: '0.01em', whiteSpace: 'nowrap', lineHeight: 1 }}>动一下就取消</span>
          </div>
          <div style={{ width: holeW, height: '100%' }} />
          <div style={{ width: wing, height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', paddingRight: 10, boxSizing: 'border-box' }}>
            <span style={{ fontFamily: SFD, fontSize: 36, fontWeight: 700, color: '#fff', fontVariantNumeric: 'tabular-nums', lineHeight: 1 }}>{n}</span>
          </div>
        </div>
      </FadeIn>
    );
  }
  if (f >= T.lock - 12 && f < 3300) return null;
  return null;
}

const restLeft = (f: number) => Math.max(0, 299 - (f - T.away) / 60);
const fmt = (s: number) => (s > 90 ? `${Math.ceil(s / 60)} 分` : `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`);
const fmtClock = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;



function Factors({ face, phone }: { face: 'wait' | 'ok'; phone: 'wait' | 'ok' }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 28 }}>
      <Factor ok={face === 'ok'} kind="face" label="脸" />
      <Factor ok={phone === 'ok'} kind="phone" label="手机" />
    </div>
  );
}

function Factor({ ok, kind, label }: { ok: boolean; kind: 'face' | 'phone'; label: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <div style={{ width: 30, height: 30, borderRadius: 15, background: ok ? '#30D158' : 'rgba(255,255,255,.16)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
        {kind === 'face'
          ? <span style={{ width: 12, height: 12, borderRadius: 6, background: ok ? '#06210f' : '#fff' }} />
          : <span style={{ width: 10, height: 16, borderRadius: 3, boxShadow: `inset 0 0 0 1.6px ${ok ? '#06210f' : '#fff'}` }} />}
      </div>
      <span style={{ fontFamily: CJK, fontSize: 16, fontWeight: 650, color: ok ? '#fff' : 'rgba(255,255,255,.78)' }}>{label}</span>
    </div>
  );
}

function Compact({ color, frac, text }: { color: string; frac: number; text: string }) {
  const c = 2 * Math.PI * 6.5;
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', padding: '0 20px', fontFamily: CJK }}>
      <svg width={30} height={30} viewBox="0 0 16 16">
        <circle cx={8} cy={8} r={6.5} fill="none" stroke="rgba(255,255,255,.18)" strokeWidth={2.2} />
        <circle cx={8} cy={8} r={6.5} fill="none" stroke={color} strokeWidth={2.2} strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - clamp01(frac))} transform="rotate(-90 8 8)" />
      </svg>
      <span style={{ color: '#fff', fontSize: 19, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{text}</span>
    </div>
  );
}

function PomoIdle({ press }: { press: number }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%', padding: '0 22px' }}>
      <div style={{ display: 'flex', gap: 14 }}>
        {['#2a2a2e', '#2a2a2e', '#2a2a2e'].map((c, i) => <div key={i} style={{ width: 92, height: 59, borderRadius: 10, background: c, boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,.08)' }} />)}
      </div>
      <div style={{ width: 59, height: 59, borderRadius: 13, background: '#2a2a2e', border: '1.5px solid rgba(255,255,255,.25)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', transform: `scale(${1 - press * 0.08})` }}><TimerIcon /></div>
    </div>
  );
}

const sv = (size: number, d: ReactNode, stroke = true) => <svg width={size} height={size} viewBox="0 0 16 16" fill={stroke ? 'none' : 'currentColor'} stroke={stroke ? 'currentColor' : 'none'} strokeWidth={1.4} strokeLinecap="round" strokeLinejoin="round" style={{ color: 'inherit' }}>{d}</svg>;
const TimerIcon = ({ size = 30 }: { size?: number }) => <span style={{ color: '#fff', display: 'flex' }}>{sv(size, <><circle cx={8} cy={9} r={5.5} /><path d="M8 9V6M6.5 1.8h3" /></>)}</span>;
const Cup = ({ size = 28 }: { size?: number }) => sv(size, <><path d="M2.5 6h9v4a3 3 0 0 1-3 3h-3a3 3 0 0 1-3-3z" /><path d="M11.5 7h1a1.5 1.5 0 0 1 0 3h-1M1.5 14.5h12" /></>);
const Car = ({ size = 30 }: { size?: number }) => <span style={{ color: '#fff', display: 'flex' }}>{sv(size, <><path d="M2 10.5V8.6l1.4-3.3A1.6 1.6 0 0 1 4.9 4.3h6.2a1.6 1.6 0 0 1 1.5 1l1.4 3.3v1.9a.8.8 0 0 1-.8.8H2.8a.8.8 0 0 1-.8-.8z" /><path d="M2.3 8.4h11.4" /><circle cx={4.8} cy={11.4} r={1.1} /><circle cx={11.2} cy={11.4} r={1.1} /></>)}</span>;
const Bag = ({ size = 30 }: { size?: number }) => <span style={{ color: '#fff', display: 'flex' }}>{sv(size, <><path d="M3 5h10l-.8 9H3.8z" /><path d="M5.6 5V4a2.4 2.4 0 0 1 4.8 0v1" /></>)}</span>;
