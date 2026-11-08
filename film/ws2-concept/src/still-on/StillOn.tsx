import {AbsoluteFill, Sequence, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {HERE, HERE_LEN, TITLE, TITLE_LEN, WEEK, WEEK_LEN, FRAMES} from './beats';
import {World} from './World';

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const Caption = ({text, length}: {text: string; length: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const inn = Math.round(0.2 * fps);
  const out = Math.round(0.1 * fps);
  const opacity = interpolate(frame, [0, inn, Math.max(inn + 1, length - out), length], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 64}}>
      <div
        style={{
          color: '#E8EBF0',
          fontFamily: 'PingFang SC, Noto Sans SC, sans-serif',
          fontSize: 64,
          fontWeight: 600,
          opacity,
        }}
      >
        {text}
      </div>
    </AbsoluteFill>
  );
};

export const STILL_ON_FRAMES = FRAMES;

export const StillOn = () => (
  <AbsoluteFill style={{background: '#0D0F12'}}>
    <World />
    <Sequence name="還在原處" from={HERE} durationInFrames={HERE_LEN} premountFor={60}>
      <Caption text="還在原處" length={HERE_LEN} />
    </Sequence>
    <Sequence name="換成 ⌘" from={WEEK} durationInFrames={WEEK_LEN} premountFor={60}>
      <Caption text="Ctrl 換成 ⌘" length={WEEK_LEN} />
    </Sequence>
    <Sequence name="還開著" from={TITLE} durationInFrames={TITLE_LEN} premountFor={60}>
      <Caption text="還開著" length={TITLE_LEN} />
    </Sequence>
  </AbsoluteFill>
);
