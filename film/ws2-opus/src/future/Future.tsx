// 《它没有 Face ID》：一台普通的 MacBook，刷脸、启动台、读唇、点头、iPhone 的 CarPlay 开在 Mac 上、走开就锁。
// 跟着 120 BPM 的配乐剪：切点、句子、推拉、面容 ID 认出、刘海展开都在拍上（beats.ts）。
import { AbsoluteFill, Audio, Img, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { LANDSCAPE, PORTRAIT, type Rect } from '../layout';
import { PLATE } from './assets';
import { HIT, MUSIC_SRC, musicVolume } from './beats';
import { CP_ESC } from './CarPlay';
import { Screen } from './Desktop';
import { CJK, SFD } from './glyphs';
import { Island, mouthOpen } from './Island';
import { MacBook } from './MacBook';
import { LINES, SHOT, TOTAL, clamp01, fade, handheld, inOut, mix, seg, shotAt, smooth } from './time';

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

/** 竖版按画面高度摆：9:16 和 9:19.5（iPhone 全面屏）用同一套比例。 */
function portrait(W: number, H: number): FL {
  const k = W / 1080;
  const base = PORTRAIT.screen;
  const sw = base.w * k, sh = base.h * k;
  // 1080 × 1920 时屏幕中心在 0.42 高度；再高的画面把多出来的一半给上面、一半给句子下面。
  const cy = 0.42 * 1920 * k + (H - 1920 * k) * 0.45;
  const cap = 1560 * k + (H - 1920 * k) * 0.7;
  return {
    W, H,
    screen: { x: (W - sw) / 2, y: cy - sh / 2, w: sw, h: sh },
    caption: { y: cap, size: 62 * k },
    desk: PLATE.deskP,
    face: { size: H, x: W / 2 - H * 0.5 + 0.0104 * H, y: 0 },
    ear: { w: (H * 16) / 9, x: -0.35 * H, y: 0 },
  };
}

// ---- 镜头：[帧, 推近倍数, 屏幕上的横向位置, 纵向位置]；WIDE 是整台机器 ----
const WIDE = -1;
/** 屏宽正好等于画面宽。 */
const FIT = -2;
type Key = [number, number, number, number];
const KEYS: Key[] = [
  [0, 5.0, 0.5, 0.108], [112, 5.5, 0.5, 0.108], [250, 1, WIDE, WIDE], [420, 1.04, WIDE, WIDE],
  [421, 1.04, WIDE, WIDE], [500, 2.0, 0.5, 0.26], [530, 2.0, 0.5, 0.26], [690, 1.34, 0.5, 0.44], [1080, 1.38, 0.5, 0.44],
  [1320, 3.6, 0.5, 0.115], [1436, 3.7, 0.5, 0.115], [1500, 1.42, 0.5, 0.46], [1560, 1.45, 0.5, 0.46],
  [1800, 2.9, 0.5, 0.1], [1872, 2.95, 0.5, 0.1], [1930, 1.32, 0.5, 0.46], [1950, 1.33, 0.5, 0.46], [1984, 2.7, 0.5, 0.1], [2160, 2.8, 0.5, 0.1],
  // 长按刘海（贴着刘海看）→ 落拍那一下往后拉，整块屏都是 CarPlay → 推到顶上那条问话 → 退回来 → Esc，退成整台机器。
  [2236, 2.9, 0.5, 0.1], [2304, 1.12, 0.5, 0.5], [2500, 1.14, 0.5, 0.5], [2556, 1.95, 0.355, 0.13], [2640, 2.0, 0.355, 0.14],
  [2720, 1.14, 0.5, 0.5], [2880, 1.16, 0.5, 0.5], [2970, 1, WIDE, WIDE],
  [3000, 1, WIDE, WIDE], [3044, 3.1, 0.5, 0.07], [3190, 3.2, 0.5, 0.07], [3300, 1, WIDE, WIDE], [3600, 1.03, WIDE, WIDE],
];
const CUTS = new Set([421, 1320, 1800]);

function camera(L: FL, f: number) {
  const { x, y, w, h } = L.screen;
  const at = (k: Key) => {
    const z = k[1] === FIT ? L.W / w : k[1];
    return k[2] === WIDE ? { z, fx: L.W / 2, fy: L.H / 2 } : { z, fx: x + k[2] * w, fy: y + k[3] * h };
  };
  let i = 0;
  while (i < KEYS.length - 1 && KEYS[i + 1][0] <= f) i++;
  const a = KEYS[i], b = KEYS[Math.min(i + 1, KEYS.length - 1)];
  if (a === b || CUTS.has(b[0])) return at(a);
  const p = inOut(seg(f, a[0], b[0]));
  const A = at(a), B = at(b);
  // 推拉：倍数按对数走，焦点跟着同一条曲线。
  const z = Math.exp(mix(Math.log(A.z), Math.log(B.z), p));
  const q = (z - A.z) / (B.z - A.z || 1);
  const t = Math.abs(B.z - A.z) > 0.01 ? clamp01(q) : p;
  return { z, fx: mix(A.fx, B.fx, t), fy: mix(A.fy, B.fy, t) };
}

export function Future({ tall = false }: { tall?: boolean }) {
  const f = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const L = tall ? portrait(width, height) : LAND;
  const shot = shotAt(f);
  const desk = shot !== 'lips' && shot !== 'ear';
  return (
    <AbsoluteFill style={{ background: '#000', overflow: 'hidden' }}>
      {desk && <Desk L={L} f={f} />}
      {shot === 'lips' && <FaceShot L={L} f={f} />}
      {shot === 'ear' && <EarShot L={L} f={f} />}
      <Grade f={f} />
      <Key L={L} f={f} />
      <Caption L={L} f={f} />
      <EndMark L={L} f={f} />
      <Audio src={staticFile(MUSIC_SRC)} volume={(i) => musicVolume(i, TOTAL)} />
    </AbsoluteFill>
  );
}

// ---- 桌上那台 MacBook ----
function Desk({ L, f }: { L: FL; f: number }) {
  const c = camera(L, f), c0 = camera(L, f - 1);
  const hh = handheld(f, f >= 3330 ? 0.25 : 1);
  // 运动模糊：画面边缘这一帧走了多少像素。
  const move = CUTS.has(f) ? 0 : Math.abs(Math.log(c.z / c0.z)) * Math.hypot(L.W, L.H) * 0.5 + Math.hypot(c.fx - c0.fx, c.fy - c0.fy) * c.z;
  const blur = Math.min(2.2, move * 0.045);
  const tx = L.W / 2 - c.fx * c.z + hh.x, ty = L.H / 2 - c.fy * c.z + hh.y;
  // 背景更远：推得少、糊得多。
  const bz = Math.pow(c.z, 0.35);
  const bgBlur = Math.min(22, (c.z - 1) * 6);
  const glow = 1;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ transform: `scale(${bz})`, transformOrigin: `${L.W / 2}px ${L.H * 0.45}px`, filter: `blur(${bgBlur.toFixed(2)}px) brightness(.9)` }}>
        <Img src={L.desk} style={{ width: L.W, height: L.H, objectFit: 'cover' }} />
      </AbsoluteFill>
      <AbsoluteFill style={{ transformOrigin: '0 0', transform: `translate(${tx}px, ${ty}px) scale(${c.z}) rotate(${hh.r}deg)`, filter: blur > 0.4 ? `blur(${blur.toFixed(2)}px)` : undefined }}>
        <MacBook screen={L.screen} glow={glow} camOn={(f > -1 && f < 112) || (f >= 1320 && f < 1560)}>
          <Screen f={f} />
          <Island f={f} />
        </MacBook>
      </AbsoluteFill>
    </AbsoluteFill>
  );
}

// ---- Mac 摄像头看到的你：嘴在动，字一个个读出来 ----
function FaceShot({ L, f }: { L: FL; f: number }) {
  const t = f - SHOT.lips[0];
  const z = mix(1, 1.14, smooth(seg(t, 0, 220)));
  const hh = handheld(f, 0.6);
  const S = L.face.size;
  // 嘴在图里的位置（face.jpg 1024 见方）：中心 (518, 566)。
  const mx = 518 / 1024, my = 566 / 1024;
  const ox = L.face.x + mx * S, oy = L.face.y + my * S;
  const o = mouthOpen((t - 40) * 0.9);
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
          const a0 = fade(t, 10 + i, 210);
          return <circle key={i} cx={ox + Math.cos(a) * rx} cy={oy + Math.sin(a) * ry} r={3.2} fill="#64d2ff" opacity={a0 * 0.9} style={{ filter: 'drop-shadow(0 0 4px rgba(100,210,255,.9))' }} />;
        })}
      </svg>
      <div style={{ position: 'absolute', left: ox - 300, width: 600, top: oy + S * 0.075, display: 'flex', justifyContent: 'center', gap: 12, fontFamily: CJK, fontSize: 64, fontWeight: 650, color: '#fff', textShadow: '0 4px 24px rgba(0,0,0,.6)' }}>
        {chars.map((c, i) => {
          const p = seg(t, 62 + i * 46, 76 + i * 46);
          return <span key={c} style={{ opacity: p, filter: `blur(${(1 - p) * 10}px)` }}>{c}</span>;
        })}
      </div>
    </AbsoluteFill>
  );
}

// ---- 戴着 AirPods 点一下头 ----
function EarShot({ L, f }: { L: FL; f: number }) {
  const t = f - SHOT.ear[0];
  const nod = (u: number) => (u <= 0 || u >= 1 ? 0 : Math.sin(u * Math.PI) ** 1.4);
  const ang = (x: number) => 6.5 * nod((x - 70) / 50);
  const a = ang(t), v = Math.abs(ang(t) - ang(t - 1));
  const z = mix(1.04, 1.12, smooth(seg(t, 0, 240)));
  const px = L.ear.x + L.ear.w * 0.3, py = L.H * 1.15;
  return (
    <AbsoluteFill style={{ transformOrigin: `${L.W / 2}px ${L.H / 2}px`, transform: `scale(${z})` }}>
      <div style={{ position: 'absolute', inset: 0, transformOrigin: `${px}px ${py}px`, transform: `rotate(${a}deg)`, filter: v > 0.05 ? `blur(${Math.min(3, v * 6).toFixed(2)}px)` : undefined }}>
        <Img src={PLATE.ear} style={{ position: 'absolute', left: L.ear.x, top: L.ear.y, width: L.ear.w, height: (L.ear.w * 9) / 16 > L.H ? (L.ear.w * 9) / 16 : L.H, objectFit: 'cover' }} />
      </div>
    </AbsoluteFill>
  );
}

// ---- 调色、颗粒、暗角 ----
function Grade({ f }: { f: number }) {
  return (
    <>
      <AbsoluteFill style={{ background: 'radial-gradient(120% 90% at 50% 45%, transparent 55%, rgba(0,0,0,.42))', pointerEvents: 'none' }} />
      <AbsoluteFill style={{ opacity: 0.07, mixBlendMode: 'overlay', pointerEvents: 'none' }}>
        <svg width="100%" height="100%">
          <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={f % 23} /><feColorMatrix type="saturate" values="0" /></filter>
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
