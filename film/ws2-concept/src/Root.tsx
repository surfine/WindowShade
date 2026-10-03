import { Composition } from 'remotion';
import { Film, FILM_FRAMES } from './Film';

export const Root = () => (
  <Composition id="WS2Concept" component={Film} durationInFrames={FILM_FRAMES} fps={60} width={1920} height={1080} />
);
