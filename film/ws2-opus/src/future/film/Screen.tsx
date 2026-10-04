// 一块屏上的 macOS Golden Gate，单位是这台机器的点。屏幕里发生什么全看帧号。
// Air 有实体刘海：岛从刘海长出来，指针进到刘海那块就被挡住（和真机一样）。
// Neo 没有刘海：岛是屏上画的，停着时不画；指针在岛上看得见。
import type { CSSProperties, ReactNode } from 'react';
import { Img } from 'remotion';
import { DOCK, ICON, LAUNCH, PLATE } from '../assets';
import { Browser, Notes, Terminal, Win } from '../Desktop';
import { AirPods, Battery, Check, CJK, ControlCenter, FaceGlyph, Lock, Pointer, SF, SFD, Search, Wifi } from '../glyphs';
import { LipGlyph } from '../neo/NeoScreen';
import { clamp01, mix, seg, smooth } from '../time';
import { LIP_TEXT, T } from './cues';
import { islandRect } from './island';
import { MACHINES, type MachineId } from './machines';
import { motion } from './springs';

const BLUE = '#0a84ff', RED = '#FF6B5E', GREEN = '#5FD38A';
type R4 = { x: number; y: number; w: number; h: number };

const LAYOUT: Record<MachineId, { browser: R4; notes: R4; term: R4; chat: R4 }> = {
  neo: { browser: { x: 300, y: 70, w: 720, h: 560 }, notes: { x: 820, y: 110, w: 540, h: 420 }, term: { x: 70, y: 420, w: 620, h: 350 }, chat: { x: 960, y: 300, w: 400, h: 470 } },
  air: { browser: { x: 380, y: 92, w: 880, h: 680 }, notes: { x: 1010, y: 150, w: 620, h: 520 }, term: { x: 90, y: 520, w: 760, h: 430 }, chat: { x: 1180, y: 380, w: 440, h: 520 } },
};

// ---- 状态 ----
/** 1 是锁屏。 */
function lockedAt(m: MachineId, f: number) {
  if (m === 'neo') return f >= 3240 ? 1 : 1 - smooth(seg(f, T.unlock, T.unlock + 36));
  return f < 3184 ? 0 : smooth(seg(f, 3184, 3214));
}
/** Neo 醒来前屏幕是黑的。 */
const dark = (m: MachineId, f: number) => (m === 'neo' && f < 400 ? 1 - smooth(seg(f, T.wake, T.wake + 70)) : 0);

export function ScreenView({ m, f }: { m: MachineId; f: number }) {
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
      {m === 'neo' && <Veil f={f} />}
      {m === 'neo' && <Ghost f={f} />}
      {lp > 0 && <Launchpad f={f} />}
      {lock > 0.001 && <LockScreen m={m} a={lock} />}
      <MenuBar m={m} desk={desk} />
      {m === 'air' && <Cursor m={m} f={f} />}
      <Island m={m} f={f} />
      {m === 'neo' && <Cursor m={m} f={f} />}
      {M.notch && <HardwareNotch w={M.pt.w} n={M.notch} />}
      {d > 0 && <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: d }} />}
    </div>
  );
}

// ---- 窗口：Neo 上点头后浏览器滑到左半屏；番茄钟时聊天、桌面收进岛 ----
function tuckP(m: MachineId, f: number, delay: number, which: 'chat' | 'all') {
  if (m !== 'neo' || f < T.pomoHover) return 0;
  const inn = which === 'chat' ? motion(f, T.pomoTap + 6, 'pull') : motion(f, T.away + delay, 'pull');
  const out = motion(f, T.back + 4 + delay, 'glide');
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
  const g = m === 'neo' ? motion(f, T.glide, 'glide') : 0;
  const b = Lt.browser;
  const br = { x: mix(b.x, LEFT.x, g), y: mix(b.y, LEFT.y, g), w: mix(b.w, LEFT.w, g), h: mix(b.h, LEFT.h, g) };
  const all = (k: number) => tuckP(m, f, k * 4, 'all');
  return (
    <>
      <Tucked m={m} f={f} r={Lt.notes} p={all(2)}><Win r={Lt.notes} z={1}><Notes /></Win></Tucked>
      <Tucked m={m} f={f} r={Lt.term} p={all(1)}><Win r={Lt.term} z={2} radius={16}><Terminal f={400} /></Win></Tucked>
      <Tucked m={m} f={f} r={br} p={all(0)}><Win r={br} z={3} active={!(m === 'neo' && f >= T.pomoHover)}><Browser w={br.w} h={br.h} /></Win></Tucked>
      {m === 'neo' && <Tucked m={m} f={f} r={Lt.chat} p={Math.max(tuckP(m, f, 0, 'chat'), all(3))}><Win r={Lt.chat} z={4} active={f >= T.pomoHover}><Chat /></Win></Tucked>}
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

function Veil({ f }: { f: number }) {
  const a = Math.min(smooth(seg(f, T.away, T.away + 30)), 1 - smooth(seg(f, T.back, T.back + 30)));
  return a > 0 ? <div style={{ position: 'absolute', inset: 0, background: `rgba(8,12,20,${(0.28 * a).toFixed(3)})` }} /> : null;
}

function Ghost({ f }: { f: number }) {
  const a = Math.min(smooth(seg(f, T.ghost, T.ghost + 14)), 1 - smooth(seg(f, T.glide + 20, T.glide + 44)));
  if (a <= 0) return null;
  const P = MACHINES.neo.pt;
  const g = (1 - motion(f, T.ghost, 'pop')) * 0.015;
  const L = { x: 8, y: P.menu + 8, w: P.w / 2 - 12, h: P.h - P.menu - 98 };
  return <div style={{ position: 'absolute', left: L.x + L.w * g, top: L.y + L.h * g, width: L.w * (1 - 2 * g), height: L.h * (1 - 2 * g), borderRadius: 22, zIndex: 5, background: `rgba(255,255,255,${(0.08 * a).toFixed(3)})`, boxShadow: `inset 0 0 0 1.5px rgba(255,255,255,${(0.55 * a).toFixed(3)}), 0 20px 50px rgba(0,0,0,${(0.3 * a).toFixed(3)})` }} />;
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

function LockScreen({ m, a }: { m: MachineId; a: number }) {
  const k = MACHINES[m].pt.w / 1408;
  const up = 1 - a;
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: a }}>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(rgba(0,0,0,.18),rgba(0,0,0,0) 40%,rgba(0,0,0,.25))' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 84 * k - up * 30, textAlign: 'center', color: 'rgba(255,255,255,.86)', fontFamily: CJK, fontSize: 19 * k, fontWeight: 600 }}>10月4日 星期日</div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 100 * k - up * 50, textAlign: 'center', fontFamily: SFD, fontSize: 124 * k, fontWeight: 700, letterSpacing: -3, lineHeight: 1, color: 'rgba(255,255,255,.82)', fontVariantNumeric: 'tabular-nums' }}>21:41</div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 92 * k, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9 }}>
        <div style={{ width: 58 * k, height: 58 * k, borderRadius: '50%', background: 'linear-gradient(#9aa3b2,#6b7384)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontFamily: SFD, fontSize: 26 * k, fontWeight: 600, boxShadow: '0 0 0 1.5px rgba(255,255,255,.3)' }}>A</div>
        <div style={{ color: '#fff', fontSize: 14 * k, fontWeight: 600 }}>Aaron</div>
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
  const go = motion(f, T.lpOpen + 4 + d * 4.2, 'bloom');
  const back = motion(f, T.lpClose + (5 - d) * 1.6, 'flyOut');
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
  air: [{ from: T.curIn, to: 1030, keys: [[T.curIn, 1150, 640], [T.curNotch, 858, 8], [800, 858, 8], [900, 1250, 900], [1030, 1250, 900]], press: [T.tap, T.closeTap] }],
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

function Cursor({ m, f }: { m: MachineId; f: number }) {
  const c = cursorAt(m, f);
  if (!c || inNotch(m, c.x, c.y)) return null;
  return (
    <div style={{ position: 'absolute', left: c.x, top: c.y, zIndex: m === 'neo' ? 50 : 25, opacity: c.a }}>
      {c.press > 0 && <div style={{ position: 'absolute', left: -16, top: -16, width: 32, height: 32, borderRadius: '50%', boxShadow: `0 0 0 2px rgba(255,255,255,${(0.7 * c.press).toFixed(3)})`, transform: `scale(${mix(0.6, 1.2, c.press)})` }} />}
      <div style={{ transform: `scale(${1 - c.press * 0.12})`, transformOrigin: '0 0' }}><Pointer size={17} /></div>
    </div>
  );
}

// ---- 岛 ----
function Island({ m, f }: { m: MachineId; f: number }) {
  const r = islandRect(m, f);
  if (r.w < 0.5 || r.h < 0.5) return null;
  const br = m === 'air' ? `0 0 ${r.r}px ${r.r}px` : `${r.r}px`;
  return (
    <div style={{ position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h, borderRadius: br, background: '#000', zIndex: 30, overflow: 'hidden', boxShadow: m === 'neo' ? '0 0 0 0.5px rgba(255,255,255,.10), 0 10px 30px rgba(0,0,0,.35)' : 'none' }}>
      <div style={{ position: 'absolute', left: '50%', top: '50%', width: 0, height: 0 }}>
        <IslandContent m={m} f={f} w={r.w} h={r.h} />
      </div>
    </div>
  );
}

const inWin = (f: number, a: number, b: number, fi = 8, fo = 6) => Math.min(smooth(seg(f, a, a + fi)), 1 - smooth(seg(f, b - fo, b)));

function Centered({ w, h, a, children }: { w: number; h: number; a: number; children: ReactNode }) {
  if (a <= 0.001) return null;
  return <div style={{ position: 'absolute', left: -w / 2, top: -h / 2, width: w, height: h, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: a }}>{children}</div>;
}

function Row({ icon, label, children }: { icon: ReactNode; label: string; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16, width: '100%', padding: '0 18px 0 14px' }}>
      <div style={{ width: 66, height: 66, borderRadius: 20, background: '#141416', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>{icon}</div>
      <div style={{ fontFamily: CJK, color: '#fff', minWidth: 0, whiteSpace: 'nowrap' }}>
        <div style={{ fontSize: 13, color: '#8e8e93', fontWeight: 500 }}>{label}</div>
        <div style={{ fontSize: 24, fontWeight: 600, marginTop: 3, letterSpacing: 0.2 }}>{children}</div>
      </div>
    </div>
  );
}

const mouthOpen = (f: number) => {
  const t = f - T.charAt;
  if (t < -10 || t > LIP_TEXT.length * T.charGap) return 0.12;
  const u = ((t % T.charGap) + T.charGap) % T.charGap / T.charGap;
  return 0.12 + 0.7 * Math.sin(u * Math.PI) ** 1.5;
};

function IslandContent({ m, f, w, h }: { m: MachineId; f: number; w: number; h: number }) {
  if (m === 'neo') {
    if (f >= T.faceOn && f < 600) {
      const ok = smooth(seg(f, T.faceOk, T.faceOk + 26));
      return <Centered w={w} h={h} a={inWin(f, T.faceOn + 8, 700)}><FaceGlyph size={84} scan={seg(f, T.faceOn + 4, T.faceOk - 10)} ok={ok} sweep={((f - T.faceOn) / 48) % 1} /></Centered>;
    }
    if (f >= 1080 && f < T.ask + 6) {
      const n = f < T.charAt ? 0 : Math.min(LIP_TEXT.length, Math.floor((f - T.charAt) / T.charGap) + 1);
      return <Centered w={400} h={92} a={inWin(f, 1080, T.ask + 6, 1, 6)}><Row icon={<LipGlyph open={mouthOpen(f)} />} label="看口型"><span>{LIP_TEXT.slice(0, n)}<i style={{ display: 'inline-block', width: 2.5, height: 24, marginLeft: 3, verticalAlign: -4, background: BLUE, opacity: Math.floor(f / 16) % 2 === 0 || n < LIP_TEXT.length ? 1 : 0 }} /></span></Row></Centered>;
    }
    if (f >= T.ask && f < T.rest + 10) {
      const nod = f > T.nodA && f < T.nodB ? 16 * Math.sin(((f - T.nodA) / (T.nodB - T.nodA)) * Math.PI * 2) ** 2 : 0;
      const ok = seg(f, T.ok, T.ok + 24);
      return <Centered w={400} h={92} a={inWin(f, T.ask, T.rest + 10, 10, 10)}><Row icon={ok > 0 ? <Check size={40} draw={ok} /> : <AirPods size={40} tilt={nod} />} label="点头确认，摇头取消"><span>放到左半屏？</span></Row></Centered>;
    }
    if (f >= T.ride && f < 1800) return <Centered w={w} h={h} a={inWin(f, T.ride + 6, 1810)}><Alert icon={<Car />} title="车快到了" sub="白色轿车 · 2 分钟" /></Centered>;
    if (f >= T.pomoHover && f < T.pomoTap + 4) return <Centered w={620} h={118} a={inWin(f, T.pomoHover, T.pomoTap + 4, 1, 4)}><PomoIdle press={Math.max(0, 1 - Math.abs(f - T.pomoTap) / 6)} /></Centered>;
    if (f >= T.pomoTap && f < T.restAlert + 4) {
      const ff = smooth(seg(f, T.ffA, T.ffB));
      const left = 1500 * (1 - ff * 0.9995);
      return <Centered w={w} h={h} a={inWin(f, T.pomoTap + 8, T.restAlert + 4, 10, 4)}><Compact color={RED} frac={1 - left / 1500} text={fmt(left)} /></Centered>;
    }
    if (f >= T.restAlert && f < T.away + 4) return <Centered w={w} h={h} a={inWin(f, T.restAlert + 6, T.away + 4, 10, 4)}><Alert icon={<Cup />} title="休息 5 分钟" sub="专注完成 · 今天第 3 个" color={GREEN} /></Centered>;
    if (f >= T.away && f < T.back + 4) {
      const left = 299 - Math.floor((f - T.away) / 60);
      const br = 0.5 + 0.5 * Math.sin(((f - T.away) / 330) * Math.PI * 2 - Math.PI / 2);
      return (
        <Centered w={w} h={h} a={inWin(f, T.away + 10, T.back + 4, 12, 4)}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, fontFamily: CJK }}>
            <div style={{ width: 150, height: 150, borderRadius: '50%', border: `7px solid ${GREEN}`, transform: `scale(${mix(0.86, 1, br)})`, opacity: mix(0.6, 1, br), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span style={{ color: '#fff', fontFamily: SFD, fontSize: 30, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{fmt(left)}</span>
            </div>
            <span style={{ color: 'rgba(255,255,255,.65)', fontSize: 16 }}>看看远处 · 点一下回来</span>
          </div>
        </Centered>
      );
    }
    if (f >= T.back && f < T.pomoPre + 4) return <Centered w={w} h={h} a={inWin(f, T.back + 8, T.pomoPre + 4, 10, 4)}><Compact color={GREEN} frac={0.06} text="4 分" /></Centered>;
    return null;
  }
  // Air
  if (f >= T.listenPre && f < 1080) return <Centered w={470} h={112} a={inWin(f, T.listenPre + 10, 1100)}><Row icon={<LipGlyph open={0.12} />} label="看口型"><span>{' '}</span></Row></Centered>;
  if (f >= 1800 && f < T.livePre + 4) {
    if (f >= T.rideOpen && f < T.rideClose + 4) return <Centered w={w} h={h} a={inWin(f, T.rideOpen + 6, T.rideClose + 4, 10, 4)}><Alert icon={<Car />} title="车快到了" sub="白色轿车 · 沪A·D3K21" /></Centered>;
    if (f >= T.foodOpen && f < T.foodClose + 4) return <Centered w={w} h={h} a={inWin(f, T.foodOpen + 6, T.foodClose + 4, 10, 4)}><Alert icon={<Bag />} title="外卖到了" sub="放在门口了" /></Centered>;
    const text = f < T.rideOpen ? '2 分钟' : f < T.foodOpen ? '1 分钟' : '到了';
    const a = f < T.rideOpen ? inWin(f, 1800, T.rideOpen + 2, 1, 4) : f < T.foodOpen ? inWin(f, T.rideClose + 10, T.foodOpen + 2, 10, 4) : inWin(f, T.foodClose + 10, T.livePre + 4, 10, 4);
    return <Centered w={w} h={h} a={a}><Wings notchW={MACHINES.air.notch!.w} w={w} left={<Car size={22} />} right={<span style={{ fontFamily: CJK, fontSize: 14, fontWeight: 600, color: '#fff' }}>{text}</span>} /></Centered>;
  }
  if (f >= T.livePre && f < 2280) return <Centered w={470} h={112} a={inWin(f, T.livePre + 10, 2300)}><Row icon={<TimerIcon />} label="番茄钟"><span>专注 25 分钟</span></Row></Centered>;
  if (f >= 2880 && f < T.ticks[0]) return <Centered w={w} h={h} a={inWin(f, 2880, T.ticks[0], 1, 8)}><div style={{ opacity: 0.55 }}><FaceGlyph size={124} scan={1} ok={0} sweep={((f - 2880) / 40) % 1} /></div></Centered>;
  if (f >= T.ticks[0] - 8 && f < T.lock - 4) {
    const n = 3 - T.ticks.filter((t) => f >= t).length + 1;
    return <Centered w={w} h={h} a={inWin(f, T.ticks[0] - 2, T.lock - 4, 8, 4)}><Wings notchW={MACHINES.air.notch!.w} w={w} left={<Lock size={18} />} right={<span style={{ fontFamily: SFD, fontSize: 17, fontWeight: 700, color: '#fff' }}>{Math.max(1, n)}</span>} /></Centered>;
  }
  if (f >= T.lock - 12 && f < 3250) return <Centered w={w} h={h} a={inWin(f, T.lock - 4, 3250, 8, 14)}><Lock size={74} open={1 - smooth(seg(f, T.lock, T.lock + 12))} /></Centered>;
  return null;
}

const fmt = (s: number) => (s > 60 ? `${Math.ceil(s / 60)} 分` : `${Math.floor(s / 60)}:${String(Math.ceil(s % 60)).padStart(2, '0')}`);

function Wings({ notchW, w, left, right }: { notchW: number; w: number; left: ReactNode; right: ReactNode }) {
  const wing = (w - notchW) / 2;
  return (
    <div style={{ position: 'relative', width: w, height: '100%' }}>
      <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: wing, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{left}</div>
      <div style={{ position: 'absolute', right: 0, top: 0, bottom: 0, width: wing, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{right}</div>
    </div>
  );
}

function Alert({ icon, title, sub, color = '#fff' }: { icon: ReactNode; title: string; sub: string; color?: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 14, fontFamily: CJK, whiteSpace: 'nowrap' }}>
      <div style={{ width: 52, height: 52, borderRadius: 16, background: '#1c1c1e', display: 'flex', alignItems: 'center', justifyContent: 'center', color }}>{icon}</div>
      <div>
        <div style={{ fontSize: 21, fontWeight: 600, color: '#fff' }}>{title}</div>
        <div style={{ fontSize: 14, color: '#8e8e93', marginTop: 2 }}>{sub}</div>
      </div>
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
