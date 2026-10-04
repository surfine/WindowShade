// 「它没有 Face ID」：一镜到底。Neo 和 15 英寸 Air 轮流出场，岛是串起整片的那个东西：
// 交接时镜头钻进岛里（岛长满画面），从另一台的岛里退出来。
import { AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { MUSIC_SRC } from '../beats';
import { CJK, SFD } from '../glyphs';
import { seg, smooth } from '../time';
import { Body } from './Body';
import { camAt, holding, P0, PLACE, project, sp, U0, worldTransform, type CamState } from './camera';
import { CHAR_RATE, FPS, GROW, HANDS, LINES, segAt, SHRINK, T } from './cues';
import { islandAt, islandRect } from './island';
import { MACHINES, type MachineId } from './machines';
import { iconP, ScreenView } from './Screen';
import { motion } from './springs';

const SHUTTER = 0.5, MAX_SAMPLES = 8;

const ledOn = (m: MachineId, f: number) => (m === 'neo' ? f < T.faceOk + 30 || (f >= 1080 && f < T.ask) : f >= 2880 && f < T.lock);

function machinesAt(f: number): MachineId[] {
  const s = segAt(f);
  return s.m === 'both' ? ['neo', 'air'] : [s.m];
}

function World({ f, W, H }: { f: number; W: number; H: number }) {
  const cam = camAt(f);
  const end = segAt(f).m === 'both';
  return (
    <AbsoluteFill style={{ perspective: P0 * cam.zoom, perspectiveOrigin: '50% 50%' }}>
      <div style={{ position: 'absolute', left: W / 2, top: H / 2, width: 0, height: 0, transformStyle: 'preserve-3d', transform: worldTransform(cam) }}>
        {machinesAt(f).map((m) => (
          <Body key={m} M={MACHINES[m]} U={U0 * cam.zoom} at={end ? PLACE[m] : [0, 0, 0]} led={ledOn(m, f)} screen={<ScreenView m={m} f={f} />} />
        ))}
      </div>
    </AbsoluteFill>
  );
}

/** 岛在画面里的外框（像素）。 */
function islandFrame(m: MachineId, f: number, cam: CamState, W: number, H: number) {
  const r = islandRect(m, f);
  const w = Math.max(r.w, 8), h = Math.max(r.h, 4), x = r.x + r.w / 2 - w / 2;
  const pts = [sp(m, x, r.y), sp(m, x + w, r.y), sp(m, x, r.y + h), sp(m, x + w, r.y + h)].map((p) => project(cam, p, W, H));
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  return { cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, w: x1 - x0, h: y1 - y0, r: (r.r * (x1 - x0)) / w };
}

/** 交接：岛长满画面，再缩进下一台的岛。返回 null 表示这一帧不在交接里。 */
function handover(f: number, W: number, H: number) {
  const Hf = HANDS.find((h) => f >= h - GROW && f < h + SHRINK);
  if (Hf === undefined) return null;
  const cover = { cx: W / 2, cy: H / 2, w: W * 1.3, h: H * 1.3, r: 0 };
  const lerp = (a: typeof cover, b: typeof cover, p: number) => ({
    cx: a.cx + (b.cx - a.cx) * p, cy: a.cy + (b.cy - a.cy) * p,
    w: Math.exp(Math.log(a.w) + (Math.log(b.w) - Math.log(a.w)) * p), h: Math.exp(Math.log(a.h) + (Math.log(b.h) - Math.log(a.h)) * p),
    r: a.r + (b.r - a.r) * p,
  });
  if (f < Hf) {
    const m = segAt(Hf - 1).m as MachineId;
    const p = smooth(seg(f, Hf - GROW, Hf));
    return { rect: lerp(islandFrame(m, f, camAt(f), W, H), cover, p * p), a: 1 };
  }
  const m = segAt(Hf).m as MachineId;
  const q = Math.min(1, motion(f, Hf, 'calm') * 1.02);
  return { rect: lerp(cover, islandFrame(m, f, camAt(f), W, H), q), a: 1 - smooth(seg(f, Hf + SHRINK - 8, Hf + SHRINK)) };
}

/** 一帧里画面上最大的位移（像素）：屏幕四角 + 岛 + 启动台图标。 */
function travel(f: number, step: number, W: number, H: number) {
  const t0 = f - step * SHUTTER;
  if (segAt(t0) !== segAt(f)) return { m: 40, cam: 40 };
  const ms = machinesAt(f);
  const m = ms[ms.length - 1];
  const P = MACHINES[m].pt;
  const c0 = camAt(f), c1 = camAt(t0);
  const end = segAt(f).m === 'both';
  let cam = 0;
  for (const [x, y] of [[0, 0], [P.w, 0], [0, P.h], [P.w, P.h], [P.w / 2, 40]]) {
    const p = sp(m, x, y, end);
    const a = project(c0, p, W, H), b = project(c1, p, W, H);
    cam = Math.max(cam, Math.hypot(a[0] - b[0], a[1] - b[1]));
  }
  const k = (U0 * c0.zoom * MACHINES[m].screen.w) / P.w;
  const i0 = islandAt(f), i1 = islandAt(t0);
  let mv = Math.max(cam, (Math.abs(i0.w - i1.w) / 2 + Math.abs(i0.h - i1.h)) * k);
  if (m === 'air' && f > T.lpOpen && f < T.lpClose + 80) {
    let d = 0;
    for (let i = 0; i < 35; i += 3) d = Math.max(d, Math.abs(iconP(f, i) - iconP(t0, i)) * 700);
    mv = Math.max(mv, d * k);
  }
  const h0 = handover(f, W, H), h1 = handover(t0, W, H);
  if (h0 && h1) mv = Math.max(mv, Math.abs(h0.rect.w - h1.rect.w) / 2, Math.abs(h0.rect.cx - h1.rect.cx));
  return { m: mv, cam };
}

export function Film({ blind = false }: { blind?: boolean }) {
  const { width: W, height: H, fps } = useVideoConfig();
  const step = FPS / fps;
  const f = useCurrentFrame() * step;
  const { m, cam } = travel(f, step, W, H);
  const n = m < 1.5 ? 1 : Math.min(MAX_SAMPLES, 1 + Math.ceil((m * SHUTTER) / 3));
  const times = Array.from({ length: n }, (_, i) => (n === 1 ? f : f - step * SHUTTER * (i / (n - 1))));
  const gap = n > 1 ? (cam * SHUTTER) / (n - 1) : 0;
  const fill = gap > 2 ? `blur(${(gap * 0.5).toFixed(2)}px)` : undefined;
  const ho = handover(f, W, H);
  return (
    <AbsoluteFill style={{ background: 'radial-gradient(90% 80% at 50% 35%, #1d1f24 0%, #0d0e11 60%, #060607 100%)', overflow: 'hidden' }}>
      {blind && <style>{'*{color:transparent!important;-webkit-text-fill-color:transparent!important;text-shadow:none!important}'}</style>}
      {times.map((t, i) => (
        <AbsoluteFill key={i} style={{ opacity: i === 0 ? 1 : 1 / (i + 1), filter: fill }}>
          <World f={t} W={W} H={H} />
        </AbsoluteFill>
      ))}
      {ho && ho.a > 0 && (
        <div style={{ position: 'absolute', left: ho.rect.cx - ho.rect.w / 2, top: ho.rect.cy - ho.rect.h / 2, width: ho.rect.w, height: ho.rect.h, borderRadius: ho.rect.r, background: '#000', opacity: ho.a }} />
      )}
      <Grade f={f} still={holding(f)} />
      <Caption f={f} W={W} H={H} />
      <EndMark f={f} W={W} H={H} />
      <Audio src={staticFile(MUSIC_SRC)} />
    </AbsoluteFill>
  );
}

function Grade({ f, still }: { f: number; still: boolean }) {
  return (
    <>
      <AbsoluteFill style={{ background: 'radial-gradient(120% 90% at 50% 45%, transparent 58%, rgba(0,0,0,.4))', pointerEvents: 'none' }} />
      <AbsoluteFill style={{ opacity: 0.06, mixBlendMode: 'overlay', pointerEvents: 'none' }}>
        <svg width="100%" height="100%">
          <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={still ? 0 : Math.floor(f) % 23} /><feColorMatrix type="saturate" values="0" /></filter>
          <rect width="100%" height="100%" filter="url(#grain)" />
        </svg>
      </AbsoluteFill>
    </>
  );
}

/** 打字字幕：每 4 帧一个字，后面一个蓝色游标；打完游标再闪一会儿。 */
function Caption({ f, W, H }: { f: number; W: number; H: number }) {
  const line = LINES.find((l) => f >= l.from && f < l.to);
  if (!line) return null;
  const chars = [...line.text];
  const n = Math.min(chars.length, Math.floor((f - line.from) / CHAR_RATE) + 1);
  const done = f - line.from - chars.length * CHAR_RATE;
  const caret = done < 0 || (done < 60 && Math.floor(done / 15) % 2 === 0);
  const last = line === LINES[LINES.length - 1];
  const a = last ? 1 : 1 - smooth(seg(f, line.to - 10, line.to));
  const size = Math.round(H * 0.042);
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: H * (last ? 0.8 : 0.875) - size * 0.6, textAlign: 'center', fontFamily: CJK, fontWeight: 600, fontSize: size * (last ? 1.1 : 1), color: '#fff', letterSpacing: 1, opacity: a, textShadow: '0 2px 18px rgba(0,0,0,.7), 0 0 2px rgba(0,0,0,.5)', width: W }}>
      <span style={{ display: 'inline-block', padding: `${size * 0.22}px ${size * 0.6}px`, borderRadius: size, background: last ? 'transparent' : 'rgba(10,11,14,.62)', backdropFilter: last ? undefined : 'blur(18px)', WebkitBackdropFilter: last ? undefined : 'blur(18px)' }}>
        {chars.slice(0, n).join('')}
        <span style={{ display: 'inline-block', width: Math.max(2, size * 0.07), height: size * 0.95, marginLeft: size * 0.08, verticalAlign: -size * 0.12, background: '#0a84ff', opacity: caret ? 1 : 0 }} />
      </span>
    </div>
  );
}

function EndMark({ f, H }: { f: number; W: number; H: number }) {
  const p = motion(f, T.mark, 'settle');
  if (p <= 0) return null;
  const size = Math.round(H * 0.03);
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: H * 0.875 + (1 - p) * 16, display: 'flex', justifyContent: 'center', opacity: Math.min(1, p * 1.2) }}>
      <div style={{ padding: `${size * 0.3}px ${size * 0.9}px`, borderRadius: size, background: 'rgba(255,255,255,.1)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.18)', fontFamily: SFD, fontSize: size, fontWeight: 600, color: 'rgba(255,255,255,.88)', letterSpacing: 1 }}>WindowShade</div>
    </div>
  );
}

export const FilmLandscape = () => <Film />;
export const FilmBlind = () => <Film blind />;
