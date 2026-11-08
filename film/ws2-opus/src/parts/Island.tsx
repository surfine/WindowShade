import type { ReactNode } from 'react';
import { islandAt, layersAt, type ContentLayer } from '../island';
import { FADE_IN } from '../motion/direction';
import { fusedIslandD } from '../motion/notchPath';
import { NOTCH, clamp01, pt } from '../motion/site';
import { CLICK_ALLOW, CONDUCT_SEND, CONDUCT_TALK, COUNTDOWN, FACE_OK, NOD_DOWN, NOD_FRAMES, type Content } from '../timeline';
import { ASK_UI, DROP_CHOICES, DROP_UI, SUMMARY_UI, dropDotAt, dropHoverAt, nodTiltAt, pointerAt, summaryHoverAt } from '../scene';

const INK = 'rgba(255,255,255,.92)';
const DIM = 'rgba(255,255,255,.5)';
const SW = 0.24; // 线宽，cqw

/** 黑色的岛：上沿贴着屏幕，宽、高、圆角来自同一次模拟。本体不做透明度。drawn 时画字和符号，否则只放线稿。 */
export function Island({ frame, cqw, drawn }: { frame: number; cqw: number; drawn: boolean }) {
  const s = islandAt(frame);
  const layers = layersAt(frame);
  const paint = drawn ? drawReal : draw;
  // 靜止時不另畫一顆藥丸。展開後設計稿的形狀和網格洞是同一條路徑、同一個黑。
  const grown = s.w > NOTCH.w + 0.05 || s.h > NOTCH.h + 0.05;
  const screenH = (1864 / 2880) * 100;
  return (
    <>
    <svg
      width="100%"
      height="100%"
      viewBox={`0 0 100 ${screenH}`}
      style={{ position: 'absolute', left: 0, top: 0, overflow: 'visible' }}
    >
      <path d={fusedIslandD(s.w, s.h, s.rb, s.rs, grown)} fill="#000" />
    </svg>
    <div
      style={{
        position: 'absolute', top: 0, left: '50%', width: s.w * cqw, height: s.h * cqw,
        transform: 'translateX(-50%)',
      }}
    >
      <svg width={s.w * cqw} height={s.h * cqw} viewBox={`0 0 ${s.w} ${s.h}`} style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="album" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#ff9ec3" /><stop offset=".55" stopColor="#ffd06a" /><stop offset="1" stopColor="#7fd0ff" /></linearGradient>
          <linearGradient id="tile" x1="0" y1="0" x2=".4" y2="1"><stop offset="0" stopColor="#3a3d45" /><stop offset="1" stopColor="#15161a" /></linearGradient>
        </defs>
        {layers.map((l, i) => <g key={`${l.content}-${i}`}>{paint(l, s.w, s.h, frame)}</g>)}
      </svg>
    </div>
    </>
  );
}

const line = { fill: 'none', stroke: INK, strokeWidth: SW, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

// 两侧的小图标照官网画，按真机刘海高度和官网 5.4 的比例缩小。
const EAR = 0.42;

function ears(l: ContentLayer, w: number, left: ReactNode, right: ReactNode) {
  // Compact：贴紧洞两侧，尽量窄、装满（WWDC23 10194）。
  const ear = (w - NOTCH.w) / 2;
  const cy = NOTCH.h / 2;
  const s = EAR * 1.08;
  return (
    <>
      <g opacity={l.first} transform={`translate(${ear / 2} ${cy}) scale(${s})`}>{left}</g>
      <g opacity={l.second} transform={`translate(${w - ear / 2} ${cy}) scale(${s})`}>{right}</g>
    </>
  );
}

function alertBody(l: ContentLayer, icon: ReactNode) {
  // alert：硬件刘海下面那一条里，左边符号位，右边两行字的位置（只画长短，不写字）。
  return (
    <>
      <g opacity={l.first} transform="translate(5 9.7)">{icon}</g>
      <line {...line} opacity={l.first} x1={9.4} y1={8.6} x2={24} y2={8.6} strokeWidth={0.9} />
      <line {...line} opacity={l.second} x1={9.4} y1={11.2} x2={19} y2={11.2} strokeWidth={0.6} stroke={DIM} />
    </>
  );
}

/** 指针停在哪一格，用最近 fade 入那么多帧的占比做亮度：换格时两格交叉淡化，不跳。 */
function hoverAmount(at: (f: number) => number, frame: number, i: number) {
  let n = 0;
  for (let k = 0; k < FADE_IN; k++) if (at(frame - k) === i) n++;
  return n / FADE_IN;
}

// 落点小岛五格的符号：一块屏，按去处涂满一部分（照 Notch.swift DropChoice.symbol 的意思画）。
function dropGlyph(i: number, ink: string) {
  const W = 4, H = 2.8, x = -W / 2, y = -H / 2;
  const fill = [
    <rect key="l" x={x + 0.45} y={y + 0.45} width={W / 2 - 0.6} height={H - 0.9} rx={0.2} fill={ink} />,
    <rect key="f" x={x + 0.45} y={y + 0.45} width={W - 0.9} height={H - 0.9} rx={0.2} fill={ink} />,
    <g key="t"><line {...line} stroke={ink} x1={0} x2={0} y1={y + 0.5} y2={0.45} strokeWidth={0.26} /><path {...line} stroke={ink} strokeWidth={0.26} d={`M -0.7 -0.2 L 0 0.5 L 0.7 -0.2`} /><line {...line} stroke={ink} x1={-1.1} x2={1.1} y1={0.95} y2={0.95} strokeWidth={0.26} /></g>,
    <g key="m">{[0, 1, 2].map((k) => <rect key={k} x={x + 0.45 + k * 1.07} y={y + 0.45} width={0.85} height={H - 0.9} rx={0.15} fill={ink} />)}</g>,
    <rect key="r" x={0.15} y={y + 0.45} width={W / 2 - 0.6} height={H - 0.9} rx={0.2} fill={ink} />,
  ][i];
  return (
    <g>
      {i !== 2 && <rect {...line} stroke={ink} strokeWidth={0.2} x={x} y={y} width={W} height={H} rx={0.45} />}
      {fill}
    </g>
  );
}

const sessionGlyph = <g><path {...line} d="M 0 -1.4 A 1.4 1.4 0 1 1 -1.21 0.7" /><circle cx={0} cy={0} r={0.35} fill={INK} /></g>;
/** 侧面的一只 AirPods Pro，跟着点头转（转轴在耳塞头上），左边一道弧是点头的方向。 */
const podGlyph = (tilt: number) => (
  <g>
    <path {...line} strokeWidth={0.16} opacity={0.5} d="M -2.1 -1.3 A 2.3 2.3 0 0 0 -2.1 1.3" />
    <g transform={`rotate(${tilt * 1.6} 0.2 -0.6)`}>
      <ellipse cx={0.2} cy={-0.6} rx={1.15} ry={1.05} fill="#fff" />
      <ellipse cx={-0.55} cy={-0.75} rx={0.42} ry={0.5} fill="#2b2d31" />
      <rect x={0.25} y={-0.2} width={0.72} height={2.5} rx={0.36} fill="#fff" transform="rotate(-14 0.6 -0.2)" />
    </g>
  </g>
);
const mouseGlyph = <g><rect {...line} x={-1.1} y={-1.8} width={2.2} height={3.6} rx={1.1} /><line {...line} x1={0} x2={0} y1={-1.5} y2={-0.7} /></g>;
const chatGlyph = <path {...line} d="M -1.7 -1.4 H 1.7 A 0.6 0.6 0 0 1 2.3 -0.8 V 0.7 A 0.6 0.6 0 0 1 1.7 1.3 H -0.4 L -1.4 2.1 V 1.3 H -1.7 A 0.6 0.6 0 0 1 -2.3 0.7 V -0.8 A 0.6 0.6 0 0 1 -1.7 -1.4 Z" />;

function drawDrop(l: ContentLayer, w: number, frame: number, real: boolean) {
  const { pad, pitch, top, bottom } = DROP_UI;
  const dot = dropDotAt(frame);
  return (
    <g>
      {DROP_CHOICES.map((name, i) => {
        const x = pad + pitch * i, cx = x + pitch / 2, on = hoverAmount(dropHoverAt, frame, i);
        const ink = `rgba(255,255,255,${0.62 + 0.38 * on})`;
        return (
          <g key={name}>
            <rect opacity={l.first} x={x + pt(2)} y={top} width={pitch - pt(4)} height={bottom - top} rx={pt(8)} fill={`rgba(255,255,255,${0.05 + 0.13 * on})`} />
            <g opacity={l.first} transform={`translate(${cx} ${top + pt(16)}) scale(0.36)`}>{dropGlyph(i, ink)}</g>
            {real && <text opacity={l.second} x={cx} y={bottom - pt(8)} textAnchor="middle" fontFamily={CJK} fontSize={pt(11)} fontWeight={on > 0.5 ? 600 : 400} fill={ink}>{name}</text>}
          </g>
        );
      })}
      {/* 你正在拖（第 2 层），构建跑完只在次区域留一个点。 */}
      <circle cx={w / 2 + NOTCH.w / 2 + 1.6} cy={NOTCH.h / 2} r={0.5} fill="#7ea4ff" opacity={dot * l.first} />
    </g>
  );
}

// 回来就开：右边两枚小点，左是人、右是手机，各自对上就亮（face-unlock.md“开盖·认你”）。
function factorDots(person: number, phone: number, ink: string) {
  return [person, phone].map((on, i) => (
    <circle key={i} cx={i ? 0.9 : -0.9} cy={0} r={0.55} fill={on > 0 ? '#34c759' : 'none'} fillOpacity={on} stroke={ink} strokeWidth={0.2} strokeOpacity={1 - 0.6 * on} />
  ));
}
/** 面容 ID 的图形：四个角、两只眼、鼻梁、嘴；认出来后换成绿色的勾（照 iPhone 的样子）。scan 0–1 是扫的进度。 */
function faceGlyph(person: number, scan: number, ink: string) {
  const k = 1.35, c = 0.55, sw = 0.2;
  const corner = (sx: number, sy: number) => <path key={`${sx}${sy}`} d={`M ${sx * k} ${sy * (k - c)} L ${sx * k} ${sy * (k - 0.25)} Q ${sx * k} ${sy * k} ${sx * (k - 0.25)} ${sy * k} L ${sx * (k - c)} ${sy * k}`} fill="none" stroke={ink} strokeWidth={sw} strokeLinecap="round" />;
  const face = (
    <g opacity={1 - person}>
      {[[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([x, y]) => corner(x, y))}
      <g stroke={ink} strokeWidth={sw} strokeLinecap="round" fill="none">
        <line x1={-0.45} y1={-0.45} x2={-0.45} y2={-0.2} /><line x1={0.45} y1={-0.45} x2={0.45} y2={-0.2} />
        <path d="M 0.05 -0.45 L 0.05 0.12 L -0.12 0.12" />
        <path d="M -0.45 0.42 Q 0 0.75 0.45 0.42" />
      </g>
      {/* 扫过去的一道亮线 */}
      <line x1={-1.1} x2={1.1} y1={-1.1 + 2.2 * scan} y2={-1.1 + 2.2 * scan} stroke="#5ac8fa" strokeWidth={0.12} opacity={0.8 * Math.sin(Math.PI * scan)} />
    </g>
  );
  return (
    <g>
      {face}
      <path d="M -0.8 0.05 L -0.2 0.6 L 0.85 -0.55" fill="none" stroke="#34c759" strokeWidth={0.32} strokeLinecap="round" strokeLinejoin="round" opacity={person} />
    </g>
  );
}

/** 锁屏上那一条窄的验证状态：左边面容 ID 在扫，中间是相机的绿灯，右边两点。 */
function verifyEars(l: ContentLayer, w: number, frame: number, ink: string) {
  const scan = ((frame % 40) / 40); // 每 0.67 秒扫一遍，认出来就停
  const person = clamp01((frame - FACE_OK) / FADE_IN);
  return (
    <>
      {ears(l, w,
        faceGlyph(person, scan, ink),
        <g>{factorDots(person, 1, ink)}</g>)}
      {/* 相机在硬件刘海正中；用着时亮绿灯，照系统的样子。 */}
      <circle cx={w / 2} cy={NOTCH.h / 2} r={0.28} fill="#34c759" opacity={l.first} />
    </>
  );
}

function draw(l: ContentLayer, w: number, h: number, frame = 0): ReactNode {
  const c: Content = l.content;
  switch (c) {
    case 'drop':
      return drawDrop(l, w, frame, false);
    case 'ask': {
      const { allow, deny } = ASK_UI;
      return (
        <>
          {alertBody(l, sessionGlyph)}
          {[deny, allow].map((b, i) => <rect key={i} {...line} opacity={l.second} x={b.x} y={b.y} width={b.w} height={b.h} rx={b.h / 2} stroke={i ? INK : DIM} />)}
        </>
      );
    }
    case 'cited':
      return alertBody(l, sessionGlyph);
    case 'verify':
    case 'unlocked':
      return c === 'verify' ? verifyEars(l, w, frame, INK) : alertBody(l, <g>{factorDots(1, 1, INK)}</g>);
    case 'preview':
      return alertBody(l, dropGlyph(0, INK));
    case 'lips': {
      const y = NOTCH.h + Math.max(1.2, (h - NOTCH.h) * 0.55);
      return <line {...line} opacity={l.first} x1={w * 0.28} x2={w * 0.72} y1={y} y2={y} strokeWidth={0.45} />;
    }
    case 'summary': {
      const { rowY, rowH, x } = SUMMARY_UI;
      return (
        <g>
          {[0, 1, 2].map((i) => {
            const y = rowY + rowH * i;
            return (
              <g key={i} opacity={i ? l.second : l.first}>
                <rect x={x} y={y + 0.3} width={w - 2 * x} height={rowH - 0.6} rx={1.8} fill="rgba(255,255,255,.12)" opacity={hoverAmount(summaryHoverAt, frame, i)} />
                <g transform={`translate(${x + 3.6} ${y + rowH / 2})`}>{[sessionGlyph, mouseGlyph, chatGlyph][i]}</g>
                <line {...line} x1={x + 7.2} x2={x + 22} y1={y + rowH / 2 - 0.9} y2={y + rowH / 2 - 0.9} strokeWidth={0.8} />
                <line {...line} x1={x + 7.2} x2={x + 17} y1={y + rowH / 2 + 1.3} y2={y + rowH / 2 + 1.3} strokeWidth={0.55} stroke={DIM} />
              </g>
            );
          })}
        </g>
      );
    }
    case 'music':
      return ears(l, w,
        <circle {...line} r={1.25} />,
        <g>{[-0.9, 0, 0.9].map((x, i) => <line key={i} {...line} x1={x} x2={x} y1={0.6} y2={0.6 - [1.1, 1.8, 0.8][i]} />)}</g>);
    case 'window':
    case 'windowChanged':
      return ears(l, w,
        <rect {...line} x={-1.4} y={-1} width={2.8} height={2} rx={0.4} />,
        <g>
          <text x={0} y={0.75} textAnchor="middle" fontSize={2} fontFamily="-apple-system,system-ui,sans-serif" fontWeight={600} fill={INK}>1</text>
          {c === 'windowChanged' && <circle cx={1.4} cy={-1.1} r={0.38} fill="#ff9f0a" />}
        </g>);
    case 'session':
      return ears(l, w,
        <path {...line} d="M 0 -1.25 A 1.25 1.25 0 1 1 -1.08 0.62" />,
        <g>{[-0.9, 0, 0.9].map((x, i) => <circle key={i} cx={x} cy={0} r={0.3} fill={INK} />)}</g>);
    case 'focus':
      return ears(l, w,
        <g><circle {...line} r={1.25} stroke={DIM} /><path {...line} d="M 0 -1.25 A 1.25 1.25 0 1 1 -1.19 0.39" /></g>,
        <line {...line} x1={-1.2} x2={1.2} y1={0} y2={0} strokeWidth={0.7} />);
    case 'headphones':
      return alertBody(l, <g><path {...line} d="M -1.8 0.8 L -1.8 0 A 1.8 1.8 0 0 1 1.8 0 L 1.8 0.8" /><rect {...line} x={-2.1} y={0.3} width={0.8} height={1.4} rx={0.3} /><rect {...line} x={1.3} y={0.3} width={0.8} height={1.4} rx={0.3} /></g>);
    case 'mouse':
      return alertBody(l, <g><rect {...line} x={-1.1} y={-1.8} width={2.2} height={3.6} rx={1.1} /><line {...line} x1={0} x2={0} y1={-1.5} y2={-0.7} /></g>);
    case 'build':
      return alertBody(l, <rect {...line} x={-1.6} y={-1.6} width={3.2} height={3.2} rx={0.7} />);
    case 'countdown': {
      // 倒数 10 秒：圆环按真实时间收短。
      const left = 1 - clamp01(l.since / COUNTDOWN);
      const a = Math.PI * 2 * left;
      const end = { x: 1.8 * Math.sin(a), y: -1.8 * Math.cos(a) };
      const ring = left >= 0.999
        ? <circle {...line} r={1.8} />
        : <path {...line} d={`M 0 -1.8 A 1.8 1.8 0 ${a > Math.PI ? 1 : 0} 1 ${end.x} ${end.y}`} />;
      return alertBody(l, <g><circle {...line} r={1.8} stroke="rgba(255,255,255,.18)" />{left > 0.001 && ring}</g>);
    }
    case 'card': {
      // 和飞回的终端同一视觉身份（红绿灯 + 编译行），缩在岛里。
      const cw = (200 / 2880) * 100, ch = (131 / 2880) * 100, x = w / 2 - cw / 2, y = NOTCH.h + (28 / 2880) * 100;
      return (
        <g opacity={l.first}>
          <rect x={x} y={y} width={cw} height={ch} rx={1.2} fill="#1e1f24" stroke="rgba(255,255,255,.28)" strokeWidth={SW * 0.7} />
          {['#ff5f57', '#febc2e', '#28c840'].map((c, i) => <circle key={c} cx={x + cw * 0.12 + i * cw * 0.1} cy={y + ch * 0.22} r={ch * 0.08} fill={c} />)}
          <line {...line} opacity={l.second} x1={x + cw * 0.08} x2={x + cw * 0.72} y1={y + ch * 0.48} y2={y + ch * 0.48} strokeWidth={0.55} />
          <line {...line} opacity={l.second} x1={x + cw * 0.08} x2={x + cw * 0.55} y1={y + ch * 0.68} y2={y + ch * 0.68} strokeWidth={0.45} stroke="rgba(255,255,255,.45)" />
        </g>
      );
    }
    case 'stroke': {
      const y = NOTCH.h + (h - NOTCH.h) * 0.56;
      const half = Math.min(6.2, (w - 4) / 2);
      return <line {...line} opacity={l.first} x1={w / 2 - half} x2={w / 2 + half} y1={y} y2={y} strokeWidth={0.5} />;
    }
    case 'road': {
      // 另一种用法：只画透视线，不画任何界面和标志。
      const vx = w / 2, vy = h * 0.32;
      const xs = [-60, -18, 18, 60];
      return (
        <g opacity={l.first}>
          {xs.map((x, i) => <line key={i} {...line} stroke={i === 1 || i === 2 ? INK : DIM} x1={vx + x} y1={h + 2} x2={vx} y2={vy} strokeWidth={0.18} />)}
          <line {...line} stroke="rgba(255,255,255,.22)" x1={0} x2={w} y1={vy} y2={vy} strokeWidth={0.12} />
        </g>
      );
    }
    default:
      return null;
  }
}

// ---- 画出来的那一版：照 site/style.css 的岛（图标 3.4cqw / 6cqw、主句 2.3cqw、副句 1.7cqw 白 0.62）----
const CJK = '"PingFang SC",-apple-system,system-ui,sans-serif';
const MONO = 'ui-monospace,"SF Mono",Menlo,monospace';

function termTile(size: number) {
  return (
    <g>
      <rect x={-size / 2} y={-size / 2} width={size} height={size} rx={size * 0.24} fill="url(#tile)" stroke="rgba(255,255,255,.18)" strokeWidth={0.12} />
      <text x={0} y={size * 0.13} textAnchor="middle" fontFamily={MONO} fontWeight={600} fontSize={size * 0.38} fill="#9be29b">&gt;_</text>
    </g>
  );
}

function alertReal(l: ContentLayer, h: number, icon: ReactNode, title: string, detail: string) {
  // Expanded／半岛：同心边距——图块圆角与岛外轮廓和谐，字不贴侧壁（10194）。
  const margin = pt(12);
  const size = pt(28);
  const x = margin;
  const band = h - NOTCH.h;
  const y = NOTCH.h + Math.max(pt(6), (band - size) / 2);
  const textX = x + size + pt(10);
  return (
    <>
      <g opacity={l.first} transform={`translate(${x + size / 2} ${y + size / 2}) scale(${size / 6})`}>{icon}</g>
      <text opacity={l.first} x={textX} y={y + pt(12)} fontFamily={CJK} fontWeight={700} fontSize={pt(18)} fill="#fff">{title}</text>
      <text opacity={l.second} x={textX} y={y + pt(32)} fontFamily={CJK} fontWeight={600} fontSize={pt(13)} fill="rgba(255,255,255,.7)">{detail}</text>
    </>
  );
}

function tile(glyph: ReactNode) {
  return (
    <g>
      <rect x={-3.1} y={-3.1} width={6.2} height={6.2} rx={1.7} fill="url(#tile)" stroke="rgba(255,255,255,.16)" strokeWidth={0.1} />
      <g transform="scale(1.2)">{glyph}</g>
    </g>
  );
}

function drawReal(l: ContentLayer, w: number, h: number, frame: number): ReactNode {
  switch (l.content) {
    case 'drop':
      return drawDrop(l, w, frame, true);
    case 'ask': {
      // 要你放行的事：一句问话，两个按钮。只认问话出现之后的那一下点。
      const { allow, deny } = ASK_UI;
      const size = pt(24), x = pt(12), y = NOTCH.h + pt(10);
      const p = pointerAt(frame);
      const pressed = p && frame >= CLICK_ALLOW - 12 && frame <= CLICK_ALLOW ? p.pressed : 0;
      return (
        <>
          <g opacity={l.first} transform={`translate(${x + size / 2} ${y + size / 2}) scale(${size / 6})`}>{tile(sessionGlyph)}</g>
          <text opacity={l.first} x={x + size + pt(8)} y={y + pt(10)} fontFamily={CJK} fontWeight={600} fontSize={pt(13)} fill="#fff">允许改文章草稿？</text>
          <text opacity={l.second} x={x + size + pt(8)} y={y + pt(26)} fontFamily={CJK} fontSize={pt(11)} fill="rgba(255,255,255,.62)">Claude · 核对三处引文</text>
          <g opacity={l.second}>
            <rect x={deny.x} y={deny.y} width={deny.w} height={deny.h} rx={deny.h / 2} fill="rgba(255,255,255,.12)" />
            <text x={deny.x + deny.w / 2} y={deny.y + deny.h / 2 + pt(4)} textAnchor="middle" fontFamily={CJK} fontSize={pt(12)} fill="#fff">不允许</text>
            <rect x={allow.x} y={allow.y} width={allow.w} height={allow.h} rx={allow.h / 2} fill="#7ea4ff" />
            <rect x={allow.x} y={allow.y} width={allow.w} height={allow.h} rx={allow.h / 2} fill="#fff" opacity={0.28 * pressed} />
            <text x={allow.x + allow.w / 2} y={allow.y + allow.h / 2 + pt(4)} textAnchor="middle" fontFamily={CJK} fontWeight={600} fontSize={pt(12)} fill="#0b1630">允许</text>
          </g>
        </>
      );
    }
    case 'cited':
      return alertReal(l, h, tile(sessionGlyph), '引文已核对', '改了 3 处 · 文章草稿');
    case 'verify':
      return verifyEars(l, w, frame, '#fff');
    case 'unlocked':
      return alertReal(l, h, tile(<g transform="scale(1.4)">{factorDots(1, 1, '#fff')}</g>), '两样都对上了', '人在 · 手机在身边');
    case 'preview': {
      const confirmed = frame >= NOD_DOWN + NOD_FRAMES;
      return alertReal(l, h, tile(podGlyph(nodTiltAt(frame))), confirmed ? '已确认 · 正在落位' : '等你确认', confirmed ? '左半屏' : '静音操作 · 点头确认');
    }
    case 'lips':
      return alertReal(l, h, tile(sessionGlyph), '等你确认', '放到左半屏');
    case 'summary': {
      const { titleY, rowY, rowH, x } = SUMMARY_UI;
      // 两家助手只写名字，不画标志。
      const rows = [
        { icon: sessionGlyph, title: 'Codex 跑完了', detail: '42 个测试通过 · Claude 还在跑' },
        { icon: mouseGlyph, title: '妙控鼠标电量低', detail: '还剩 10%，记得充电' },
        { icon: chatGlyph, title: '聊天', detail: '3 条新消息' },
      ];
      return (
        <g>
          <text opacity={l.first} x={x} y={titleY} fontFamily={CJK} fontWeight={600} fontSize={pt(11)} fill="rgba(255,255,255,.62)">离开期间</text>
          {rows.map((r, i) => {
            const y = rowY + rowH * i;
            return (
              <g key={r.title} opacity={i ? l.second : l.first}>
                <rect x={x} y={y + 0.3} width={w - 2 * x} height={rowH - 0.6} rx={1.8} fill="rgba(255,255,255,.12)" opacity={hoverAmount(summaryHoverAt, frame, i)} />
                <g transform={`translate(${x + pt(16)} ${y + rowH / 2}) scale(${pt(18) / 6})`}>{tile(r.icon)}</g>
                <text x={x + pt(36)} y={y + rowH * 0.42} fontFamily={CJK} fontWeight={600} fontSize={pt(12)} fill="#fff">{r.title}</text>
                <text x={x + pt(36)} y={y + rowH * 0.78} fontFamily={CJK} fontSize={pt(11)} fill="rgba(255,255,255,.62)">{r.detail}</text>
              </g>
            );
          })}
        </g>
      );
    }
    case 'music':
      return ears(l, w,
        <rect x={-1.7} y={-1.7} width={3.4} height={3.4} rx={0.7} fill="url(#album)" />,
        <g>{[-1.2, -0.4, 0.4, 1.2].map((x, i) => <rect key={i} x={x - 0.22} y={-[0.7, 1.3, 1.0, 0.5][i]} width={0.44} height={2 * [0.7, 1.3, 1.0, 0.5][i]} rx={0.22} fill="#ff9ec3" />)}</g>);
    case 'window':
    case 'windowChanged':
      return ears(l, w, termTile(3.4),
        <g>
          {l.content === 'windowChanged' && <circle cx={-1.5} cy={0} r={0.55} fill="#7ea4ff" />}
          <text x={l.content === 'windowChanged' ? 0.5 : 0} y={0.8} textAnchor="middle" fontFamily={CJK} fontWeight={600} fontSize={2.3} fill="#fff">1</text>
        </g>);
    case 'headphones':
      return alertReal(l, h, tile(<g><path {...line} d="M -1.8 0.8 L -1.8 0 A 1.8 1.8 0 0 1 1.8 0 L 1.8 0.8" /><rect {...line} x={-2.1} y={0.3} width={0.8} height={1.4} rx={0.3} /><rect {...line} x={1.3} y={0.3} width={0.8} height={1.4} rx={0.3} /></g>), 'AirPods 已连接', '电量 90%');
    case 'mouse':
      return alertReal(l, h, tile(<g><rect {...line} x={-1.1} y={-1.8} width={2.2} height={3.6} rx={1.1} /><line {...line} x1={0} x2={0} y1={-1.5} y2={-0.7} /></g>), '妙控鼠标已连接', '电量 82%');
    case 'build':
      return alertReal(l, h, termTile(6), '构建成功', '终端');
    case 'countdown': {
      const remain = Math.max(0, COUNTDOWN - l.since);
      const left = remain / COUNTDOWN;
      const a = Math.PI * 2 * left;
      const end = { x: 2 * Math.sin(a), y: -2 * Math.cos(a) };
      const ring = left >= 0.999 ? <circle {...line} r={2} stroke="#ff6b5e" strokeWidth={0.45} /> : <path {...line} stroke="#ff6b5e" strokeWidth={0.45} d={`M 0 -2 A 2 2 0 ${a > Math.PI ? 1 : 0} 1 ${end.x} ${end.y}`} />;
      return alertReal(l, h, <g><circle {...line} r={2} stroke="rgba(255,255,255,.18)" strokeWidth={0.45} />{left > 0.001 && ring}</g>, '手机不在身边', `${Math.ceil(remain / 60)} 秒后锁屏`);
    }
    case 'card': {
      // 和飛回去的那扇終端是同一扇：紅綠燈、同一句提示符、同一行編譯。縮在島的高度裡。
      const cw = Math.min(16.2, w - 2.4);
      const ch = Math.min(7.2, h - NOTCH.h - 1.1);
      const x = w / 2 - cw / 2;
      const y = NOTCH.h + 0.55;
      const rows = ['$ swift build', 'Compiling WindowShade', '[132/186] Notch.swift'];
      return (
        <g opacity={l.first}>
          <rect x={x} y={y} width={cw} height={ch} rx={0.7} fill="#1e1f24" stroke="rgba(255,255,255,.16)" strokeWidth={0.06} />
          <path d={`M ${x} ${y + 0.7} A 0.7 0.7 0 0 1 ${x + 0.7} ${y} L ${x + cw - 0.7} ${y} A 0.7 0.7 0 0 1 ${x + cw} ${y + 0.7} L ${x + cw} ${y + 1.45} L ${x} ${y + 1.45} Z`} fill="#2a2c33" />
          {['#ff5f57', '#febc2e', '#28c840'].map((c, i) => <circle key={c} cx={x + 0.7 + i * 0.72} cy={y + 0.74} r={0.2} fill={c} />)}
          <text x={x + cw - 0.45} y={y + 0.98} textAnchor="end" fontFamily={CJK} fontWeight={600} fontSize={0.62} fill="#f5f5f7">终端</text>
          {rows.map((r, i) => (
            <text key={r} x={x + 0.45} y={y + 2.35 + i * 1.15} fontFamily={MONO} fontSize={0.7} fill={i ? '#d7dbe3' : '#8fd18f'}>{r}</text>
          ))}
          <rect x={x + 0.45} y={y + ch - 1.15} width={0.34} height={0.72} fill="#d7dbe3" />
        </g>
      );
    }
    case 'stroke': {
      // 抬手先出三声；再说一句出草稿；播放键发出去。笔画在 iPhone 上。
      if (frame < CONDUCT_TALK) return alertReal(l, h, tile(sessionGlyph), '三声 · high', '下一轮 · WindowShade · Claude');
      const sent = frame >= CONDUCT_SEND;
      const title = sent ? '发出去了' : '核对三处引文';
      const detail = sent ? '三声 · high · 文章草稿' : '草稿 · 播放键发出去';
      return alertReal(l, h, tile(sessionGlyph), title, detail);
    }
    case 'focus':
      return ears(l, w,
        <g><circle {...line} r={1.4} stroke="rgba(255,255,255,.18)" strokeWidth={0.4} /><circle {...line} r={1.4} stroke="#ff6b5e" strokeWidth={0.4} /></g>,
        <text x={0} y={0.7} textAnchor="middle" fontFamily={CJK} fontWeight={600} fontSize={1.8} fill="#fff">25 分</text>);
    default:
      return draw(l, w, h, frame);
  }
}
