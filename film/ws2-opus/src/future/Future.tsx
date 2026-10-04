// 《它没有 Face ID》：一台普通的 MacBook，刷脸、启动台、读唇、点头、iPhone 的 CarPlay 开在 Mac 上、走开就锁。
// 跟着 120 BPM 的配乐剪：句子、推拉、面容 ID 认出、刘海展开都在拍上（beats.ts）。
// 一镜到底：每个段落之间都由刘海带过去——脸和耳朵两块实拍也是从岛上展开、再收回岛里。
import { AbsoluteFill, Audio, Img, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { LANDSCAPE, PORTRAIT, type Rect } from '../layout';
import { PLATE } from './assets';
import { HIT, MUSIC_SRC } from './beats';
import { CP_ESC } from './CarPlay';
import { Screen, launchpadTravel } from './Desktop';
import { CJK, SFD } from './glyphs';
import { Island, LIPS_T0, MOUTH, THUMB, islandBox, mouthOpen } from './Island';
import { MacBook } from './MacBook';
import { PT, islandAt } from './shape';
import { FPS, LINES, POCKET, clamp01, fade, handheld, inOut, mix, seg, smooth } from './time';

type FL = {
  W: number; H: number; screen: Rect;
  caption: { y: number; size: number };
  desk: string;
  /** 脸、耳朵两块板：图里那一点放到画面哪里。 */
  face: { size: number; x: number; y: number };
  ear: { w: number; x: number; y: number };
};

const LAND: FL = {
  W: 1920, H: 1080, screen: LANDSCAPE.screen,
  caption: { y: 1000, size: 54 },
  desk: PLATE.desk,
  face: { size: 1920, x: 0, y: -470 },
  ear: { w: 1920, x: 0, y: 0 },
};

/** 竖版按画面宽高摆：屏宽占画面九成（底座略出画，像镜头贴近桌面），屏幕中心在 0.40 高度。 */
function portrait(W: number, H: number): FL {
  const k = W / 1080;
  const sw = W * 0.9, sh = sw / (PORTRAIT.screen.w / PORTRAIT.screen.h);
  const cy = H * 0.4;
  return {
    W, H,
    screen: { x: (W - sw) / 2, y: cy - sh / 2, w: sw, h: sh },
    caption: { y: H * 0.68, size: 62 * k },
    desk: PLATE.deskP,
    face: { size: H, x: W / 2 - H * 0.5 + 0.0104 * H, y: 0 },
    ear: { w: (H * 16) / 9, x: -0.35 * H, y: 0 },
  };
}

// ---- 镜头：[帧, 推近倍数, 屏幕上的横向位置, 纵向位置]；WIDE 是整台机器 ----
// 追着主体走：每一下推拉都在主体落定之前到位；两个相同的键之间是定住的镜头（手持归零）。
const WIDE = -1;
type Key = [number, number, number, number];
const KEYS: Key[] = [
  [0, 5.0, 0.5, 0.108], [112, 5.5, 0.5, 0.108], [250, 1, WIDE, WIDE], [440, 1, WIDE, WIDE],
  // 点刘海：指针还在路上镜头就先到刘海；启动台铺开时退到能看全。
  [500, 2.0, 0.5, 0.26], [530, 2.0, 0.5, 0.26], [690, 1.34, 0.5, 0.44], [1000, 1.34, 0.5, 0.44],
  // 读唇：推到岛上那块小画面，钻进去；回来后退一步看左半屏的预览，再推回刘海听问话、钻进 AirPods。
  [1052, 3.6, 0.5, 0.115], [1400, 3.6, 0.5, 0.115], [1460, 1.42, 0.5, 0.46], [1510, 1.42, 0.5, 0.46],
  [1560, 2.9, 0.5, 0.1], [1740, 2.9, 0.5, 0.1], [1790, 1.32, 0.5, 0.46], [1940, 1.32, 0.5, 0.46],
  [1972, 2.7, 0.5, 0.1], [2150, 2.7, 0.5, 0.1],
  // 长按刘海（贴着刘海看）→ 落拍那一下往后拉，整块屏都是 CarPlay → 推到顶上那条问话 → 退回来 → Esc，退成整台机器。
  [2236, 2.9, 0.5, 0.1], [2304, 1.12, 0.5, 0.5], [2490, 1.12, 0.5, 0.5], [2540, 1.95, 0.355, 0.13], [2640, 1.95, 0.355, 0.13],
  [2700, 1.14, 0.5, 0.5], [2872, 1.14, 0.5, 0.5], [2950, 1, WIDE, WIDE],
  [3000, 1, WIDE, WIDE], [3044, 3.1, 0.5, 0.07], [3190, 3.1, 0.5, 0.07], [3290, 1, WIDE, WIDE], [3600, 1, WIDE, WIDE],
];
/** 落地轻震：[帧, 振幅（1080 高度下的像素）]。 */
const LANDINGS: [number, number][] = [[500, 2.2], [1052, 2.6], [2280, 5], [2540, 1.8], [3044, 2.2], [3184, 3.2]];
/** 快门 180°：一帧里取样的时间跨度（帧）。 */
const SHUTTER = 0.5;
const MAX_SAMPLES = 10;

const segAt = (f: number) => {
  let i = 0;
  while (i < KEYS.length - 1 && KEYS[i + 1][0] <= f) i++;
  return i;
};
const same = (a: Key, b: Key) => a[1] === b[1] && a[2] === b[2] && a[3] === b[3];

function camera(L: FL, f: number) {
  const { x, y, w, h } = L.screen;
  const at = (k: Key) => (k[2] === WIDE ? { z: k[1], fx: L.W / 2, fy: L.H / 2 } : { z: k[1], fx: x + k[2] * w, fy: y + k[3] * h });
  const i = segAt(f);
  const a = KEYS[i], b = KEYS[Math.min(i + 1, KEYS.length - 1)];
  if (a === b) return at(a);
  const p = inOut(seg(f, a[0], b[0]));
  const A = at(a), B = at(b);
  // 推拉：倍数按对数走，焦点跟着同一条曲线。
  const z = Math.exp(mix(Math.log(A.z), Math.log(B.z), p));
  const q = (z - A.z) / (B.z - A.z || 1);
  const t = Math.abs(B.z - A.z) > 0.01 ? clamp01(q) : p;
  return { z, fx: mix(A.fx, B.fx, t), fy: mix(A.fy, B.fy, t) };
}

/** 手持的量：镜头定住的段落里归零，进出各 16 帧过渡。 */
function handEnv(f: number) {
  const i = segAt(f);
  const a = KEYS[i], b = KEYS[Math.min(i + 1, KEYS.length - 1)];
  if (a === b || !same(a, b)) return 1;
  return 1 - Math.min(seg(f, a[0], a[0] + 16), 1 - seg(f, b[0] - 16, b[0]));
}

function shake(L: FL, f: number) {
  const s = Math.min(L.W, L.H) / 1080;
  let y = 0;
  for (const [a, amp] of LANDINGS) {
    const t = f - a;
    if (t >= 0 && t < 48) y += amp * Math.exp(-t / 8) * Math.sin(t * 0.95);
  }
  return { x: y * 0.35 * s, y: y * s };
}

/** 桌面这一层此刻的变换：世界坐标 → 画面坐标 = t + z · p。 */
function xform(L: FL, f: number) {
  const c = camera(L, f);
  const hh = handheld(f, handEnv(f));
  const sh = shake(L, f);
  return { z: c.z, tx: L.W / 2 - c.fx * c.z + hh.x + sh.x, ty: L.H / 2 - c.fy * c.z + hh.y + sh.y, r: hh.r };
}
type XF = ReturnType<typeof xform>;

/** 屏幕点坐标里的方块 → 画面坐标。 */
function ptBox(L: FL, X: XF, b: { x: number; y: number; w: number; h: number; r: number }) {
  const k = L.screen.w / PT.w;
  return { x: X.tx + X.z * (L.screen.x + b.x * k), y: X.ty + X.z * (L.screen.y + b.y * k), w: b.w * k * X.z, h: b.h * k * X.z, r: b.r * k * X.z };
}

// ---- 刘海里的镜头：从岛上的小方块展开到整个画面，再收回去 ----
type Kind = keyof typeof POCKET;
function pocketAt(L: FL, f: number) {
  for (const kind of Object.keys(POCKET) as Kind[]) {
    const P = POCKET[kind];
    if (f < P.open[0] || f >= P.close[1]) continue;
    const p = f < P.open[1] ? inOut(seg(f, P.open[0], P.open[1])) : f >= P.close[0] ? 1 - inOut(seg(f, P.close[0], P.close[1])) : 1;
    const src = ptBox(L, xform(L, f), islandBox(f, kind === 'face' ? 'thumb' : 'pods'));
    const box = { x: mix(src.x, 0, p), y: mix(src.y, 0, p), w: mix(src.w, L.W, p), h: mix(src.h, L.H, p), r: mix(src.r, 0, p) };
    return { kind, p, src, box };
  }
  return null;
}

/** 这一帧画面上最快的那一点走了多少像素（快门取样用）。 */
function travel(L: FL, f: number, step: number) {
  const a = xform(L, f), b = xform(L, f - step);
  let m = 0;
  for (const [X, Y] of [[0, 0], [L.W, 0], [0, L.H], [L.W, L.H], [L.W / 2, L.H * 0.1]]) {
    const wx = (X - a.tx) / a.z, wy = (Y - a.ty) / a.z;
    m = Math.max(m, Math.hypot(b.tx + b.z * wx - X, b.ty + b.z * wy - Y));
  }
  const cam = m;
  const k = (L.screen.w / PT.w) * a.z;
  const s0 = islandAt(f), s1 = islandAt(f - step);
  m = Math.max(m, (Math.abs(s0.w - s1.w) / 2 + Math.abs(s0.h - s1.h)) * k);
  m = Math.max(m, launchpadTravel(f - step, f) * k);
  const p0 = pocketAt(L, f), p1 = pocketAt(L, f - step);
  if (p0 && p1) {
    m = Math.max(m, Math.abs(p0.box.x - p1.box.x), Math.abs(p0.box.y - p1.box.y), Math.abs(p0.box.x + p0.box.w - p1.box.x - p1.box.w), Math.abs(p0.box.y + p0.box.h - p1.box.y - p1.box.h));
    if (p0.kind === 'ear') m = Math.max(m, Math.abs(earAngle(f) - earAngle(f - step)) * (Math.PI / 180) * L.H * 0.9);
  }
  return { m, cam };
}

export function Future({ tall = false, blind = false }: { tall?: boolean; blind?: boolean }) {
  const { width, height, fps } = useVideoConfig();
  const step = FPS / fps;
  const f = useCurrentFrame() * step;
  const L = tall ? portrait(width, height) : LAND;
  // 快门：一帧里按时间均匀取几次再平均（每层透明度 1/(i+1) 叠起来就是等权平均），走得快的帧才多取。
  const { m, cam } = travel(L, f, step);
  const n = m < 1.5 ? 1 : Math.min(MAX_SAMPLES, 1 + Math.ceil((m * SHUTTER) / 3));
  const times = Array.from({ length: n }, (_, i) => (n === 1 ? f : f - step * SHUTTER * (i / (n - 1))));
  // 镜头整体在走时，取样之间还空着的距离用每层一点模糊补上（重建滤波），不然是一串清楚的残影，不是拖影。
  // 只有岛或局部在动时不补：不动的地方不能跟着糊。
  const gap = n > 1 ? (cam * SHUTTER) / (n - 1) : 0;
  const fill = gap > 2 ? `blur(${(gap * 0.5).toFixed(2)}px)` : undefined;
  return (
    <AbsoluteFill style={{ background: '#000', overflow: 'hidden' }}>
      {blind && <style>{'*{color:transparent!important;-webkit-text-fill-color:transparent!important;text-shadow:none!important}'}</style>}
      {times.map((t, i) => (
        <AbsoluteFill key={i} style={{ opacity: i === 0 ? 1 : 1 / (i + 1), filter: fill }}>
          <World L={L} f={t} />
        </AbsoluteFill>
      ))}
      <Grade f={f} still={handEnv(f) === 0} />
      <Key L={L} f={f} />
      <Caption L={L} f={f} />
      <EndMark L={L} f={f} />
      <Audio src={staticFile(MUSIC_SRC)} />
    </AbsoluteFill>
  );
}

function World({ L, f }: { L: FL; f: number }) {
  const pk = pocketAt(L, f);
  return (
    <>
      {!(pk && pk.p >= 1) && <Desk L={L} f={f} />}
      {pk && <Pocket L={L} f={f} pk={pk} />}
    </>
  );
}

// ---- 桌上那台 MacBook ----
function Desk({ L, f }: { L: FL; f: number }) {
  const X = xform(L, f);
  // 背景更远：推得少、糊得多（景深，不是运动模糊）。
  const bz = Math.pow(X.z, 0.35);
  const bgBlur = Math.min(22, (X.z - 1) * 6);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ transform: `scale(${bz})`, transformOrigin: `${L.W / 2}px ${L.H * 0.45}px`, filter: `blur(${bgBlur.toFixed(2)}px) brightness(.9)` }}>
        <Img src={L.desk} style={{ width: L.W, height: L.H, objectFit: 'cover' }} />
      </AbsoluteFill>
      <AbsoluteFill style={{ transformOrigin: '0 0', transform: `translate(${X.tx}px, ${X.ty}px) scale(${X.z}) rotate(${X.r}deg)` }}>
        <MacBook screen={L.screen} glow={1} camOn={f < 112 || (f >= 1040 && f < 1330)}>
          <Screen f={f} />
          <Island f={f} />
        </MacBook>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

type Pk = NonNullable<ReturnType<typeof pocketAt>>;
function Pocket({ L, f, pk }: { L: FL; f: number; pk: Pk }) {
  const { box, src, p } = pk;
  // 镜头里那一点（嘴 / AirPods）在小方块里时对准方块中心，展开时回到它在整幅画面里的位置。
  let A: { x: number; y: number }, s0: number;
  if (pk.kind === 'face') {
    const S = L.face.size;
    A = { x: L.face.x + MOUTH.x * S, y: L.face.y + MOUTH.y * S };
    s0 = (src.w * THUMB.img) / THUMB.size / S;
  } else {
    const ez = earZoom(f - POCKET.ear.t0);
    const a0 = { x: L.ear.x + 0.352 * L.ear.w, y: L.ear.y + 0.486 * earH(L) };
    A = { x: L.W / 2 + (a0.x - L.W / 2) * ez, y: L.H / 2 + (a0.y - L.H / 2) * ez };
    s0 = (src.w * 0.8) / (0.09 * L.ear.w * ez);
  }
  const s = Math.exp(mix(Math.log(s0), 0, p));
  const cx = mix(box.x + box.w / 2, A.x, p), cy = mix(box.y + box.h / 2, A.y, p);
  const clip = `inset(${box.y}px ${L.W - box.x - box.w}px ${L.H - box.y - box.h}px ${box.x}px round ${box.r}px)`;
  return (
    <AbsoluteFill style={{ clipPath: clip, WebkitClipPath: clip, background: '#000' }}>
      <AbsoluteFill style={{ transformOrigin: '0 0', transform: `translate(${cx - A.x * s}px, ${cy - A.y * s}px) scale(${s})` }}>
        {pk.kind === 'face' ? <FaceShot L={L} f={f} /> : <EarShot L={L} f={f} />}
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

// ---- Mac 摄像头看到的你：嘴在动，字一个个读出来 ----
function FaceShot({ L, f }: { L: FL; f: number }) {
  const t = f - POCKET.face.t0;
  const z = mix(1, 1.14, smooth(seg(t, 0, 220)));
  const hh = handheld(f, 0.6 * smooth(seg(t, 0, 30)) * (1 - smooth(seg(t, 190, 210))));
  const S = L.face.size;
  const ox = L.face.x + MOUTH.x * S, oy = L.face.y + MOUTH.y * S;
  const o = mouthOpen((f - LIPS_T0) * 0.9);
  const chars = ['左', '半', '屏'];
  return (
    <AbsoluteFill style={{ transformOrigin: `${ox}px ${oy}px`, transform: `translate(${hh.x}px,${hh.y}px) scale(${z})` }}>
      <Img src={PLATE.face} style={{ position: 'absolute', left: L.face.x, top: L.face.y, width: S, height: S }} />
      {/* 嘴：同一块图在嘴的位置纵向拉开一点，中间压暗，像张嘴 */}
      <div style={{ position: 'absolute', left: ox - S * 0.07, top: oy - S * 0.03, width: S * 0.14, height: S * 0.06, overflow: 'hidden', borderRadius: '50%', WebkitMaskImage: 'radial-gradient(closest-side, #000 55%, transparent)', maskImage: 'radial-gradient(closest-side, #000 55%, transparent)' }}>
        <div style={{ position: 'absolute', left: -(ox - S * 0.07 - L.face.x), top: -(oy - S * 0.03 - L.face.y), width: S, height: S, transformOrigin: `${ox - L.face.x}px ${oy - L.face.y - S * 0.004}px`, transform: `scaleY(${1 + o * 0.22})` }}>
          <Img src={PLATE.face} style={{ width: S, height: S }} />
        </div>
        <div style={{ position: 'absolute', left: '28%', right: '28%', top: `${50 - o * 9}%`, height: `${o * 22}%`, borderRadius: '50%', background: 'rgba(25,8,8,.85)', filter: 'blur(2px)' }} />
      </div>
      {/* 嘴边的点：读唇看到的轮廓 */}
      <svg style={{ position: 'absolute', left: 0, top: 0, width: L.W, height: L.H, overflow: 'visible' }}>
        {Array.from({ length: 20 }, (_, i) => {
          const a = (i / 20) * Math.PI * 2;
          const rx = S * 0.062, up = Math.sin(a) < 0;
          const ry = up ? S * (0.016 + o * 0.006) : S * (0.016 + o * 0.022);
          const a0 = fade(t, 16 + i, 200);
          return <circle key={i} cx={ox + Math.cos(a) * rx} cy={oy + Math.sin(a) * ry} r={3.2} fill="#64d2ff" opacity={a0 * 0.9} style={{ filter: 'drop-shadow(0 0 4px rgba(100,210,255,.9))' }} />;
        })}
      </svg>
      <div style={{ position: 'absolute', left: ox - 300, width: 600, top: oy + S * 0.075, display: 'flex', justifyContent: 'center', gap: 12, fontFamily: CJK, fontSize: 64, fontWeight: 650, color: '#fff', textShadow: '0 4px 24px rgba(0,0,0,.6)' }}>
        {chars.map((c, i) => {
          const p = seg(t, 52 + i * 40, 66 + i * 40) * (1 - seg(t, 196, 206));
          return <span key={c} style={{ opacity: p, filter: `blur(${(1 - p) * 10}px)` }}>{c}</span>;
        })}
      </div>
    </AbsoluteFill>
  );
}

// ---- 戴着 AirPods 点一下头 ----
const earH = (L: FL) => Math.max((L.ear.w * 9) / 16, L.H);
const earZoom = (t: number) => mix(1.04, 1.1, smooth(seg(t, 0, 150)));
const nodCurve = (u: number) => (u <= 0 || u >= 1 ? 0 : Math.sin(u * Math.PI) ** 1.4);
function earAngle(f: number) {
  return 6.5 * nodCurve((f - POCKET.ear.t0 - 60) / 50);
}

function EarShot({ L, f }: { L: FL; f: number }) {
  const t = f - POCKET.ear.t0;
  const z = earZoom(t);
  const px = L.ear.x + L.ear.w * 0.3, py = L.H * 1.15;
  return (
    <AbsoluteFill style={{ transformOrigin: `${L.W / 2}px ${L.H / 2}px`, transform: `scale(${z})` }}>
      <div style={{ position: 'absolute', inset: 0, transformOrigin: `${px}px ${py}px`, transform: `rotate(${earAngle(f)}deg)` }}>
        <Img src={PLATE.ear} style={{ position: 'absolute', left: L.ear.x, top: L.ear.y, width: L.ear.w, height: earH(L), objectFit: 'cover' }} />
      </div>
    </AbsoluteFill>
  );
}

// ---- 调色、颗粒、暗角 ----
/** 定住的镜头里颗粒也不动：静止就是一帧不差的静止。 */
function Grade({ f, still }: { f: number; still: boolean }) {
  return (
    <>
      <AbsoluteFill style={{ background: 'radial-gradient(120% 90% at 50% 45%, transparent 55%, rgba(0,0,0,.42))', pointerEvents: 'none' }} />
      <AbsoluteFill style={{ opacity: 0.07, mixBlendMode: 'overlay', pointerEvents: 'none' }}>
        <svg width="100%" height="100%">
          <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={still ? 0 : Math.floor(f) % 23} /><feColorMatrix type="saturate" values="0" /></filter>
          <rect width="100%" height="100%" filter="url(#grain)" />
        </svg>
      </AbsoluteFill>
    </>
  );
}

function Caption({ L, f }: { L: FL; f: number }) {
  const line = LINES.find((l) => f >= l.from && f < l.to);
  if (!line) return null;
  const a = fade(f, line.from, line.to, 12, 6);
  const last = line === LINES[LINES.length - 1];
  const y = last ? L.caption.y - (L.W > L.H ? 18 : 0) : L.caption.y;
  return (
    <div
      style={{
        position: 'absolute', left: 0, right: 0, top: y - L.caption.size * 0.7, textAlign: 'center', fontFamily: CJK, fontWeight: 600,
        fontSize: L.caption.size * (last ? 1.12 : 1), color: '#fff', letterSpacing: 1, opacity: a, filter: `blur(${(1 - a) * 6}px)`,
        textShadow: '0 2px 18px rgba(0,0,0,.65), 0 0 2px rgba(0,0,0,.4)',
      }}
    >
      {line.text}
    </div>
  );
}

function EndMark({ L, f }: { L: FL; f: number }) {
  const a = smooth(seg(f, HIT.last, HIT.last + 24));
  if (a <= 0) return null;
  const y = L.caption.y + L.caption.size * (L.W > L.H ? 0.36 : 0.62);
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: y, textAlign: 'center', fontFamily: SFD, fontSize: L.caption.size * 0.62, fontWeight: 600, color: 'rgba(255,255,255,.72)', letterSpacing: 2, opacity: a }}>
      WindowShade 2
    </div>
  );
}

/** 键盘上按的那一下 Esc：画面下方一颗键帽，按下、弹起。 */
function Key({ L, f }: { L: FL; f: number }) {
  const a = fade(f, CP_ESC - 26, CP_ESC + 22, 8, 10);
  if (a <= 0) return null;
  const down = Math.max(0, 1 - Math.abs(f - CP_ESC) / 6);
  const u = L.caption.size * 1.7;
  return (
    <div style={{ position: 'absolute', left: L.W / 2 - u * 0.8, top: L.caption.y - u * 0.95, width: u * 1.6, height: u, opacity: a }}>
      <div style={{
        position: 'absolute', inset: 0, borderRadius: u * 0.16, background: 'linear-gradient(#3a3a3d,#2a2a2c)',
        boxShadow: `0 ${(1 - down) * u * 0.07}px 0 #121214, 0 ${u * 0.1}px ${u * 0.3}px rgba(0,0,0,.5), inset 0 1px 0 rgba(255,255,255,.12)`,
        transform: `translateY(${down * u * 0.06}px)`, display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-start', padding: `0 0 ${u * 0.14}px ${u * 0.16}px`,
        fontFamily: SFD, fontSize: u * 0.26, color: 'rgba(255,255,255,.9)', letterSpacing: 0.5,
      }}>esc</div>
    </div>
  );
}

export const FutureLandscape = () => <Future />;
export const FuturePortrait = () => <Future tall />;
export const FutureBlind = () => <Future blind />;
