import { Composition } from 'remotion';
import { Film } from './Film';
import { LANDSCAPE, PHONE, PORTRAIT } from './layout';
import { FPS } from './motion/site';
import { OUT_TOTAL } from './cut';

// 画出来的界面（B 版）是主版；占位版写着每块要录什么，录真机时对着它拍。
const Landscape = () => <Film L={LANDSCAPE} drawn />;
const Portrait = () => <Film L={PORTRAIT} drawn />;
const LandscapeSlots = () => <Film L={LANDSCAPE} drawn={false} />;
const PortraitSlots = () => <Film L={PORTRAIT} drawn={false} />;
/** iPhone 18 Pro Max 原生竖屏 1320 × 2868。 */
const Phone = () => <Film L={PHONE} drawn />;

export function Root() {
  const common = { durationInFrames: OUT_TOTAL, fps: FPS } as const;
  return (
    <>
      <Composition id="WS2Opus" component={Landscape} {...common} width={LANDSCAPE.width} height={LANDSCAPE.height} />
      <Composition id="WS2OpusPortrait" component={Portrait} {...common} width={PORTRAIT.width} height={PORTRAIT.height} />
      <Composition id="WS2OpusSlots" component={LandscapeSlots} {...common} width={LANDSCAPE.width} height={LANDSCAPE.height} />
      <Composition id="WS2OpusSlotsPortrait" component={PortraitSlots} {...common} width={PORTRAIT.width} height={PORTRAIT.height} />
      <Composition id="WS2OpusPhone" component={Phone} {...common} width={PHONE.width} height={PHONE.height} />
    </>
  );
}
