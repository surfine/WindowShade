import { Composition } from 'remotion';
import { Film } from './Film';
import { Cover } from './Cover';
import { FPS } from './motion';
import { FILM_FRAMES } from './warp';

export const Root = () => (
  <>
    <Composition id="WS2Next" component={Film} durationInFrames={FILM_FRAMES} fps={FPS} width={1920} height={1080} defaultProps={{ audio: '' }} />
    <Composition id="Cover" component={Cover} durationInFrames={1} fps={FPS} width={1920} height={1080} defaultProps={{ t: 0.33, ax: 855, ay: 150, s: 2.2, text: '刘海能收窗口' }} />
  </>
);
