import type { ReactNode } from 'react';
import { islandAt, layersAt, type ContentLayer } from '../island';
import { NOTCH, clamp01 } from '../motion/site';
import { COUNTDOWN, type Content } from '../timeline';
import { STROKE } from '../scene';

const INK = 'rgba(255,255,255,.92)';
const DIM = 'rgba(255,255,255,.5)';
const SW = 0.24; // 线宽，cqw

/** 黑色的岛：上沿贴着屏幕，宽、高、圆角来自同一次模拟。本体不做透明度。drawn 时画字和符号，否则只放线稿。 */
export function Island({ frame, cqw, drawn }: { frame: number; cqw: number; drawn: boolean }) {
  const s = islandAt(frame);
  const layers = layersAt(frame);
  const paint = drawn ? drawReal : draw;
  return (
    <div
      style={{
        position: 'absolute', top: 0, left: '50%', width: s.w * cqw, height: s.h * cqw,
        transform: 'translateX(-50%)', background: '#000', overflow: 'hidden',
        borderBottomLeftRadius: s.r * cqw, borderBottomRightRadius: s.r * cqw,
      }}
    >
      <svg width={s.w * cqw} height={s.h * cqw} viewBox={`0 0 ${s.w} ${s.h}`} style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="album" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#ff9ec3" /><stop offset=".55" stopColor="#ffd06a" /><stop offset="1" stopColor="#7fd0ff" /></linearGradient>
          <linearGradient id="tile" x1="0" y1="0" x2=".4" y2="1"><stop offset="0" stopColor="#3a3d45" /><stop offset="1" stopColor="#15161a" /></linearGradient>
        </defs>
        {layers.map((l, i) => <g key={`${l.content}-${i}`}>{paint(l, s.w, s.h)}</g>)}
      </svg>
    </div>
  );
}

const line = { fill: 'none', stroke: INK, strokeWidth: SW, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

function ears(l: ContentLayer, w: number, left: ReactNode, right: ReactNode) {
  // compact：内容只在硬件刘海两边露出的那一截里。
  const ear = (w - NOTCH.w) / 2;
  const cy = NOTCH.h / 2;
  return (
    <>
      <g opacity={l.first} transform={`translate(${ear / 2} ${cy})`}>{left}</g>
      <g opacity={l.second} transform={`translate(${w - ear / 2} ${cy})`}>{right}</g>
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

function draw(l: ContentLayer, w: number, h: number): ReactNode {
  const c: Content = l.content;
  switch (c) {
    case 'music':
      return ears(l, w,
        <circle {...line} r={1.25} />,
        <g>{[-0.9, 0, 0.9].map((x, i) => <line key={i} {...line} x1={x} x2={x} y1={0.6} y2={0.6 - [1.1, 1.8, 0.8][i]} />)}</g>);
    case 'window':
    case 'windowChanged':
      return ears(l, w,
        <rect {...line} x={-1.4} y={-1} width={2.8} height={2} rx={0.4} />,
        <g>
          <text x={0} y={0.75} textAnchor="middle" fontSize={2} fontFamily="Inter, sans-serif" fontWeight={600} fill={INK}>1</text>
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
      // 一排里的格子：收进去的那扇窗，缩成卡片的位置。
      const cw = 14, ch = 13, x = w / 2 - cw / 2, y = NOTCH.h + 2.6;
      return (
        <g>
          <rect x={x} y={y} width={cw} height={ch} rx={1.6} fill="#171a20" stroke="rgba(255,255,255,.35)" strokeWidth={SW} opacity={l.first} />
          <line {...line} opacity={l.second} x1={x} x2={x + cw * 0.7} y1={y + ch + 2} y2={y + ch + 2} strokeWidth={0.8} />
        </g>
      );
    }
    case 'stroke': {
      // 刚才那一笔，原样落在刘海里；第二层是说话的波形（只是示意）。
      const sx = (x: number) => 6 + ((x - 22) / 56) * (w - 12);
      const sy = (y: number) => NOTCH.h + 2 + ((y - 30) / 40) * 9;
      const d = STROKE.map((p, i) => `${i ? 'L' : 'M'} ${sx(p.x).toFixed(2)} ${sy(p.y).toFixed(2)}`).join(' ');
      const bars = 36;
      return (
        <g>
          <path {...line} d={d} strokeWidth={0.5} opacity={l.first} />
          <g opacity={l.second}>
            {Array.from({ length: bars }, (_, i) => {
              const x = 8 + (i / (bars - 1)) * (w - 16);
              const t = l.since - 24 - i * 1.5;
              const env = clamp01(t / 20) * (1 - clamp01((t - 200) / 30));
              const amp = env * (0.5 + 0.5 * Math.abs(Math.sin(i * 1.7 + t * 0.21) * Math.cos(i * 0.6 - t * 0.13))) * 2.4;
              return <line key={i} {...line} stroke={DIM} x1={x} x2={x} y1={h - 3.6 - amp} y2={h - 3.6 + amp} strokeWidth={0.45} />;
            })}
          </g>
        </g>
      );
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
const CJK = '"Source Han Sans SC","Noto Sans SC","PingFang SC",sans-serif';
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
  const size = 6, x = 2.2, y = h - 2 - size;
  return (
    <>
      <g opacity={l.first} transform={`translate(${x + size / 2} ${y + size / 2})`}>{icon}</g>
      <text opacity={l.first} x={x + size + 1.6} y={y + 2.9} fontFamily={CJK} fontWeight={600} fontSize={2.3} fill="#fff">{title}</text>
      <text opacity={l.second} x={x + size + 1.6} y={y + 5.5} fontFamily={CJK} fontSize={1.7} fill="rgba(255,255,255,.62)">{detail}</text>
    </>
  );
}

function tile(glyph: ReactNode) {
  return (
    <g>
      <rect x={-3} y={-3} width={6} height={6} rx={1.44} fill="url(#tile)" stroke="rgba(255,255,255,.18)" strokeWidth={0.12} />
      <g transform="scale(1.15)">{glyph}</g>
    </g>
  );
}

function drawReal(l: ContentLayer, w: number, h: number): ReactNode {
  switch (l.content) {
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
      const cw = 15.8, ch = 11, x = w / 2 - cw / 2, y = NOTCH.h + 1.8;
      return (
        <g>
          <g opacity={l.first}>
            <rect x={x} y={y} width={cw} height={ch} rx={2.8} fill="#1c1d22" stroke="rgba(255,255,255,.1)" strokeWidth={0.12} />
            <path d={`M ${x} ${y + 2.8} A 2.8 2.8 0 0 1 ${x + 2.8} ${y} L ${x + cw - 2.8} ${y} A 2.8 2.8 0 0 1 ${x + cw} ${y + 2.8} L ${x + cw} ${y + 2.2} L ${x} ${y + 2.2} Z`} fill="#2c2e35" />
            {[0, 1, 2].map((i) => <rect key={i} x={x + 1.6} y={y + 3.6 + i * 1.7} width={[9, 7, 10][i]} height={0.7} rx={0.35} fill={i ? 'rgba(215,219,227,.4)' : 'rgba(143,209,143,.7)'} />)}
            <text x={x} y={y + ch + 2.7} fontFamily={CJK} fontWeight={600} fontSize={2} fill="#fff">终端</text>
          </g>
          <text opacity={l.second} x={x} y={y + ch + 5} fontFamily={CJK} fontSize={1.5} fill="rgba(255,255,255,.62)">收进刘海</text>
        </g>
      );
    }
    case 'stroke': {
      const base = draw(l, w, h);
      const said = clamp01((l.since - 260) / 11);
      return (
        <g>
          <g opacity={1 - said}>{base}</g>
          <g opacity={said * l.second}>
            {draw({ ...l, second: 0 }, w, h)}
            <text x={w / 2} y={h - 2.6} textAnchor="middle" fontFamily={CJK} fontSize={2.3} fontWeight={600} fill="#fff">核对三处引文</text>
          </g>
        </g>
      );
    }
    case 'focus':
      return ears(l, w,
        <g><circle {...line} r={1.4} stroke="rgba(255,255,255,.18)" strokeWidth={0.4} /><circle {...line} r={1.4} stroke="#ff6b5e" strokeWidth={0.4} /></g>,
        <text x={0} y={0.7} textAnchor="middle" fontFamily={CJK} fontWeight={600} fontSize={1.8} fill="#fff">25 分</text>);
    default:
      return draw(l, w, h);
  }
}
