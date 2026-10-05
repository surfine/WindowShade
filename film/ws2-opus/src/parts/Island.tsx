import type { ReactNode } from 'react';
import { islandAt, layersAt, type ContentLayer } from '../island';
import { NOTCH, clamp01 } from '../motion/site';
import { COUNTDOWN, type Content } from '../timeline';
import { STROKE } from '../scene';

const INK = 'rgba(255,255,255,.92)';
const DIM = 'rgba(255,255,255,.5)';
const SW = 0.24; // 线宽，cqw

/**
 * 黑色的岛 / 半岛：上沿贴着屏幕（传感器），宽、高、圆角来自同一次模拟。
 * compact = 岛（两耳）；alert/expanded = 往下鼓（提醒或半岛展开）。无空白额头；不画箭头指刘海。
 * 本体不做透明度。里面只放线稿。尺寸是影片布局值，见 docs/design-drafts/一颗岛.html。
 */
export function Island({ frame, cqw }: { frame: number; cqw: number }) {
  const s = islandAt(frame);
  const layers = layersAt(frame);
  return (
    <div
      style={{
        position: 'absolute', top: 0, left: '50%', width: s.w * cqw, height: s.h * cqw,
        transform: 'translateX(-50%)', background: '#000', overflow: 'hidden',
        borderBottomLeftRadius: s.r * cqw, borderBottomRightRadius: s.r * cqw,
      }}
    >
      <svg width={s.w * cqw} height={s.h * cqw} viewBox={`0 0 ${s.w} ${s.h}`} style={{ position: 'absolute', inset: 0 }}>
        {layers.map((l, i) => <g key={`${l.content}-${i}`}>{draw(l, s.w, s.h)}</g>)}
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
  // alert：硬件刘海下面短下鼓（半岛矮档示意）；左边符号、右边两行——相对位置继承紧凑两耳（只画长短，不写字）。
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
