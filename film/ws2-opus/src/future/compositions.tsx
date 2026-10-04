import { Composition } from 'remotion';
import { FilmBlind, FilmLandscape } from './film/Film';
import { FPS, TOTAL } from './film/cues';
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
    </>
  );
}
