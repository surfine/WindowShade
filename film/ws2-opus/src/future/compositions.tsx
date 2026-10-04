import { Composition } from 'remotion';
import { FutureLandscape, FuturePortrait } from './Future';
import { FPS, TOTAL } from './time';

export function FutureCompositions() {
  return (
    <>
      <Composition id="WS2Future" component={FutureLandscape} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
      <Composition id="WS2FuturePortrait" component={FuturePortrait} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} />
      {/* iPhone 全面屏 9:19.5；正式输出时按机型像素放大。 */}
      <Composition id="WS2FuturePhone" component={FuturePortrait} durationInFrames={TOTAL} fps={FPS} width={1080} height={2340} />
    </>
  );
}
