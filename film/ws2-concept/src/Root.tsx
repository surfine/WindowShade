import {Composition} from 'remotion';
import {Film, FILM_FRAMES} from './Film';
import {SiteCut} from './site-motion/SiteCut';
import {SITE_FRAMES} from './site-motion/motion';

export const Root = () => (
  <>
    <Composition id="WS2Concept" component={Film} durationInFrames={FILM_FRAMES} fps={60} width={1920} height={1080} />
    <Composition id="WS2ConceptPortrait" component={Film} durationInFrames={FILM_FRAMES} fps={60} width={1080} height={1920} />
    <Composition id="WS2SiteCut" component={SiteCut} durationInFrames={SITE_FRAMES} fps={60} width={1920} height={1080} />
    <Composition id="WS2SiteCutPortrait" component={SiteCut} durationInFrames={SITE_FRAMES} fps={60} width={1080} height={1920} />
  </>
);
