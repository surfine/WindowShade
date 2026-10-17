// 整块屏幕（1710×1107 pt）。窗口全是真实的 WindowShade 截图；刘海按本机实测几何画，肩始终保留；
// 刷脸、读唇、点头按 D1 用刘海小岛的语言画成产品界面（不画 Face ID 图形，也不画系统的解锁界面）。
import type { CSSProperties, ReactNode } from 'react';
import { Img, staticFile } from 'remotion';
import { FPS, HW, seg, smooth } from './motion';
import {
  APPS, T, appSlot, appState, browseWin, effectsWin, islandAt, islandContent, launchBackdrop, lockAmount, pointer, shadeWin, WIN,
  type WinState,
} from './plan';
import { notchPath } from './motion';

const SANS = '"PingFang SC","SF Pro Text",-apple-system,sans-serif';
const DISPLAY = '"SF Pro Display","PingFang SC",-apple-system,sans-serif';

function Win({ src, r, shadow = 1 }: { src: string; r: WinState; shadow?: number }) {
  if (r.o <= 0) return null;
  const rad = Math.min(12, r.w * 0.03, r.h * 0.3);
  return (
    <div style={{ position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h, borderRadius: rad, overflow: 'hidden', opacity: r.o,
      boxShadow: `0 ${10 * shadow}px ${40 * shadow}px rgba(0,0,0,${0.45 * shadow}), 0 0 0 0.5px rgba(255,255,255,.12)` }}>
      <Img src={staticFile(src)} style={{ width: '100%', height: '100%', display: 'block' }} />
    </div>
  );
}

function MenuBar({ dim }: { dim: number }) {
  const item: CSSProperties = { fontFamily: SANS, fontSize: 13.5, color: 'rgba(255,255,255,.92)', fontWeight: 500 };
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: 1710, height: HW.h, background: 'rgba(10,14,24,.28)', backdropFilter: 'blur(20px)',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 18px', opacity: 1 - dim * 0.7 }}>
      <div style={{ display: 'flex', gap: 20, ...item }}><b style={{ fontWeight: 700 }}>WindowShade</b><span>文件</span><span>编辑</span><span>窗口</span></div>
      <div style={{ display: 'flex', gap: 18, ...item }}><span>10月18日 周六</span><span>9:41</span></div>
    </div>
  );
}

function Pointer({ t }: { t: number }) {
  const p = pointer(t);
  if (p.o <= 0) return null;
  const s = 1 - 0.12 * p.down;
  return (
    <svg width={26} height={36} viewBox="0 0 26 36" style={{ position: 'absolute', left: p.x - 3, top: p.y - 2, opacity: p.o, transform: `scale(${s})`, transformOrigin: '3px 2px', filter: 'drop-shadow(0 2px 3px rgba(0,0,0,.35))' }}>
      <path d="M3 2 L3 27 L9.2 21.4 L13.4 31.2 L17.6 29.4 L13.5 19.8 L21.6 19.8 Z" fill="#000" stroke="#fff" strokeWidth={1.8} strokeLinejoin="round" />
    </svg>
  );
}

const Sym = ({ name, size, tint = 1, style }: { name: string; size: number; tint?: number; style?: CSSProperties }) => (
  <Img src={staticFile(`sym/${name}.png`)} style={{ width: size, height: size, objectFit: 'contain', filter: tint ? 'invert(1)' : 'none', ...style }} />
);

function Island({ t, f }: { t: number; f: number }) {
  const s = islandAt(f);
  const { c, o } = islandContent(t);
  const L = HW.cx - s.w / 2;
  const top = HW.h;
  const body = (children: ReactNode) => (
    <div style={{ position: 'absolute', left: L, top: 0, width: s.w, height: s.h, opacity: o, filter: `blur(${((1 - o) * 4).toFixed(2)}px)`,
      transform: `translateY(${((1 - o) * 4).toFixed(2)}px)`, fontFamily: SANS, color: '#fff' }}>{children}</div>
  );
  const ears = (left: ReactNode, right: ReactNode) => body(
    <>
      <div style={{ position: 'absolute', left: 10, top: 0, height: HW.h, display: 'flex', alignItems: 'center', gap: 6 }}>{left}</div>
      <div style={{ position: 'absolute', right: 12, top: 0, height: HW.h, display: 'flex', alignItems: 'center', gap: 6 }}>{right}</div>
    </>,
  );
  let content: ReactNode = null;
  if (c === 'count') {
    content = ears(
      <div style={{ width: 16, height: 12, borderRadius: 3, border: '1.6px solid rgba(255,255,255,.85)', borderTopWidth: 3.2 }} />,
      <span style={{ fontSize: 15, fontWeight: 650, fontVariantNumeric: 'tabular-nums' }}>1</span>,
    );
  } else if (c === 'shelf') {
    content = body(
      <div style={{ position: 'absolute', left: 0, right: 0, top: top + 10, display: 'flex', justifyContent: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 10, borderRadius: 18, background: 'rgba(255,255,255,.08)' }}>
          <div style={{ width: 132, height: 100, borderRadius: 8, overflow: 'hidden' }}><Img src={staticFile('ui/settings-shade.png')} style={{ width: '100%', height: '100%' }} /></div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <span style={{ fontSize: 16, fontWeight: 600 }}>WindowShade 设置</span>
            <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,.6)' }}>点一下放回原处</span>
          </div>
        </div>
      </div>,
    );
  } else if (c === 'drop') {
    const hot = seg(t, T.slide[0] + 0.25, T.slide[0] + 0.45);
    const cell = (label: string, i: number, on: number) => (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, opacity: 0.75 + on * 0.25 }}>
        <div style={{ width: 92, height: 52, borderRadius: 9, border: `1.5px solid rgba(255,255,255,${0.35 + on * 0.5})`, background: `rgba(255,255,255,${0.04 + on * 0.18})`, position: 'relative' }}>
          <div style={{ position: 'absolute', top: 5, bottom: 5, left: i === 2 ? 48 : 5, right: i === 0 ? 48 : 5, borderRadius: 5, background: `rgba(255,255,255,${0.35 + on * 0.5})` }} />
        </div>
        <span style={{ fontSize: 12.5 }}>{label}</span>
      </div>
    );
    content = body(
      <div style={{ position: 'absolute', left: 0, right: 0, top: top + 8, display: 'flex', justifyContent: 'center', gap: 30 }}>
        {cell('左半屏', 0, 0)}{cell('铺满', 1, 0)}{cell('右半屏', 2, hot)}
      </div>,
    );
  } else if (c === 'activity') {
    content = body(
      <div style={{ position: 'absolute', left: 18, right: 20, top: top + 10, display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ width: 40, height: 40, borderRadius: 12, background: '#2f9e5b', display: 'grid', placeItems: 'center' }}>
          <Sym name="iphone" size={22} />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
          <span style={{ fontSize: 16, fontWeight: 600 }}>外卖 · 骑手已取餐</span>
          <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,.62)' }}>来自 iPhone · 约 12 分钟送达</span>
        </div>
        <span style={{ fontFamily: DISPLAY, fontSize: 28, fontWeight: 650, color: '#4cd27f', fontVariantNumeric: 'tabular-nums' }}>12′</span>
      </div>,
    );
  } else if (c === 'away') {
    const n = t < T.ticks[1] ? 3 : t < T.ticks[2] ? 2 : 1;
    const ring = seg(t, T.away + 0.4, T.lock);
    content = ears(
      <span style={{ fontSize: 13.5, fontWeight: 600 }}>离开</span>,
      <div style={{ position: 'relative', width: 22, height: 22 }}>
        <svg width={22} height={22} viewBox="0 0 22 22" style={{ position: 'absolute', inset: 0 }}>
          <circle cx={11} cy={11} r={9} fill="none" stroke="rgba(255,255,255,.25)" strokeWidth={2.2} />
          <circle cx={11} cy={11} r={9} fill="none" stroke="#ff9f0a" strokeWidth={2.2} strokeDasharray={`${(1 - ring) * 56.5} 60`} transform="rotate(-90 11 11)" strokeLinecap="round" />
        </svg>
        <span style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', fontSize: 11.5, fontWeight: 700 }}>{t >= T.ticks[0] ? n : ''}</span>
      </div>,
    );
  } else if (c === 'lock') {
    content = ears(<Sym name="lock.fill" size={15} />, <span style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,.8)' }}>已锁</span>);
  } else if (c === 'verify') {
    const face = t >= T.face, phone = t >= T.phone, done = t >= T.phone + 0.35;
    const tick = (on: boolean, at: number) => (
      <div style={{ width: 20, height: 20, display: 'grid', placeItems: 'center' }}>
        {on ? <Sym name="checkmark.circle.fill" size={20} tint={0} style={{ filter: 'invert(62%) sepia(60%) saturate(500%) hue-rotate(85deg)', transform: `scale(${0.6 + 0.4 * smooth(seg(t, at, at + 0.18))})` }} />
          : <div style={{ width: 14, height: 14, borderRadius: 7, border: '2px solid rgba(255,255,255,.35)', borderTopColor: '#fff', transform: `rotate(${(t * 360 * 1.4) % 360}deg)` }} />}
      </div>
    );
    content = body(
      <>
        <div style={{ position: 'absolute', left: 12, top: 0, height: HW.h, display: 'flex', alignItems: 'center', gap: 7 }}>
          <div style={{ width: 8, height: 8, borderRadius: 4, background: '#32d74b', boxShadow: '0 0 6px #32d74b' }} />
          <span style={{ fontSize: 12.5, color: 'rgba(255,255,255,.75)' }}>相机</span>
        </div>
        <div style={{ position: 'absolute', left: 0, right: 0, top: top + 6, display: 'flex', justifyContent: 'center', gap: 34, alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>{tick(face, T.face)}<span style={{ fontSize: 15, fontWeight: 600 }}>{done ? '认出你' : face ? '是你' : '正在认你'}</span></div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>{tick(phone, T.phone)}<Sym name="iphone" size={16} /><span style={{ fontSize: 15, fontWeight: 600 }}>iPhone 在旁边</span></div>
        </div>
      </>,
    );
  } else if (c === 'lips') {
    const text = '放到左半屏';
    const shown = Math.max(0, Math.min(text.length, Math.floor((t - T.char0) / T.charGap) + 1));
    const ok = t >= T.ok;
    const talk = t < T.lipsStop ? 1 - seg(t, T.lipsStop - 0.3, T.lipsStop) : 0;
    const bars = [0, 1, 2, 3, 4].map((i) => {
      const a = 0.35 + 0.65 * Math.abs(Math.sin(t * (7.1 + i * 1.3) + i * 1.7)) * talk;
      return <div key={i} style={{ width: 4, height: 6 + 20 * a, borderRadius: 2, background: ok ? '#32d74b' : 'rgba(255,255,255,.85)' }} />;
    });
    content = body(
      <>
        <div style={{ position: 'absolute', left: 22, top: top + 14, height: 40, display: 'flex', alignItems: 'center', gap: 3.5 }}>{bars}</div>
        <div style={{ position: 'absolute', left: 74, right: 18, top: top + 10, display: 'flex', flexDirection: 'column', gap: 4 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            {ok ? <Sym name="checkmark.circle.fill" size={22} tint={0} style={{ filter: 'invert(62%) sepia(60%) saturate(500%) hue-rotate(85deg)', transform: `scale(${0.6 + 0.4 * smooth(seg(t, T.ok, T.ok + 0.18))})` }} /> : null}
            <span style={{ fontSize: 24, fontWeight: 650, letterSpacing: 0.5 }}>
              {text.slice(0, shown)}
              {!ok && shown < text.length && t >= T.char0 - 0.3 ? <span style={{ opacity: Math.round((t * 2.5) % 1) ? 1 : 0.2 }}>▍</span> : null}
            </span>
          </div>
          <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,.6)', opacity: seg(t, T.sub, T.sub + 0.25) }}>{ok ? '已确认 · 正在放过去' : '点头确认 · 摇头取消'}</span>
        </div>
      </>,
    );
  }
  return (
    <>
      <svg width={1710} height={260} viewBox="0 -4 1710 260" style={{ position: 'absolute', left: 0, top: -4, overflow: 'visible' }}>
        <path d={notchPath(s)} fill="#000" />
      </svg>
      {content}
    </>
  );
}

function Launchpad({ t }: { t: number }) {
  const bd = launchBackdrop(t);
  if (bd <= 0.001 && t > T.lpOpen) return null;
  if (t < T.lpOpen) return null;
  return (
    <>
      {APPS.map(([icon, label], i) => {
        const a = appState(i, t);
        if (a.o <= 0) return null;
        const size = appSlot(i).size * a.s;
        return (
          <div key={icon} style={{ position: 'absolute', left: a.x - size / 2, top: a.y - size / 2, width: size, height: size, opacity: a.o }}>
            <Img src={staticFile(`icons/${icon}.png`)} style={{ width: '100%', height: '100%', filter: 'drop-shadow(0 8px 18px rgba(0,0,0,.35))' }} />
            <div style={{ position: 'absolute', top: size + 10, left: -40, right: -40, textAlign: 'center', fontFamily: SANS, fontSize: 17, color: '#fff', opacity: a.label, textShadow: '0 1px 4px rgba(0,0,0,.4)' }}>{label}</div>
          </div>
        );
      })}
    </>
  );
}

export function Screen({ f }: { f: number }) {
  const t = f / FPS;
  const lock = lockAmount(t);
  const bd = t >= T.lpOpen ? launchBackdrop(t) : 0;
  const blur = Math.max(lock * 22, bd * 16);
  const eff = effectsWin(t), shade = shadeWin(t), browse = browseWin(t);
  const raise = (r: WinState) => (r.z ? 1 : 0);
  const wins: { src: string; r: WinState; key: string }[] = [
    { key: 'panel', src: 'ui/window-browser.png', r: { ...WIN.panel, o: 1 } },
    { key: 'adv', src: 'ui/settings-advanced.png', r: { ...WIN.advanced, o: 1 } },
    { key: 'browse', src: 'ui/settings-browse.png', r: browse },
    { key: 'effects', src: 'ui/settings-effects.png', r: eff },
  ].sort((a, b) => raise(a.r) - raise(b.r));
  const shadeUnder = t >= T.untuck && t < T.untuck + 0.05; // 放回前一帧在刘海下面
  return (
    <div style={{ position: 'absolute', inset: 0, width: 1710, height: 1107, overflow: 'hidden', background: '#000', borderRadius: '14px 14px 2px 2px' }}>
      <div style={{ position: 'absolute', inset: 0, filter: blur > 0.05 ? `blur(${blur.toFixed(2)}px)` : undefined }}>
        <Img src={staticFile('ui/wall.jpg')} style={{ position: 'absolute', left: 0, top: 0, width: 1710, height: 1107 }} />
        {wins.map((w) => <Win key={w.key} src={w.src} r={w.r} shadow={w.r.z ? 1.3 : 1} />)}
        {shade.o > 0 && !shadeUnder ? <Win src="ui/settings-shade.png" r={shade} shadow={1.2} /> : null}
        <MenuBar dim={lock} />
      </div>
      {blur > 0.05 ? <div style={{ position: 'absolute', inset: 0, background: `rgba(4,6,12,${(lock * 0.5 + bd * 0.28).toFixed(3)})` }} /> : null}
      <Launchpad t={t} />
      <Pointer t={t} />
      <Island t={t} f={f} />
    </div>
  );
}

