// 黑色的岛：上沿贴着屏幕，本体不做透明度；内容在形状走到一定程度后才淡入，退场先收内容。
import type { ReactNode } from 'react';
import { Img } from 'remotion';
import { PLATE } from './assets';
import { CP_ESC, CP_IN, CarPlay } from './CarPlay';
import { AirPods, Battery, CJK, Check, FaceGlyph, IPhone, Lock, SFD, SFR, XMark } from './glyphs';
import { NOTCH_PT, PT, islandAt } from './shape';
import { clamp01, fade, mix, seg, smooth } from './time';

const SUB = 'rgba(235,235,245,.6)';

/** 「读到的」和「左半屏？」两段在岛上的时间。 */
export const LISTEN = [1040, 1556] as const;
/** CarPlay 跟着岛缩到这一帧才开始淡（Esc 后 12 帧开始收，再 14 帧已经很小）。 */
const CAR_OUT = CP_ESC + 26;
export const ASK = [1552, 1828] as const;
/** 嘴在 face.jpg 里的位置（0–1）；嘴动从这一帧开始（镜头里和小画面里同一个嘴）。 */
export const MOUTH = { x: 518 / 1024, y: 566 / 1024 };
export const LIPS_T0 = 1120;
/** 读唇小画面：边长、圆角、左边距、里面那张脸的边长（点）。 */
export const THUMB = { size: 66, r: 18, pad: 22, img: 300 };
/** 问话那一行左边的图标格。 */
export const ICON_BOX = { size: 44, pad: 26, r: 12 };

/** 岛里某个方块此刻在屏幕点坐标里的位置。 */
export function islandBox(f: number, which: 'thumb' | 'pods') {
  const s = islandAt(f);
  const cy = NOTCH_PT.h + (s.h - NOTCH_PT.h) / 2;
  const left = (PT.w - s.w) / 2;
  if (which === 'thumb') return { x: left + THUMB.pad, y: cy - THUMB.size / 2, w: THUMB.size, h: THUMB.size, r: THUMB.r };
  return { x: left + ICON_BOX.pad, y: cy - ICON_BOX.size / 2, w: ICON_BOX.size, h: ICON_BOX.size, r: ICON_BOX.r };
}

export function Island({ f }: { f: number }) {
  const s = islandAt(f);
  const fil = 7; // 上沿两侧的内凹小圆角
  return (
    <div style={{ position: 'absolute', left: (PT.w - s.w) / 2, top: 0, width: s.w, height: s.h, zIndex: 40 }}>
      {s.w < PT.w && [0, 1].map((i) => (
        <div
          key={i}
          style={{
            position: 'absolute', top: 0, [i ? 'right' : 'left']: -fil, width: fil, height: fil,
            background: `radial-gradient(circle at ${i ? '100%' : '0'} 100%, transparent ${fil - 0.3}px, #000 ${fil}px)`,
          }}
        />
      ))}
      <div style={{ position: 'absolute', inset: 0, background: '#000', borderBottomLeftRadius: s.r, borderBottomRightRadius: s.r, overflow: 'hidden' }}>
        <Content f={f} w={s.w} h={s.h} />
        {f >= CP_IN && f < CAR_OUT + 8 && <Car f={f} w={s.w} />}
      </div>
    </div>
  );
}

const body = (h: number) => ({ top: NOTCH_PT.h, height: h - NOTCH_PT.h });

function Row({ w, h, a, icon, title, sub, shake = 0 }: { w: number; h: number; a: number; icon: ReactNode; title: ReactNode; sub?: ReactNode; shake?: number }) {
  const b = body(h);
  return (
    <div style={{ position: 'absolute', left: 0, width: w, ...b, opacity: a, display: 'flex', alignItems: 'center', gap: 14, padding: '0 26px', transform: `translateX(${shake}px)` }}>
      <div style={{ width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>{icon}</div>
      <div style={{ fontFamily: CJK, whiteSpace: 'nowrap' }}>
        <div style={{ fontSize: 19, fontWeight: 600, color: '#fff', letterSpacing: 0.2 }}>{title}</div>
        {sub && <div style={{ fontSize: 14, color: SUB, marginTop: 3 }}>{sub}</div>}
      </div>
    </div>
  );
}

function Content({ f, w, h }: { f: number; w: number; h: number }) {
  // 刷脸：-16 开始长，0 帧时已经在扫；84 认出；112 收回。
  if (f < 112) {
    const a = fade(f, -8, 110, 8, 8);
    const scan = seg(f, -6, 70);
    const sweep = (Math.max(0, f + 6) / 52) % 1 + 0;
    const ok = smooth(seg(f, 82, 96));
    const size = 150;
    const cy = NOTCH_PT.h + (h - NOTCH_PT.h) / 2;
    return (
      <div style={{ position: 'absolute', left: w / 2 - size / 2, top: cy - size / 2 - 4, width: size, height: size, opacity: a, transform: `scale(${mix(0.92, 1, smooth(seg(f, -10, 10)))})` }}>
        <FaceGlyph size={size} scan={scan} ok={ok} sweep={sweep} />
      </div>
    );
  }
  // 认出来了：欢迎回来，手机也在身边。
  if (f >= 292 && f < 410) {
    const a = fade(f, 300, 404);
    const b = fade(f, 312, 404);
    return (
      <>
        <Row w={w} h={h} a={a} icon={<Check size={34} />} title="欢迎回来" sub={<span style={{ opacity: b / Math.max(a, 0.01) }}>你的 iPhone 也在身边</span>} />
        <div style={{ position: 'absolute', right: 30, ...body(h), display: 'flex', alignItems: 'center', opacity: b }}>
          <div style={{ position: 'relative' }}>
            <IPhone size={30} />
            <i style={{ position: 'absolute', right: -5, top: -3, width: 9, height: 9, borderRadius: 5, background: '#30D158', boxShadow: '0 0 0 2px #000' }} />
          </div>
        </div>
      </>
    );
  }
  // iPhone 连上来了：长按刘海，CarPlay 就开在这块屏上。
  if (f >= 2166 && f < 2272) {
    const a = fade(f, 2174, 2270, 11, 6);
    const b = fade(f, 2186, 2270, 11, 6);
    return (
      <>
        <Row w={w} h={h} a={a} icon={<IPhone size={34} />} title="iPhone 已连接" sub={<span style={{ opacity: b / Math.max(a, 0.01) }}>长按刘海，打开 CarPlay</span>} />
        <div style={{ position: 'absolute', right: 26, ...body(h), display: 'flex', alignItems: 'center', gap: 7, opacity: b, fontFamily: SFD, fontSize: 15, fontWeight: 600, color: '#fff' }}>
          82%<Battery size={26} color="#30D158" level={0.82} />
        </div>
      </>
    );
  }
  // 读唇：嘴的小画面、读到的字、嘴动的节奏。
  if (f >= LISTEN[0] && f < LISTEN[1]) {
    const a = fade(f, LISTEN[0] + 8, LISTEN[1] - 4);
    const chars = ['左', '半', '屏'];
    return (
      <div style={{ position: 'absolute', left: 0, width: w, ...body(h), opacity: a, display: 'flex', alignItems: 'center', padding: `0 ${THUMB.pad}px`, gap: 18 }}>
        <div style={{ width: THUMB.size, height: THUMB.size, borderRadius: THUMB.r, overflow: 'hidden', flex: 'none', position: 'relative', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.12)' }}>
          <Img src={PLATE.face} style={{ position: 'absolute', width: THUMB.img, height: THUMB.img, left: THUMB.size / 2 - MOUTH.x * THUMB.img, top: THUMB.size / 2 - MOUTH.y * THUMB.img }} />
          <LipDots f={f} />
        </div>
        <div style={{ fontFamily: CJK, flex: 1 }}>
          <div style={{ fontSize: 13, color: SUB, letterSpacing: 1 }}>读到的</div>
          <div style={{ fontSize: 30, fontWeight: 650, color: '#fff', display: 'flex', gap: 2, marginTop: 2 }}>
            {chars.map((c, i) => {
              const t = seg(f, 1326 + i * 16, 1338 + i * 16);
              return <span key={c} style={{ opacity: t, filter: `blur(${(1 - t) * 6}px)`, transform: `translateY(${(1 - t) * 6}px)` }}>{c}</span>;
            })}
          </div>
        </div>
      </div>
    );
  }
  // 点头确认：左半屏。中间镜头钻进 AirPods 看你点头，回来时图标还跟着点一下。
  if (f >= ASK[0] && f < ASK[1]) {
    const a = fade(f, ASK[0] + 10, ASK[1] - 6);
    const nod = Math.sin(clamp01((f - 1734) / 22) * Math.PI) * 14;
    const done = seg(f, 1752, 1762);
    return (
      <>
        <Row w={w} h={h} a={a * (1 - done)} icon={<AirPods size={40} tilt={nod} />} title="左半屏？" sub="点头确认，摇头取消" />
        <Row w={w} h={h} a={a * done} icon={<Check size={34} draw={seg(f, 1754, 1772)} />} title="好了" sub="已移到左半屏" />
      </>
    );
  }
  // 摇头取消。
  if (f >= 1962 && f < 2096) {
    const a = fade(f, 1970, 2090);
    const sway = f > 2004 && f < 2040 ? Math.sin(((f - 2004) / 36) * Math.PI * 4) * 12 * (1 - (f - 2004) / 36) : 0;
    const done = seg(f, 2040, 2050);
    return (
      <>
        <Row w={w} h={h} a={a * (1 - done)} icon={<AirPods size={40} sway={sway} />} title="全部收进刘海？" sub="点头确认，摇头取消" />
        <Row w={w} h={h} a={a * done} icon={<XMark size={32} />} title="已取消" sub="窗口都还在" shake={done < 1 ? 0 : Math.sin((f - 2050) * 0.9) * 5 * Math.max(0, 1 - (f - 2050) / 18)} />
      </>
    );
  }
  // 走开：倒数，然后锁上。
  if (f >= 3168 && f < 3282) {
    const a = fade(f, 3174, 3272, 8, 8);
    const size = 120;
    const cy = NOTCH_PT.h + (h - NOTCH_PT.h) / 2;
    return (
      <div style={{ position: 'absolute', left: w / 2 - size / 2, top: cy - size / 2, width: size, height: size, opacity: a, transform: `scale(${mix(0.9, 1, smooth(seg(f, 3168, 3186)))})` }}>
        <Lock size={size} open={1 - smooth(seg(f, 3174, 3184))} />
      </div>
    );
  }
  if (f >= 2968 && f < 3172) {
    const a = fade(f, 2976, 3170);
    const left = Math.max(1, 3 - Math.floor((f - 3000) / 60));
    const ring = 1 - clamp01((f - 3000) / 180);
    const ear = (w - NOTCH_PT.w) / 2;
    return (
      <div style={{ opacity: a }}>
        <div style={{ position: 'absolute', left: ear / 2 - 11, top: NOTCH_PT.h / 2 - 11, width: 22, height: 22 }}>
          <svg width={22} height={22} viewBox="0 0 22 22">
            <circle cx={11} cy={11} r={9.5} fill="none" stroke="rgba(255,159,10,.28)" strokeWidth={2.4} />
            <circle cx={11} cy={11} r={9.5} fill="none" stroke="#ff9f0a" strokeWidth={2.4} strokeLinecap="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - ring} transform="rotate(-90 11 11)" />
          </svg>
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: SFR, fontSize: 12, fontWeight: 700, color: '#ff9f0a' }}>{left}</div>
        </div>
        <div style={{ position: 'absolute', right: ear / 2 - 9, top: NOTCH_PT.h / 2 - 9 }}>
          <Lock size={18} color="#ff9f0a" />
        </div>
      </div>
    );
  }
  return null;
}

/** 嘴型三拍：左、半、屏。 */
export function mouthOpen(t: number) {
  const beats = [[0, 34], [44, 76], [88, 128]];
  const peaks = [0.7, 1, 0.55];
  let v = 0;
  beats.forEach(([a, b], i) => {
    if (t > a && t < b) v = Math.max(v, Math.sin(((t - a) / (b - a)) * Math.PI) * peaks[i]);
  });
  return v;
}

function LipDots({ f }: { f: number }) {
  const o = mouthOpen((f - LIPS_T0) * 0.9);
  const pts = Array.from({ length: 14 }, (_, i) => {
    const a = (i / 14) * Math.PI * 2;
    const up = Math.sin(a) < 0;
    return { x: 33 + Math.cos(a) * 15, y: 33 + Math.sin(a) * (up ? 5 + o * 2 : 5 + o * 7) };
  });
  return (
    <svg width={THUMB.size} height={THUMB.size} style={{ position: 'absolute', inset: 0 }}>
      {pts.map((p, i) => <circle key={i} cx={p.x} cy={p.y} r={1.3} fill="#64d2ff" />)}
    </svg>
  );
}

/** 刘海展开成整块屏：刘海下面就是 iPhone 的 CarPlay，跟着岛一起从刘海里长出来。 */
function Car({ f, w }: { f: number; w: number }) {
  const k = w / PT.w;
  // 收回时 CarPlay 跟着岛一起缩进刘海，缩小了才淡掉。
  const a = clamp01((f - CP_IN - 6) / 10) * (1 - clamp01((f - CAR_OUT) / 8));
  return (
    <div style={{ position: 'absolute', left: (w - PT.w * k) / 2, top: NOTCH_PT.h * k, width: PT.w, height: PT.h, transformOrigin: '0 0', transform: `scale(${k})`, opacity: a }}>
      <CarPlay f={f} />
    </div>
  );
}
