// 画出来的界面。画法、配色、文案都照官网示意（site/style.css 深色、site/scripts/content.mjs、site/scripts/launchpad.mjs），
// 不另起一套。尺寸用 cqw（屏宽的百分之一）。
import type { CSSProperties, ReactNode } from 'react';
import type { Rect } from '../layout';
import { ICON_SIZE, LAUNCH_APPS, iconCenter } from '../scene';

export const CJK = '"Source Han Sans SC","Noto Sans SC","PingFang SC",sans-serif';
const MONO = 'ui-monospace,"SF Mono",Menlo,monospace';
const C = {
  win: '#26282d', bar: '#2d2f35', ink: '#eceef2', muted: '#a0a5ae', line: 'rgba(255,255,255,.08)',
  accent: '#7ea4ff', menubar: 'rgba(20,22,28,.45)',
};
export const WALL =
  'radial-gradient(120% 90% at 0% 0%,#233a6b 0%,transparent 58%),radial-gradient(90% 80% at 100% 0%,#4a2a55 0%,transparent 62%),radial-gradient(120% 90% at 70% 110%,#5a3a2a 0%,transparent 62%),#171a24';

type Box = { rect: Rect; cqw: number; sw: number; sh: number };
const place = ({ rect, sw, sh }: Box): CSSProperties => ({
  position: 'absolute', left: (rect.x / 100) * sw, top: (rect.y / 100) * sh, width: (rect.w / 100) * sw, height: (rect.h / 100) * sh,
});

/** 菜单栏：和刘海一样高，左边 App 菜单，右边时间。 */
export function MenuBar({ cqw, h }: { cqw: number; h: number }) {
  const items = ['文本编辑', '文件', '编辑', '格式', '显示', '窗口'];
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, right: 0, height: h * cqw, display: 'flex', alignItems: 'center', gap: 1.5 * cqw, padding: `0 ${1.6 * cqw}px`, fontFamily: CJK, fontSize: 0.56 * h * cqw, color: C.ink, background: C.menubar, whiteSpace: 'nowrap' }}>
      {items.map((m, i) => <span key={m} style={{ fontWeight: i ? 400 : 650, opacity: i ? 0.82 : 1 }}>{m}</span>)}
      <span style={{ marginLeft: 'auto', opacity: 0.9 }}>9:41</span>
    </div>
  );
}

function Lights({ cqw, off }: { cqw: number; off?: boolean }) {
  const lamps = [['#ea7468', '#e8928b'], ['#efbb50', '#f7d563'], ['#7cca4a', '#a6d989']];
  return (
    <span style={{ display: 'flex', gap: 1.2 * cqw }}>
      {lamps.map(([a, b], i) => (
        <i key={i} style={{ width: 1.95 * cqw, height: 1.95 * cqw, borderRadius: '50%', background: off ? '#4a4c52' : `linear-gradient(${a} 30%, ${b} 75%)` }} />
      ))}
    </span>
  );
}

/** 一扇窗：标题栏 5cqw、红绿灯、居中标题，圆角 2.6cqw。 */
export function Win({ box, title, off, children, opacity = 1, scale = 1, radius = 2.6 }: { box: Box; title: string; off?: boolean; children?: ReactNode; opacity?: number; scale?: number; radius?: number }) {
  const { cqw } = box;
  return (
    <div style={{ ...place(box), opacity, transform: `scale(${scale})`, transformOrigin: '50% 50%', borderRadius: radius * cqw, overflow: 'hidden', background: C.win, color: C.ink, fontFamily: CJK, boxShadow: `0 0 0 1px rgba(0,0,0,.85), 0 ${1.1 * cqw}px ${2.4 * cqw}px rgba(0,0,0,${off ? 0.36 : 0.5})` }}>
      <div style={{ position: 'relative', height: 5 * cqw, display: 'flex', alignItems: 'center', padding: `0 ${1.8 * cqw}px`, background: C.bar, boxShadow: `inset 0 -0.5px 0 ${C.line}`, fontSize: 1.85 * cqw, fontWeight: 600, color: off ? C.muted : C.ink }}>
        <Lights cqw={cqw} off={off} />
        <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', whiteSpace: 'nowrap' }}>{title}</span>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, top: 5 * cqw, bottom: 0 }}>{children}</div>
    </div>
  );
}

/** marks：每行末尾那处引文改好的程度（0–1），助手改过的地方标一小段强调色。 */
function Lines({ cqw, widths, marks = [] }: { cqw: number; widths: number[]; marks?: number[] }) {
  return (
    <div style={{ display: 'grid', gap: 1.5 * cqw, marginTop: 3 * cqw }}>
      {widths.map((w, i) => (
        <i key={i} style={{ position: 'relative', height: 0.9 * cqw, width: `${w}%`, borderRadius: cqw, background: C.line }}>
          {(marks[i] ?? 0) > 0 && <b style={{ position: 'absolute', right: 0, top: 0, bottom: 0, width: '22%', borderRadius: cqw, background: C.accent, opacity: 0.75 * marks[i] }} />}
        </i>
      ))}
    </div>
  );
}

/** 后面那扇“文章草稿”，不在前台。 */
export function DraftWin({ box, opacity, marks }: { box: Box; opacity?: number; marks?: number[] }) {
  const { cqw } = box;
  return (
    <Win box={box} title="文章草稿" off opacity={opacity}>
      <div style={{ padding: `${4 * cqw}px ${4.4 * cqw}px` }}>
        <div style={{ fontSize: 1.65 * cqw, fontWeight: 600, color: C.accent, letterSpacing: '.02em' }}>周四 · 专栏</div>
        <div style={{ fontSize: 4.6 * cqw, fontFamily: '"Songti SC","Noto Serif SC",serif', fontWeight: 500, lineHeight: 1.2, marginTop: 1.4 * cqw, color: C.ink, whiteSpace: 'nowrap' }}>桌面空了，<br />心也静了。</div>
        <Lines cqw={cqw} widths={[100, 92, 96, 58]} marks={marks} />
      </div>
    </Win>
  );
}

export function TermWin(p: { box: Box; opacity?: number; scale?: number; radius?: number; done?: boolean }) {
  const { cqw } = p.box;
  const rows = ['$ swift build', 'Compiling WindowShade', '[132/186] Notch.swift', p.done ? 'Build complete!' : '[133/186] SlideOver.swift'];
  return (
    <Win {...p} title="终端">
      <div style={{ position: 'absolute', inset: 0, background: '#1e1f24', color: '#d7dbe3', font: `${1.75 * cqw}px/1.7 ${MONO}`, padding: `${2.6 * cqw}px ${3 * cqw}px` }}>
        {rows.map((r, i) => <div key={r} style={{ color: i && !(p.done && i === 3) ? undefined : '#8fd18f' }}>{r}</div>)}
        <div style={{ width: cqw, height: 2.2 * cqw, background: '#d7dbe3', marginTop: 0.4 * cqw }} />
      </div>
    </Win>
  );
}

export function NotesWin(p: { box: Box; opacity?: number }) {
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
export function MusicWin(p: { box: Box; opacity?: number; playing: boolean }) {
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

// 启动台的六个原创图标（site/scripts/launchpad.mjs）与配色（site/launchpad.css）。
const ICON_PATHS: Record<string, string> = {
  mail: '<rect x="4" y="8" width="24" height="16" rx="3"/><path d="M5.5 10.5 16 18l10.5-7.5"/>',
  notes: '<rect x="7" y="5" width="18" height="22" rx="3"/><path d="M11.5 11.5h9M11.5 16h9M11.5 20.5h5"/>',
  calendar: '<rect x="5" y="7" width="22" height="20" rx="3"/><path d="M5 13h22M11 4.5v5M21 4.5v5"/>',
  photos: '<rect x="5" y="7" width="22" height="18" rx="3"/><circle cx="12" cy="14" r="2.4"/><path d="M6.5 22.5 14 17l5 4.5 4-3 3.5 3"/>',
  reference: '<path d="M6.5 6.5h9a3 3 0 0 1 3 3v16H9.5a3 3 0 0 1-3-3z"/><path d="M18.5 9.5h4a3 3 0 0 1 3 3v13h-7"/><path d="M11 12.5h5M11 17h5"/>',
  tools: Array.from({ length: 9 }, (_, i) => `<rect x="${5 + (i % 3) * 8}" y="${5 + Math.floor(i / 3) * 8}" width="6" height="6" rx="1.5" fill="currentColor" stroke="none"/>`).join(''),
};
const ICON_BG: Record<string, [string, string]> = {
  mail: ['linear-gradient(#5b9bff,#2f6ae0)', '#fff'],
  notes: ['linear-gradient(#ffd968,#f5b428)', '#7a4d05'],
  calendar: ['linear-gradient(#fff,#f2f3f7)', '#e0453a'],
  photos: ['linear-gradient(#ff9ec3,#ffd06a 55%,#7fd0ff)', '#fff'],
  reference: ['linear-gradient(#a99cff,#6c5ce0)', '#fff'],
  tools: ['linear-gradient(#9fb4cf,#6c7f9b)', '#fff'],
};
export function AppIcon({ k, cqw, size }: { k: string; cqw: number; size: number }) {
  const [bg, ink] = ICON_BG[k];
  return (
    <div style={{ width: size * cqw, height: size * cqw, borderRadius: '26%', background: bg, color: ink, display: 'grid', placeItems: 'center', boxShadow: `0 ${0.6 * cqw}px ${1.4 * cqw}px -${0.8 * cqw}px rgba(0,0,0,.6)` }}>
      <svg width="62%" height="62%" viewBox="0 0 32 32" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" dangerouslySetInnerHTML={{ __html: ICON_PATHS[k] }} />
    </div>
  );
}

/** 主屏幕：铺满屏，上面是“主屏幕 / App 资料库”，下面一排图标。拖走的那个不画。 */
export function HomeScreen({ cqw, sw, sh, opacity, hide }: { cqw: number; sw: number; sh: number; opacity: number; hide?: string }) {
  return (
    <div style={{ position: 'absolute', inset: 0, opacity, background: 'rgba(14,16,22,.96)', fontFamily: CJK }}>
      <div style={{ position: 'absolute', top: 9 * cqw, left: '50%', transform: 'translateX(-50%)', display: 'flex', gap: 0.4 * cqw, padding: 0.4 * cqw, borderRadius: 99, background: 'rgba(255,255,255,.12)' }}>
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
