// 呼叫點 1:1 樣張：把片子真的會用到的那三個島，各自照原尺寸畫一遍。
//
// 為什麼要另開一張：片子裡鏡頭常退得很遠，島只有幾十像素，勾是正是反肉眼分不出來；
// 之前那張 `callsites-sheet.png` 又是「整格畫面縮小」，等於把證據抽掉。
// 這一張照原點度畫（1:1，不放大、不縮），所以它跟片子是同一條渲染路，
// 再由 `tools/crop-callsites.py` 用 NEAREST 放大裁切，筆畫看得出來。
//
// index = 0 → `src/future/Island.tsx`（Future.tsx 用；這一格是「欢迎回来」的綠圓勾）
// index = 1 → `src/future/film/Screen.tsx` 的 `IslandLayers`（Concept 片的 Unlock；刷臉認出來）
// index = 2 → `src/future/neo/NeoScreen.tsx`（Neo 的島；已確認）
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { Island } from '../Island';
import { PT } from '../shape';
import { MACHINES } from './machines';
import { IslandLayers } from './Screen';
import { NPT } from '../neo/geom';
import { NeoScreen } from '../neo/NeoScreen';

export function SymbolCallsites() {
  const index = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: '#000' }}>
      {index === 0 && (
        // Island.tsx 自己靠 PT.w 置中，所以給它一個 PT.w 寬的定位容器（跟片子同一套點座標）。
        <div style={{ position: 'absolute', left: (1920 - PT.w) / 2, top: 0, width: PT.w, height: PT.h }}>
          <Island f={320} />
        </div>
      )}
      {index === 1 && (
        <div style={{ position: 'absolute', left: (1920 - MACHINES.neo.pt.w) / 2, top: 0, width: MACHINES.neo.pt.w, height: MACHINES.neo.pt.h }}>
          <IslandLayers m="neo" f={460} />
        </div>
      )}
      {index === 2 && (
        <div style={{ position: 'absolute', left: (1920 - NPT.w) / 2, top: 0, width: NPT.w, height: NPT.h }}>
          <NeoScreen s={{ lock: 1, island: { kind: 'face', scan: 1, ok: 1, sweep: 1 } }} />
        </div>
      )}
    </AbsoluteFill>
  );
}
