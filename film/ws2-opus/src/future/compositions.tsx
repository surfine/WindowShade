import { Composition } from 'remotion';
import { PHONE } from '../layout';
import { FutureLandscape, FuturePortrait } from './Future';
import { FPS, TOTAL } from './time';

export function FutureCompositions() {
  return (
    <>
      <Composition id="WS2Future" component={FutureLandscape} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
      <Composition id="WS2FuturePortrait" component={FuturePortrait} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} />
      {/* iPhone 18 Pro Max 原生竖屏 1320 × 2868（同 layout.ts 的 PHONE）。 */}
      <Composition id="WS2FuturePhone" component={FuturePortrait} durationInFrames={TOTAL} fps={FPS} width={PHONE.width} height={PHONE.height} />
    </>
  );
}
