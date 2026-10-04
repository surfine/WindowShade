import { Composition } from 'remotion';
import { Film } from './Film';
import { LANDSCAPE, PORTRAIT } from './layout';
import { FPS } from './motion/site';
import { TOTAL } from './timeline';

const Landscape = () => <Film L={LANDSCAPE} />;
const Portrait = () => <Film L={PORTRAIT} />;

export function Root() {
  return (
    <>
      <Composition id="WS2Opus" component={Landscape} durationInFrames={TOTAL} fps={FPS} width={LANDSCAPE.width} height={LANDSCAPE.height} />
      <Composition id="WS2OpusPortrait" component={Portrait} durationInFrames={TOTAL} fps={FPS} width={PORTRAIT.width} height={PORTRAIT.height} />
    </>
  );
}
