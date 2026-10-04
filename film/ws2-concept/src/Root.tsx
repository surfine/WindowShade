import {Composition, Folder} from 'remotion';
import {Film, FILM_FRAMES} from './Film';
import {STILL_ON_FRAMES, StillOn} from './still-on/StillOn';

export const Root = () => (
  <>
    <Folder name="概念">
      <Composition id="WS2Concept" component={Film} durationInFrames={FILM_FRAMES} fps={60} width={1920} height={1080} />
      <Composition id="WS2ConceptPortrait" component={Film} durationInFrames={FILM_FRAMES} fps={60} width={1080} height={1920} />
    </Folder>
    <Folder name="還開著">
      <Composition id="StillOn" component={StillOn} durationInFrames={STILL_ON_FRAMES} fps={60} width={1920} height={1080} />
    </Folder>
  </>
);
