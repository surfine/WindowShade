import { Composition } from 'remotion';
import { Film } from './Film';
import { FPS, TOTAL } from './motion';

export const Root = () => (
  <>
    <Composition id="WS2Next" component={Film} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} defaultProps={{ audio: '' }} />
  </>
);
