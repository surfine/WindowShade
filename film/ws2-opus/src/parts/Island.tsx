import type { ReactNode } from 'react';
import { islandAt, layersAt, type ContentLayer } from '../island';
import { FADE_IN } from '../motion/direction';
import { NOTCH, SITE_NOTCH_H, clamp01 } from '../motion/site';
import { CLICK_ALLOW, COUNTDOWN, type Content } from '../timeline';
import { ASK_UI, DROP_CHOICES, DROP_UI, STROKE, SUMMARY_UI, dropDotAt, dropHoverAt, pointerAt, summaryHoverAt } from '../scene';

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
        {layers.map((l, i) => <g key={`${l.content}-${i}`}>{paint(l, s.w, s.h, frame)}</g>)}
      </svg>
    </div>
  );
}

const line = { fill: 'none', stroke: INK, strokeWidth: SW, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

// 两侧的小图标照官网画，按真机刘海高度和官网 5.4 的比例缩小。
const EAR = (NOTCH.h / SITE_NOTCH_H) * 1.25;

function ears(l: ContentLayer, w: number, left: ReactNode, right: ReactNode) {
  // compact：内容只在硬件刘海两边露出的那一截里。
  const ear = (w - NOTCH.w) / 2;
  const cy = NOTCH.h / 2;
  return (
    <>
      <g opacity={l.first} transform={`translate(${ear / 2} ${cy}) scale(${EAR})`}>{left}</g>
      <g opacity={l.second} transform={`translate(${w - ear / 2} ${cy}) scale(${EAR})`}>{right}</g>
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
const mouthGlyph = <path {...line} d="M -1.6 0 Q 0 -1.1 1.6 0 Q 0 1.3 -1.6 0 Z" />;
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
            <rect opacity={l.first} x={x + 0.3} y={top} width={pitch - 0.6} height={bottom - top} rx={1.6} fill={`rgba(255,255,255,${0.05 + 0.13 * on})`} />
            <g opacity={l.first} transform={`translate(${cx} ${top + (real ? 3.1 : (bottom - top) / 2)})`}>{dropGlyph(i, ink)}</g>
            {real && <text opacity={l.second} x={cx} y={bottom - 1.2} textAnchor="middle" fontFamily={CJK} fontSize={1.35} fontWeight={on > 0.5 ? 600 : 400} fill={ink}>{name}</text>}
          </g>
        );
      })}
      {/* 你正在拖（第 2 层），构建跑完只在次区域留一个点。 */}
      <circle cx={w / 2 + NOTCH.w / 2 + 1.6} cy={NOTCH.h / 2} r={0.5} fill="#7ea4ff" opacity={dot * l.first} />
    </g>
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
    case 'preview':
      return alertBody(l, dropGlyph(0, INK));
    case 'lips':
      return ears(l, w, mouthGlyph, <g>{[-0.9, 0, 0.9].map((x, i) => <circle key={i} cx={x} cy={0} r={0.3} fill={INK} opacity={l.since >= i * 15 ? 1 : 0.3} />)}</g>);
    case 'summary': {
      const { rowY, rowH, x } = SUMMARY_UI;
      return (
        <g>
          {[0, 1].map((i) => {
            const y = rowY + rowH * i;
            return (
              <g key={i} opacity={i ? l.second : l.first}>
                <rect x={x} y={y + 0.3} width={w - 2 * x} height={rowH - 0.6} rx={1.8} fill="rgba(255,255,255,.12)" opacity={hoverAmount(summaryHoverAt, frame, i)} />
                <g transform={`translate(${x + 3.6} ${y + rowH / 2})`}>{i ? chatGlyph : mouseGlyph}</g>
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
      const cw = 14, ch = 13, x = w / 2 - cw / 2, y = SITE_NOTCH_H + 2.6;
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
      const sy = (y: number) => SITE_NOTCH_H + 2 + ((y - 30) / 40) * 9;
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

function drawReal(l: ContentLayer, w: number, h: number, frame: number): ReactNode {
  switch (l.content) {
    case 'drop':
      return drawDrop(l, w, frame, true);
    case 'ask': {
      // 要你放行的事：一句问话，两个按钮。只认问话出现之后的那一下点。
      const { allow, deny } = ASK_UI;
      const size = 6, x = 2.2, y = SITE_NOTCH_H + 0.6;
      const p = pointerAt(frame);
      const pressed = p && frame >= CLICK_ALLOW - 12 && frame <= CLICK_ALLOW ? p.pressed : 0;
      return (
        <>
          <g opacity={l.first} transform={`translate(${x + size / 2} ${y + size / 2})`}>{tile(sessionGlyph)}</g>
          <text opacity={l.first} x={x + size + 1.6} y={y + 2.9} fontFamily={CJK} fontWeight={600} fontSize={2.3} fill="#fff">允许改文章草稿？</text>
          <text opacity={l.second} x={x + size + 1.6} y={y + 5.5} fontFamily={CJK} fontSize={1.7} fill="rgba(255,255,255,.62)">Claude · 核对三处引文</text>
          <g opacity={l.second}>
            <rect x={deny.x} y={deny.y} width={deny.w} height={deny.h} rx={deny.h / 2} fill="rgba(255,255,255,.12)" />
            <text x={deny.x + deny.w / 2} y={deny.y + deny.h / 2 + 0.6} textAnchor="middle" fontFamily={CJK} fontSize={1.7} fill="#fff">不允许</text>
            <rect x={allow.x} y={allow.y} width={allow.w} height={allow.h} rx={allow.h / 2} fill="#7ea4ff" />
            <rect x={allow.x} y={allow.y} width={allow.w} height={allow.h} rx={allow.h / 2} fill="#fff" opacity={0.28 * pressed} />
            <text x={allow.x + allow.w / 2} y={allow.y + allow.h / 2 + 0.6} textAnchor="middle" fontFamily={CJK} fontWeight={600} fontSize={1.7} fill="#0b1630">允许</text>
          </g>
        </>
      );
    }
    case 'cited':
      return alertReal(l, h, tile(sessionGlyph), '引文已核对', '改了 3 处 · 文章草稿');
    case 'preview':
      return alertReal(l, h, tile(dropGlyph(0, INK)), '左半屏', '文章草稿 · 点头确认');
    case 'lips':
      // 读口型：左边是嘴，右边三个点随说出的字一个个亮。
      return ears(l, w,
        <g transform="scale(1.1)">{mouthGlyph}</g>,
        <g>{[-1.1, 0, 1.1].map((x, i) => <circle key={i} cx={x} cy={0} r={0.4} fill="#fff" opacity={l.since >= i * 15 ? 1 : 0.25} />)}</g>);
    case 'summary': {
      const { titleY, rowY, rowH, x } = SUMMARY_UI;
      const rows = [
        { icon: mouseGlyph, title: '妙控鼠标电量低', detail: '还剩 10%，记得充电' },
        { icon: chatGlyph, title: '聊天', detail: '3 条新消息' },
      ];
      return (
        <g>
          <text opacity={l.first} x={x + 0.8} y={titleY} fontFamily={CJK} fontWeight={600} fontSize={1.6} fill="rgba(255,255,255,.62)">离开期间</text>
          {rows.map((r, i) => {
            const y = rowY + rowH * i;
            return (
              <g key={r.title} opacity={i ? l.second : l.first}>
                <rect x={x} y={y + 0.3} width={w - 2 * x} height={rowH - 0.6} rx={1.8} fill="rgba(255,255,255,.12)" opacity={hoverAmount(summaryHoverAt, frame, i)} />
                <g transform={`translate(${x + 3.6} ${y + rowH / 2}) scale(0.85)`}>{tile(r.icon)}</g>
                <text x={x + 7.6} y={y + rowH / 2 - 0.25} fontFamily={CJK} fontWeight={600} fontSize={2.1} fill="#fff">{r.title}</text>
                <text x={x + 7.6} y={y + rowH / 2 + 2.15} fontFamily={CJK} fontSize={1.6} fill="rgba(255,255,255,.62)">{r.detail}</text>
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
      const cw = 15.8, ch = 11, x = w / 2 - cw / 2, y = SITE_NOTCH_H + 1.8;
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
      const base = draw(l, w, h, frame);
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
      return draw(l, w, h, frame);
  }
}
