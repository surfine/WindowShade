import { Composition } from 'remotion';
import { FilmBlind, FilmLandscape } from './film/Film';
import { FPS, TOTAL } from './film/cues';
import { IslandQA, QA_FRAME_COUNT } from './film/IslandQA';
import { PhoneQA } from './film/PhoneQA';
import { PhoneDiag } from './film/PhoneDiag';
import { PLATE, PlateAir, PlateNeo } from './film/plates';
import { SymbolQA } from './film/SymbolQA';
import { SymbolOverlayQA, OVERLAY_SYMBOLS } from './film/SymbolOverlayQA';
import { SymbolCallsites } from './film/SymbolCallsites';
import { KEYS, NeoKeys } from './neo/Keys';

// 竖版还没按两台机器重新构图，Aaron 看过草稿再做；先只留横版、草稿、去字版。
export function FutureCompositions() {
  return (
    <>
      <Composition id="WS2Future" component={FilmLandscape} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
      {/* 草稿：1080p30 过门禁用；去字版：盲读用。 */}
      <Composition id="WS2FutureDraft" component={FilmLandscape} durationInFrames={TOTAL / 2} fps={FPS / 2} width={1920} height={1080} />
      <Composition id="WS2FutureBlind" component={FilmBlind} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
      {/* Neo 改版的关键帧样张，一帧一张。 */}
      <Composition id="WS2FutureKeys" component={NeoKeys} durationInFrames={KEYS.length} fps={FPS} width={1920} height={1080} />
      <Composition id="WS2FuturePlateNeo" component={PlateNeo} durationInFrames={TOTAL / 2} fps={FPS / 2} width={PLATE.neo.w} height={PLATE.neo.h} />
      <Composition id="WS2FuturePlateAir" component={PlateAir} durationInFrames={TOTAL / 2} fps={FPS / 2} width={PLATE.air.w} height={PLATE.air.h} />
      {/* 島排版驗收台：一張靜幀，每個島狀態一列，用來量島內留白對不對稱。 */}
      <Composition id="WS2FutureIslandQA" component={IslandQA} durationInFrames={QA_FRAME_COUNT} fps={1} width={1920} height={15 * 306} />
      {/* 手機螢幕驗收台：四個角度各一格，逐角看貼圖與邊框。 */}
      <Composition id="WS2FuturePhoneQA" component={PhoneQA} durationInFrames={1} fps={1} width={2 * 1150} height={2 * 1150} />
      {/* 手機穿幫診斷：機身／貼圖分開渲，外加俯視配置。 */}
      <Composition id="WS2FuturePhoneDiag" component={PhoneDiag} durationInFrames={1} fps={1} width={3 * 960} height={2 * 960} />
      {/* 符號驗收台：現況（手畫）vs 新版（真 SF Symbols），外加真符號單獨放大。 */}
      <Composition id="WS2FutureSymbolQA" component={SymbolQA} durationInFrames={1} fps={1} width={780} height={56 + 8 * 240 + 300} />
      {/* 符號疊圖：每一幀一顆，上＝AppKit 官方、下＝本專案的真符號向量（512×512 各一格）。 */}
      <Composition id="WS2FutureSymbolOverlay" component={SymbolOverlayQA} durationInFrames={OVERLAY_SYMBOLS.length} fps={1} width={512} height={1024} />
      {/* 三個呼叫點各一幀，都用真元件、1:1，不會糊；再由 tools/crop-callsites.py NEAREST 放大裁切。 */}
      <Composition id="WS2FutureSymbolCallsites" component={SymbolCallsites} durationInFrames={3} fps={1} width={1920} height={1080} />
    </>
  );
}
