// iPhone 的 CarPlay，开在这台 Mac 上：刘海展开成整块屏，刘海下面就是 CarPlay（深色）。
// 单位是屏幕点；容器 1710 × (1107 − 刘海高)，左上角在刘海下沿。
import type { ReactNode } from 'react';
import { Img } from 'remotion';
import { ICON, PLATE } from './assets';
import { AirPods, CJK, Check, SF, SFD } from './glyphs';
import { NOTCH_PT, PT } from './shape';
import { clamp01, fade, mix, seg, smooth, spring } from './time';

/** 刘海开始展开（落拍前 12 帧）；内容在落拍后长出来。 */
export const CP_IN = 2268;
/** 指针点「下一首」。 */
export const CP_NEXT = 2430;
/** 问要不要导航回家；点头；好了。 */
export const CP_ASK = 2520, CP_NOD = 2572, CP_OK = 2604;
/** Esc：内容先收，刘海随后收回。 */
export const CP_ESC = 2868;

export const CP_H = PT.h - NOTCH_PT.h;
const G = 16;
const SIDE = { x: 14, y: 14, w: 104, h: CP_H - 28 };
const MAP = { x: 134, y: 14, w: 980, h: CP_H - 28 };
const NP = { x: MAP.x + MAP.w + G, y: 14, w: PT.w - 14 - (MAP.x + MAP.w + G), h: (CP_H - 28 - G) / 2 };
const AG = { ...NP, y: NP.y + NP.h + G };
/** 「下一首」按钮在屏幕上的位置（给指针用）。 */
export const NEXT_BTN = { x: NP.x + NP.w / 2 + 112, y: NOTCH_PT.h + NP.y + NP.h - 86 };

const tile = { position: 'absolute' as const, background: 'linear-gradient(#242427,#1c1c1e)', borderRadius: 34, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.06)', overflow: 'hidden' };

function appear(f: number, i: number) {
  const p = spring(f, CP_IN + 8 + i * 4, 0.9, 0.45);
  return { opacity: clamp01(p * 1.4), transform: `scale(${mix(0.94, 1, p)})` };
}
const box = (r: { x: number; y: number; w: number; h: number }) => ({ left: r.x, top: r.y, width: r.w, height: r.h });

export function CarPlay({ f }: { f: number }) {
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: PT.w, height: CP_H, background: '#000', fontFamily: SF, color: '#fff', overflow: 'hidden' }}>
      <div style={{ position: 'absolute', ...box(SIDE), display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20, ...appear(f, 0) }}>
        <div style={{ fontFamily: SFD, fontSize: 30, fontWeight: 600, marginTop: 8 }}>21:42</div>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 18, fontWeight: 600, opacity: 0.9 }}>
          <svg width={22} height={14} viewBox="0 0 18 12">{[0, 1, 2, 3].map((i) => <rect key={i} x={i * 4.6} y={9 - i * 3} width={3.2} height={3 + i * 3} rx={0.8} fill="#fff" />)}</svg>5G
        </div>
        {(['maps', 'music', 'messages'] as const).map((k) => <Img key={k} src={ICON[k]} style={{ width: 84, height: 84 }} />)}
        <div style={{ marginTop: 'auto', marginBottom: 6, width: 76, height: 76, borderRadius: 22, background: 'rgba(255,255,255,.12)', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, padding: 17 }}>
          {[0, 1, 2, 3].map((i) => <i key={i} style={{ borderRadius: 5, background: '#fff', opacity: i === 0 ? 1 : 0.85 }} />)}
        </div>
      </div>
      <div style={{ ...tile, ...box(MAP), ...appear(f, 1) }}><MapTile f={f} /></div>
      <div style={{ ...tile, ...box(NP), ...appear(f, 2) }}><NowPlaying f={f} /></div>
      <div style={{ ...tile, ...box(AG), ...appear(f, 3) }}><Agent f={f} /></div>
      <Ask f={f} />
    </div>
  );
}

const ROUTE = 'M 400 1100 L 410 470 Q 412 440 444 441 L 760 452 Q 790 453 792 424 L 800 -200';

function MapTile({ f }: { f: number }) {
  const t = (f - CP_IN) / 60;
  const go = smooth(seg(f, CP_OK + 10, CP_OK + 80));
  const pan = t * 6 + go * 30;
  const meters = Math.max(50, 300 - Math.floor(Math.max(0, f - CP_OK - 80) / 60 * 18 / 10) * 10);
  const card = spring(f, CP_OK + 30, 0.88, 0.42);
  const sugg = 1 - smooth(seg(f, CP_OK, CP_OK + 16));
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#1d2126' }}>
      <svg width="100%" height="100%" viewBox="0 0 980 1046" preserveAspectRatio="xMidYMid slice" style={{ position: 'absolute', inset: 0 }}>
        <g transform={`translate(${-pan * 0.4} ${pan}) rotate(-8 490 520)`}>
          <rect x={-300} y={-500} width={1600} height={2000} fill="#1d2126" />
          <path d="M -300 260 C 100 230 300 120 640 20 L 1300 -180 L 1300 -500 L -300 -500 Z" fill="#17283a" />
          <rect x={620} y={620} width={300} height={220} rx={24} fill="#1b2a22" />
          <rect x={60} y={700} width={220} height={170} rx={20} fill="#1b2a22" />
          {[-200, -40, 120, 280, 440, 600, 760, 920, 1080, 1240].map((y) => <line key={y} x1={-300} y1={y} x2={1300} y2={y + 50} stroke="#2b3037" strokeWidth={12} />)}
          {[-160, 40, 240, 440, 640, 840, 1040].map((x) => <line key={x} x1={x} y1={-500} x2={x - 70} y2={1500} stroke="#2b3037" strokeWidth={12} />)}
          <line x1={-300} y1={430} x2={1300} y2={478} stroke="#3d434c" strokeWidth={26} />
          <text x={560} y={410} fill="#8e9199" fontSize={24} fontFamily={CJK}>滨江大道</text>
          <text x={120} y={660} fill="#7c8088" fontSize={20} fontFamily={CJK}>望江公园</text>
          {go > 0 && (
            <>
              <path d={ROUTE} fill="none" stroke="#0a3b75" strokeWidth={34} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - go} />
              <path d={ROUTE} fill="none" stroke="#0a84ff" strokeWidth={22} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - go} />
            </>
          )}
        </g>
        <g transform="translate(404 700)">
          <circle r={34} fill="rgba(10,132,255,.18)" />
          <circle r={24} fill="#fff" />
          <path d="M 0 -14 L 10 11 L 0 5 L -10 11 Z" fill="#0a84ff" />
        </g>
      </svg>
      {/* 出发前：回家的建议 */}
      {sugg > 0 && (
        <div style={{ position: 'absolute', left: 22, right: 22, bottom: 22, height: 104, borderRadius: 26, background: 'rgba(28,28,30,.94)', display: 'flex', alignItems: 'center', gap: 20, padding: '0 26px', fontFamily: CJK, opacity: sugg }}>
          <div style={{ width: 60, height: 60, borderRadius: 30, background: '#0a84ff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width={32} height={32} viewBox="0 0 24 24"><path d="M3 11 L12 4 L21 11 V20 H15 V14 H9 V20 H3 Z" fill="#fff" /></svg>
          </div>
          <div>
            <div style={{ fontSize: 30, fontWeight: 650 }}>回家</div>
            <div style={{ fontSize: 22, color: 'rgba(255,255,255,.62)', marginTop: 2 }}>8 分钟 · 4.6 公里</div>
          </div>
        </div>
      )}
      {/* 出发后：转弯卡片、到达时间 */}
      {card > 0 && (
        <>
          <div style={{ position: 'absolute', left: 22, top: 22, padding: '18px 30px 18px 20px', borderRadius: 26, background: 'rgba(28,28,30,.94)', display: 'flex', alignItems: 'center', gap: 18, boxShadow: '0 8px 24px rgba(0,0,0,.4)', opacity: clamp01(card * 1.3), transform: `translateY(${(1 - card) * -16}px)` }}>
            <svg width={56} height={56} viewBox="0 0 44 44"><path d="M 14 40 V 20 Q 14 12 22 12 H 32" fill="none" stroke="#fff" strokeWidth={6} strokeLinecap="round" /><path d="M 28 4 L 38 12 L 28 20 Z" fill="#fff" /></svg>
            <div style={{ fontFamily: CJK }}>
              <div style={{ fontFamily: SFD, fontSize: 42, fontWeight: 700, lineHeight: 1 }}>{meters} 米</div>
              <div style={{ fontSize: 24, color: 'rgba(255,255,255,.75)', marginTop: 6 }}>滨江大道</div>
            </div>
          </div>
          <div style={{ position: 'absolute', left: 22, right: 22, bottom: 22, height: 76, borderRadius: 24, background: 'rgba(28,28,30,.94)', display: 'flex', alignItems: 'center', padding: '0 28px', gap: 30, fontFamily: CJK, fontSize: 25, opacity: clamp01(card * 1.3), transform: `translateY(${(1 - card) * 16}px)` }}>
            <span style={{ fontFamily: SFD, fontWeight: 700, fontSize: 32, color: '#30d158' }}>21:50</span>
            <span style={{ color: 'rgba(255,255,255,.7)' }}>到达</span>
            <span style={{ fontFamily: SFD, fontWeight: 600 }}>8 分钟</span>
            <span style={{ fontFamily: SFD, color: 'rgba(255,255,255,.7)' }}>4.6 公里</span>
          </div>
        </>
      )}
    </div>
  );
}

const SONGS = [
  { title: '夜航', who: '城市夜行', art: { x: -80, y: -60 } },
  { title: '慢慢回家', who: '城市夜行', art: { x: -260, y: -200 } },
];

function NowPlaying({ f }: { f: number }) {
  const swap = smooth(seg(f, CP_NEXT + 2, CP_NEXT + 14));
  const s = SONGS[swap < 0.5 ? 0 : 1];
  const a = swap < 0.5 ? 1 - swap * 2 : swap * 2 - 1;
  const p = f < CP_NEXT ? 0.32 + (f - CP_IN) / 60 / 214 : (f - CP_NEXT) / 60 / 236;
  const press = Math.max(0, 1 - Math.abs(f - CP_NEXT) / 7);
  const ctl = { width: 64, height: 64, display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 32 };
  return (
    <div style={{ position: 'absolute', inset: 0, padding: 30, fontFamily: CJK }}>
      <div style={{ display: 'flex', gap: 24, alignItems: 'center' }}>
        <div style={{ width: 170, height: 170, borderRadius: 18, overflow: 'hidden', flex: 'none', boxShadow: '0 10px 26px rgba(0,0,0,.45)', opacity: a }}>
          <Img src={PLATE.wall} style={{ width: 520, height: 520, marginLeft: s.art.x, marginTop: s.art.y }} />
        </div>
        <div style={{ minWidth: 0, opacity: a }}>
          <div style={{ fontSize: 34, fontWeight: 650, whiteSpace: 'nowrap' }}>{s.title}</div>
          <div style={{ fontSize: 24, color: 'rgba(255,255,255,.6)', marginTop: 6, whiteSpace: 'nowrap' }}>{s.who}</div>
        </div>
      </div>
      <div style={{ position: 'absolute', left: 30, right: 30, bottom: 150, height: 8, borderRadius: 4, background: 'rgba(255,255,255,.18)' }}>
        <div style={{ width: `${Math.min(1, p) * 100}%`, height: '100%', borderRadius: 4, background: '#fff' }} />
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 54, display: 'flex', justifyContent: 'center', gap: 48 }}>
        <div style={ctl}><Skip back /></div>
        <div style={ctl}><svg width={34} height={38} viewBox="0 0 34 38"><rect x={3} y={2} width={10} height={34} rx={3} fill="#fff" /><rect x={21} y={2} width={10} height={34} rx={3} fill="#fff" /></svg></div>
        <div style={{ ...ctl, background: `rgba(255,255,255,${(press * 0.22).toFixed(3)})`, transform: `scale(${1 - press * 0.08})` }}><Skip /></div>
      </div>
    </div>
  );
}

const Skip = ({ back = false }: { back?: boolean }) => (
  <svg width={46} height={30} viewBox="0 0 46 30" style={{ transform: back ? 'scaleX(-1)' : undefined }}>
    <path d="M2 3 L21 15 L2 27 Z" fill="#fff" stroke="#fff" strokeWidth={3} strokeLinejoin="round" />
    <path d="M22 3 L41 15 L22 27 Z" fill="#fff" stroke="#fff" strokeWidth={3} strokeLinejoin="round" />
    <rect x={41} y={3} width={4} height={24} rx={1.5} fill="#fff" />
  </svg>
);

/** 指挥模式还在跑：车里也看得到 Claude 跑到哪了。 */
function Agent({ f }: { f: number }) {
  // 第 23 小节的强拍（2760）正好跑完。
  const PASS = 2760, per = (PASS - CP_IN - 40) / 26;
  const n = Math.min(42, Math.floor(16 + Math.max(0, f - CP_IN - 40) / per + 1e-6));
  const done = n >= 42;
  return (
    <div style={{ position: 'absolute', inset: 0, padding: 30, fontFamily: CJK }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
        <Img src={ICON.claude} style={{ width: 62, height: 62 }} />
        <div>
          <div style={{ fontSize: 28, fontWeight: 650 }}>Claude</div>
          <div style={{ fontSize: 21, color: 'rgba(255,255,255,.6)', marginTop: 2 }}>WindowShade · 指挥模式</div>
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 30, fontWeight: 600, marginTop: 70 }}>
        {done && <Check size={34} draw={seg(f, PASS, PASS + 14)} />}
        {done ? '测试全部通过' : '正在跑测试'}
      </div>
      <div style={{ height: 10, borderRadius: 5, background: 'rgba(255,255,255,.16)', marginTop: 20 }}>
        <div style={{ width: `${(n / 42) * 100}%`, height: '100%', borderRadius: 5, background: done ? '#30d158' : '#d97757' }} />
      </div>
      <div style={{ fontFamily: SFD, fontSize: 22, color: 'rgba(255,255,255,.6)', marginTop: 12 }}>{n} / 42</div>
    </div>
  );
}

/** 顶上落下来一条：要不要导航回家？点头。 */
function Ask({ f }: { f: number }) {
  const inn = spring(f, CP_ASK, 0.84, 0.42);
  const out = spring(f, CP_OK + 70, 1, 0.34);
  const y = mix(-140, 22, inn) + mix(0, -170, out);
  if (f < CP_ASK || f > CP_OK + 110) return null;
  const nod = Math.sin(clamp01((f - CP_NOD) / 26) * Math.PI) * 16;
  const done = seg(f, CP_OK, CP_OK + 10);
  const a = fade(f, CP_ASK + 4, CP_OK + 110, 10, 10);
  const row = (o: number, icon: ReactNode, title: string, sub: string) => (
    <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', gap: 20, padding: '0 30px', opacity: o }}>
      <div style={{ width: 56, display: 'flex', justifyContent: 'center' }}>{icon}</div>
      <div style={{ fontFamily: CJK, whiteSpace: 'nowrap' }}>
        <div style={{ fontSize: 28, fontWeight: 650 }}>{title}</div>
        <div style={{ fontSize: 21, color: 'rgba(235,235,245,.6)', marginTop: 3 }}>{sub}</div>
      </div>
    </div>
  );
  return (
    <div style={{ position: 'absolute', left: MAP.x + MAP.w / 2 - 250, top: y, width: 500, height: 112, borderRadius: 30, background: 'rgba(44,44,46,.97)', boxShadow: '0 16px 40px rgba(0,0,0,.5), inset 0 0 0 1px rgba(255,255,255,.08)', overflow: 'hidden' }}>
      {row(a * (1 - done), <AirPods size={52} tilt={nod} />, '导航回家？', '点头确认，摇头取消')}
      {row(a * done, <Check size={46} draw={seg(f, CP_OK + 2, CP_OK + 20)} />, '开始导航', '8 分钟到家')}
    </div>
  );
}
