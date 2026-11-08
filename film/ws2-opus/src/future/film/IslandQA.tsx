// 島內排版的驗收台：把每一個島狀態攤在同一張圖上量。
// 背景刻意用中灰（不是桌布）：黑島的邊界與島內留白才量得準，也不會被桌布的亮暗帶跑。
// 這裡用的就是本片那一疊圖層（`IslandLayers`），所以量到的就是片子裡畫的。
import { AbsoluteFill } from 'remotion';
import { MACHINES, type MachineId } from './machines';
import { IslandLayers } from './Screen';

const ROW_H = 306;

type Row = { m: MachineId; f: number; label: string };

/** 每一個「島長什麼樣」的狀態各一列。幀號是 60 fps 的片子幀。 */
const ROWS: Row[] = [
  { m: 'neo', f: 440, label: 'Neo 認人（解鎖）' },
  { m: 'neo', f: 660, label: 'Neo 已收進劉海' },
  { m: 'neo', f: 1200, label: 'Neo 等你確認' },
  { m: 'neo', f: 1500, label: 'Neo 已確認' },
  { m: 'neo', f: 2320, label: 'Neo 番茄鐘（待按）' },
  { m: 'neo', f: 2400, label: 'Neo 番茄鐘（倒數）' },
  { m: 'neo', f: 2600, label: 'Neo 休息提醒' },
  { m: 'neo', f: 2700, label: 'Neo 走開（大環）' },
  { m: 'neo', f: 2800, label: 'Neo 休息中的窄藥丸' },
  { m: 'air', f: 1060, label: 'Air 看口型' },
  { m: 'air', f: 1820, label: 'Air 緊湊（左右耳）' },
  { m: 'air', f: 1900, label: 'Air 半島（車）' },
  { m: 'air', f: 2100, label: 'Air 半島（外送）' },
  { m: 'air', f: 3060, label: 'Air 走開倒數' },
  { m: 'air', f: 3400, label: 'Air 片尾（半島）' },
];

export const QA_FRAME_COUNT = 1;

export function IslandQA() {
  const W = 1920;
  return (
    <AbsoluteFill style={{ background: '#3f434b', fontFamily: 'ui-sans-serif, system-ui', flexDirection: 'column' }}>
      {ROWS.map((r, i) => {
        const P = MACHINES[r.m].pt;
        const left = (W - P.w) / 2;
        return (
          <div key={i} style={{ position: 'relative', height: ROW_H, flex: 'none', borderBottom: '1px dashed rgba(255,255,255,.18)' }}>
            {/* 螢幕寬的那一塊：島是相對它定位的 */}
            <div style={{ position: 'absolute', left, top: 0, width: P.w, height: ROW_H, overflow: 'hidden', background: '#4a4e57' }}>
              <IslandLayers m={r.m} f={r.f} />
              {/* 中線：內容該對稱於這一條 */}
              <div style={{ position: 'absolute', left: P.w / 2 - 0.5, top: 0, width: 1, height: ROW_H, background: 'rgba(255,60,60,.85)' }} />
            </div>
            <div style={{ position: 'absolute', left: 8, top: 6, color: '#fff', fontSize: 15, background: 'rgba(0,0,0,.55)', padding: '2px 8px', borderRadius: 4 }}>
              {r.label} · {r.m} · f{r.f} · 屏寬 {P.w}
            </div>
          </div>
        );
      })}
    </AbsoluteFill>
  );
}
