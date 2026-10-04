import { Composition } from 'remotion';
import { PHONE } from '../layout';
import { FutureBlind, FutureLandscape, FuturePortrait } from './Future';
import { KEYS, NeoKeys } from './neo/Keys';
import { FPS, TOTAL } from './time';

export function FutureCompositions() {
  return (
    <>
      <Composition id="WS2Future" component={FutureLandscape} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
      <Composition id="WS2FuturePortrait" component={FuturePortrait} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} />
      {/* iPhone 18 Pro Max 原生竖屏 1320 × 2868（同 layout.ts 的 PHONE）。 */}
      <Composition id="WS2FuturePhone" component={FuturePortrait} durationInFrames={TOTAL} fps={FPS} width={PHONE.width} height={PHONE.height} />
      {/* 草稿：1080p30 过门禁用；去字版：盲读用。 */}
      <Composition id="WS2FutureDraft" component={FutureLandscape} durationInFrames={TOTAL / 2} fps={FPS / 2} width={1920} height={1080} />
      <Composition id="WS2FutureBlind" component={FutureBlind} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
      {/* Neo 改版的关键帧样张，一帧一张。 */}
      <Composition id="WS2FutureKeys" component={NeoKeys} durationInFrames={KEYS.length} fps={FPS} width={1920} height={1080} />
    </>
  );
}
