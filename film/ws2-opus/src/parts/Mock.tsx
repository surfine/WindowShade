// 画出来的界面，照 macOS Golden Gate 深色外观：系统字体（SF、苹方）、本机自带的墙纸和 App 图标（public/，从 /System 转出）。
// 窗口、菜单栏的比例按系统；为了 1080p 上看得清，整套界面放大约 1.6 倍（标题栏 5cqw ≈ 系统 52pt × 1.6）。尺寸用 cqw（屏宽的百分之一）。
import type { CSSProperties, ReactNode } from 'react';
import { Img, staticFile } from 'remotion';
import type { Rect } from '../layout';
import { pt } from '../motion/site';
import { ICON_SIZE, LAUNCH_APPS, iconCenter } from '../scene';

export const CJK = '"PingFang SC",-apple-system,system-ui,sans-serif';
const MONO = 'ui-monospace,"SF Mono",Menlo,monospace';
const C = {
  win: '#1f1f22', bar: '#1f1f22', ink: '#f5f5f7', muted: 'rgba(235,235,245,.55)', line: 'rgba(255,255,255,.09)',
  accent: '#0a84ff',
};
/** 墙纸没加载出来时的底色（Radial Sky Blue 的主色）。 */
export const WALL = '#0b1624';

/** 本机自带的墙纸 Radial Sky Blue（/System/Library/Desktop Pictures）。blur / dim 给锁屏和主屏幕用。 */
export function Wallpaper({ blur = 0, dim = 0, scale = 1, opacity = 1 }: { blur?: number; dim?: number; scale?: number; opacity?: number }) {
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: WALL, opacity }}>
      <Img src={staticFile('wall/radial-sky-blue.jpg')} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', filter: blur ? `blur(${blur}px) saturate(1.2)` : undefined, transform: `scale(${scale * (blur ? 1.08 : 1)})` }} />
      {dim > 0 && <div style={{ position: 'absolute', inset: 0, background: `rgba(0,0,0,${dim})` }} />}
    </div>
  );
}

type Box = { rect: Rect; cqw: number; sw: number; sh: number };
const place = ({ rect, sw, sh }: Box): CSSProperties => ({
  position: 'absolute', left: (rect.x / 100) * sw, top: (rect.y / 100) * sh, width: (rect.w / 100) * sw, height: (rect.h / 100) * sh,
});

const APPLE = 'M17.05 12.54c-.03-2.6 2.13-3.86 2.23-3.92-1.22-1.78-3.11-2.02-3.78-2.05-1.6-.17-3.13.95-3.95.95-.82 0-2.07-.93-3.41-.9-1.75.03-3.37 1.02-4.27 2.59-1.83 3.17-.47 7.85 1.31 10.42.87 1.26 1.9 2.67 3.25 2.62 1.31-.05 1.8-.84 3.38-.84 1.57 0 2.02.84 3.4.81 1.41-.02 2.3-1.27 3.15-2.54 1-1.46 1.41-2.88 1.43-2.95-.03-.01-2.71-1.04-2.74-4.19zM14.47 4.89c.72-.88 1.21-2.09 1.07-3.3-1.04.04-2.3.69-3.04 1.56-.66.77-1.25 2.01-1.09 3.19 1.15.09 2.33-.59 3.06-1.45z';

/** 菜单栏：樣片 HW.mb = 57.3 px（34 pt），字 21.9 px（13 pt）。 */
export function MenuBar({ cqw, h }: { cqw: number; h: number }) {
  const items = ['文本编辑', '文件', '编辑', '格式', '显示', '窗口', '帮助'];
  const H = Math.max(h, (57.3 / 2880) * 100) * cqw, f = pt(13) * cqw, ic = pt(13) * cqw;
  const glyph = (d: ReactNode, w = 1) => <svg width={ic * w} height={ic} viewBox={`0 0 ${24 * w} 24`} fill="#fff">{d}</svg>;
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, right: 0, height: H, display: 'flex', alignItems: 'center', gap: 1.35 * cqw, padding: `0 ${1.25 * cqw}px 0 ${1.5 * cqw}px`, fontFamily: CJK, fontSize: f, color: '#fff', whiteSpace: 'nowrap', background: 'linear-gradient(rgba(0,0,0,.28), rgba(0,0,0,0))', textShadow: '0 0 6px rgba(0,0,0,.25)' }}>
      <svg width={ic * 0.9} height={ic} viewBox="0 0 24 24" fill="#fff" style={{ marginRight: 0.3 * cqw }}><path d={APPLE} /></svg>
      {items.map((m, i) => <span key={m} style={{ fontWeight: i ? 500 : 700 }}>{m}</span>)}
      <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 1.15 * cqw }}>
        {glyph(<g><path d="M12 18.6a1.7 1.7 0 1 1 0 3.4 1.7 1.7 0 0 1 0-3.4z" /><path d="M12 13.2c2 0 3.8.8 5.1 2.1l-1.6 1.6A5 5 0 0 0 12 15.4a5 5 0 0 0-3.5 1.5l-1.6-1.6A7.2 7.2 0 0 1 12 13.2z" /><path d="M12 7.8c3.5 0 6.6 1.4 8.9 3.7l-1.6 1.6A10.3 10.3 0 0 0 12 10a10.3 10.3 0 0 0-7.3 3.1l-1.6-1.6A12.5 12.5 0 0 1 12 7.8z" /><path d="M12 2.4c5 0 9.4 2 12.7 5.3l-1.6 1.6A15.6 15.6 0 0 0 12 4.6 15.6 15.6 0 0 0 .9 9.3L-.7 7.7A17.8 17.8 0 0 1 12 2.4z" /></g>)}
        {glyph(<g><rect x={1} y={6} width={30} height={13} rx={4} fill="none" stroke="#fff" strokeOpacity={0.55} strokeWidth={1.4} /><rect x={3.2} y={8.2} width={21} height={8.6} rx={2.2} /><rect x={32.4} y={10} width={2} height={5} rx={1} fillOpacity={0.55} /></g>, 1.5)}
        {glyph(<g><rect x={2} y={4} width={20} height={7} rx={3.5} fill="none" stroke="#fff" strokeWidth={1.7} /><circle cx={17.5} cy={7.5} r={2.2} /><rect x={2} y={13} width={20} height={7} rx={3.5} fill="none" stroke="#fff" strokeWidth={1.7} /><circle cx={6.5} cy={16.5} r={2.2} /></g>)}
        <span style={{ fontWeight: 500 }}>10月4日 周日 9:41</span>
      </span>
    </div>
  );
}

/** 紅綠燈：樣片直徑 20 px、圓心距 33.7 px。 */
function Lights({ cqw, off }: { cqw: number; off?: boolean }) {
  const lamps = ['#ff5f57', '#febc2e', '#28c840'];
  const d = (20 / 1.684) ;
  const gap = (33.7 / 1.684) - d;
  return (
    <span style={{ display: 'flex', gap: pt(gap) * cqw }}>
      {lamps.map((a, i) => (
        <i key={i} style={{ width: pt(d) * cqw, height: pt(d) * cqw, borderRadius: '50%', background: off ? 'rgba(255,255,255,.16)' : a, boxShadow: off ? 'none' : 'inset 0 0 0 0.5px rgba(0,0,0,.22)' }} />
      ))}
    </span>
  );
}

/** 一扇窗：樣片標題欄高 52 px、圓角 22 px、字約 13 pt。 */
const BAR = 52 / 1.684;
const WIN_R = pt(22 / 1.684);
export function Win({ box, title, off, children, opacity = 1, scale = 1, radius = WIN_R }: { box: Box; title: string; off?: boolean; children?: ReactNode; opacity?: number; scale?: number; radius?: number }) {
  const { cqw } = box;
  return (
    <div style={{ ...place(box), opacity, transform: `scale(${scale})`, transformOrigin: '50% 50%', borderRadius: radius * cqw, overflow: 'hidden', background: C.win, color: C.ink, fontFamily: CJK, boxShadow: `inset 0 0 0 0.5px rgba(255,255,255,.14), 0 0 0 0.5px rgba(0,0,0,.7), 0 ${pt(off ? 8 : 18) * cqw}px ${pt(off ? 16 : 28) * cqw}px rgba(0,0,0,${off ? 0.35 : 0.45})` }}>
      <div style={{ position: 'relative', height: pt(BAR) * cqw, display: 'flex', alignItems: 'center', padding: `0 ${pt(16) * cqw}px`, background: C.bar, fontSize: pt(13) * cqw, fontWeight: 600, color: off ? C.muted : C.ink }}>
        <Lights cqw={cqw} off={off} />
        <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', whiteSpace: 'nowrap' }}>{title}</span>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: pt(BAR) * cqw, bottom: 0 }}>{children}</div>
    </div>
  );
}

/** 三处可读引文：短句 + 出处；变蓝时看得出核了对哪一句（审片 B11-02）。第三处的出处也在核对中被改对（审片 B13-01）。 */
const CITES: { before: string; after: string; src: string; srcBefore?: string }[] = [
  { before: '设计就是外观。', after: '设计不是看起来怎样，而是用起来怎样。', src: 'Jobs，2003' },
  { before: '动得越夸张越好。', after: '界面应当跟上手指。', src: 'Karunamuni，Fluid Interfaces' },
  { before: '刘海只是屏幕上的缺口。', after: '刘海是硬件和软件合成的同一层。', src: 'WWDC23 · 10194（转述）', srcBefore: 'WWDC 2022' },
];

/** 后面那扇“文章草稿”，不在前台。 */
export function DraftWin({ box, opacity, marks }: { box: Box; opacity?: number; marks?: number[] }) {
  const { cqw } = box;
  const tool = (label: string) => (
    <span style={{ fontSize: pt(12) * cqw, fontWeight: 600, color: 'rgba(235,235,245,.55)', padding: `0 ${0.8 * cqw}px` }}>{label}</span>
  );
  return (
    <Win box={box} title="文章草稿" off opacity={opacity}>
      <div style={{ height: pt(28) * cqw, display: 'flex', alignItems: 'center', gap: 0.4 * cqw, padding: `0 ${2.4 * cqw}px`, borderBottom: `0.5px solid ${C.line}`, background: 'rgba(255,255,255,.03)' }}>
        {tool('B')}{tool('I')}{tool('≡')}{tool('“ ”')}
        <span style={{ marginLeft: 'auto', fontSize: pt(11) * cqw, color: C.muted }}>核对三处引文</span>
      </div>
      <div style={{ padding: `${2.2 * cqw}px ${3.2 * cqw}px` }}>
        <div style={{ fontSize: pt(12) * cqw, fontWeight: 600, color: C.accent, letterSpacing: '.02em' }}>周四 · 专栏</div>
        <div style={{ fontSize: pt(22) * cqw, fontFamily: '"Songti SC","Noto Serif SC",serif', fontWeight: 500, lineHeight: 1.3, marginTop: pt(8) * cqw, color: C.ink }}>桌面空了，心也静了。</div>
        <div style={{ fontSize: pt(13) * cqw, lineHeight: 1.55, marginTop: pt(8) * cqw, color: 'rgba(235,235,245,.62)' }}>窗口收进刘海，不是最小化。下面三处引文要和出处对上。</div>
        <div style={{ display: 'grid', gap: 1.1 * cqw, marginTop: 2.2 * cqw }}>
          {CITES.map((c, i) => {
            const m = marks?.[i] ?? 0;
            const on = m > 0.55;
            return (
              <div key={c.src} style={{ fontSize: pt(14) * cqw, lineHeight: 1.4, fontWeight: 500, color: on ? C.accent : 'rgba(235,235,245,.78)' }}>
                {on ? c.after : c.before}
                <div style={{ fontSize: pt(11) * cqw, fontWeight: 500, color: on ? 'rgba(10,132,255,.75)' : C.muted, marginTop: 0.25 * cqw }}>{on ? c.src : c.srcBefore ?? c.src}</div>
              </div>
            );
          })}
        </div>
      </div>
    </Win>
  );
}

export function TermWin(p: { box: Box; opacity?: number; scale?: number; radius?: number; done?: boolean }) {
  const { cqw } = p.box;
  const rows = ['$ swift build', 'Compiling WindowShade', '[132/186] Notch.swift', p.done ? 'Build complete!' : '[133/186] SlideOver.swift'];
  return (
    <Win {...p} title="WindowShade — zsh — 80×24">
      <div style={{ position: 'absolute', inset: 0, background: '#1e1f24', color: '#d7dbe3', font: `${pt(13) * cqw}px/1.55 ${MONO}`, padding: `${pt(12) * cqw}px ${pt(14) * cqw}px` }}>
        {rows.map((r, i) => <div key={r} style={{ color: i && !(p.done && i === 3) ? undefined : '#8fd18f' }}>{r}</div>)}
        <div style={{ width: cqw, height: 2.2 * cqw, background: '#d7dbe3', marginTop: 0.4 * cqw }} />
      </div>
    </Win>
  );
}

export function NotesWin(p: { box: Box; opacity?: number; scale?: number; radius?: number }) {
  const { cqw } = p.box;
  const notes = ['采访提纲', '核对三处引文', '周五前交稿'];
  return (
    <Win {...p} title="备忘录">
      <div style={{ padding: `${3 * cqw}px ${2.6 * cqw}px`, display: 'grid', gap: 2.2 * cqw, fontSize: 1.9 * cqw }}>
        {notes.map((n) => (
          <div key={n} style={{ display: 'flex', alignItems: 'center', gap: 1.4 * cqw, whiteSpace: 'nowrap' }}>
            <i style={{ width: 1.6 * cqw, height: 1.6 * cqw, borderRadius: '50%', boxShadow: `inset 0 0 0 ${0.18 * cqw}px ${C.muted}`, flex: 'none' }} />{n}
          </div>
        ))}
      </div>
    </Win>
  );
}

/** 音乐：封面、两行字的位置、播放键。playing 之后播放键换成暂停。 */
export function MusicWin(p: { box: Box; opacity?: number; playing: boolean; scale?: number; radius?: number }) {
  const { cqw } = p.box;
  return (
    <Win {...p} title="音乐">
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 3 * cqw }}>
        <div style={{ width: 16 * cqw, height: 16 * cqw, borderRadius: 1.6 * cqw, background: 'linear-gradient(140deg,#ff9ec3,#ffd06a 55%,#7fd0ff)' }} />
        <i style={{ display: 'block', width: 12 * cqw, height: 1.1 * cqw, borderRadius: cqw, background: 'rgba(255,255,255,.5)', marginTop: 2.4 * cqw }} />
        <i style={{ display: 'block', width: 8 * cqw, height: 0.9 * cqw, borderRadius: cqw, background: C.line, marginTop: 1.2 * cqw }} />
        <svg width={4 * cqw} height={4 * cqw} viewBox="0 0 20 20" style={{ marginTop: 2.2 * cqw }}>
          {p.playing
            ? <g fill={C.ink}><rect x={5} y={4} width={3.4} height={12} rx={1} /><rect x={11.6} y={4} width={3.4} height={12} rx={1} /></g>
            : <path d="M6 3.8 L16 10 L6 16.2 Z" fill={C.ink} />}
        </svg>
      </div>
    </Win>
  );
}

export function ChatWin(p: { box: Box; opacity?: number; scale?: number; radius?: number }) {
  const { cqw } = p.box;
  const bubbles: [boolean, number][] = [[false, 62], [true, 48], [false, 70], [false, 40], [true, 56]];
  return (
    <Win {...p} title="聊天">
      <div style={{ padding: `${2.4 * cqw}px ${2 * cqw}px`, display: 'grid', gap: 1.3 * cqw }}>
        {bubbles.map(([mine, w], i) => (
          <i key={i} style={{ justifySelf: mine ? 'end' : 'start', width: `${w}%`, height: 3 * cqw, borderRadius: 1.5 * cqw, background: mine ? '#3a62c9' : '#3a3c42' }} />
        ))}
      </div>
    </Win>
  );
}

// 主屏幕上的图标：本机 /System/Applications 里各 App 自带的图标（public/icons/，sips 转成 PNG）。
export function AppIcon({ k, cqw, size }: { k: string; cqw: number; size: number }) {
  // 系统图标四周自带约 10% 的留白和投影，画大一点让图形本身和原来一样大。
  return <Img src={staticFile(`icons/${k}.png`)} style={{ width: size * 1.18 * cqw, height: size * 1.18 * cqw, display: 'block', margin: -size * 0.09 * cqw }} />;
}

/** 主屏幕：铺满屏，上面是“主屏幕 / App 资料库”，下面一排图标。拖走的那个不画。 */
export function HomeScreen({ cqw, sw, sh, opacity, hide }: { cqw: number; sw: number; sh: number; opacity: number; hide?: string }) {
  return (
    <div style={{ position: 'absolute', inset: 0, opacity, fontFamily: CJK }}>
      <Wallpaper blur={1.6 * cqw} dim={0.32} />
      <div style={{ position: 'absolute', top: 9 * cqw, left: '50%', transform: 'translateX(-50%)', display: 'flex', gap: 0.4 * cqw, padding: 0.4 * cqw, borderRadius: 99, background: 'rgba(255,255,255,.14)', boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,.22)' }}>
        {['主屏幕', 'App 资料库'].map((t, i) => (
          <span key={t} style={{ padding: `${0.7 * cqw}px ${1.8 * cqw}px`, borderRadius: 99, fontSize: 1.4 * cqw, fontWeight: 600, color: i ? 'rgba(255,255,255,.7)' : '#171a20', background: i ? 'transparent' : '#fff' }}>{t}</span>
        ))}
      </div>
      {LAUNCH_APPS.map((a, i) => {
        if (a.key === hide) return null;
        const c = iconCenter(i);
        return (
          <div key={a.key} style={{ position: 'absolute', left: (c.x / 100) * sw, top: (c.y / 100) * sh, transform: 'translate(-50%,-50%)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0.8 * cqw }}>
            <AppIcon k={a.key} cqw={cqw} size={ICON_SIZE} />
            <span style={{ fontSize: 1.4 * cqw, color: 'rgba(255,255,255,.9)', position: 'absolute', top: (ICON_SIZE + 0.8) * cqw, whiteSpace: 'nowrap' }}>{a.name}</span>
          </div>
        );
      })}
    </div>
  );
}
