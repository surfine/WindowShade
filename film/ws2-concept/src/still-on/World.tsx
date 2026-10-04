import {useCurrentFrame, useVideoConfig} from 'remotion';
import {
  BULGE,
  BLOOM,
  D0,
  D1,
  D2,
  DIGIT,
  DOLLY_IN,
  DOLLY_OUT,
  EXIT,
  EXIT_SHAPE,
  GLIDE,
  LAND,
  LID,
  MATCH,
  NOD,
  PASS,
  RESTORE,
  TUCK,
  UNVEIL,
  VEIL,
  WORDS_OUT,
} from './beats';
import {impulse, play, ramp, SPRING} from './tokens';

const SW = 980;
const SH = Math.round((SW * 1864) / 2880);
const NW = (SW * 312) / 2880;
const NH = (SW * 56) / 2880;

const Digit = ({n, opacity, y}: {n: string; opacity: number; y: number}) => (
  <div
    style={{
      position: 'absolute',
      left: (SW - 24) / 2 - 8,
      top: 0,
      color: '#fff',
      fontFamily: 'PingFang SC, Noto Sans SC, sans-serif',
      fontWeight: 600,
      fontSize: 22,
      opacity,
      translate: `0px ${y}px`,
    }}
  >
    {n}
  </div>
);

const Paper = ({
  homeX,
  homeY,
  w,
  h,
  dx,
  dy,
  s,
}: {
  homeX: number;
  homeY: number;
  w: number;
  h: number;
  dx: number;
  dy: number;
  s: number;
}) => (
  <div
    style={{
      position: 'absolute',
      left: homeX,
      top: homeY,
      width: w,
      height: h,
      borderRadius: 16,
      background: '#F5F6F8',
      translate: `${dx}px ${dy}px`,
      scale: s,
      transformOrigin: 'center center',
    }}
  >
    <div style={{position: 'absolute', left: 22, top: 28, width: '46%', height: 8, borderRadius: 8, background: '#E4E7EC'}} />
    <div style={{position: 'absolute', left: 22, top: 48, width: '72%', height: 8, borderRadius: 8, background: '#EEF0F3'}} />
  </div>
);

export const World = () => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const lid = play(frame, fps, LID, SPRING.settle);
  const dollyIn = play(frame, fps, DOLLY_IN, SPRING.dolly);
  const dollyOut = play(frame, fps, DOLLY_OUT, SPRING.dolly);
  const zoom = 1 + dollyIn * 0.38 * (1 - dollyOut);
  const bloom = play(frame, fps, BLOOM, SPRING.bloom);
  const close = play(frame, fps, EXIT_SHAPE, SPRING.calm);
  const spoken = Math.max(0, bloom * (1 - close));
  const nod = play(frame, fps, NOD, SPRING.pop);
  const glide = play(frame, fps, GLIDE, SPRING.glide);
  const pass = play(frame, fps, PASS, SPRING.glide);
  const land = play(frame, fps, LAND, SPRING.catch);
  const tuck = play(frame, fps, TUCK, SPRING.settle);
  const restore = play(frame, fps, RESTORE, SPRING.flyOut);
  const bulge = impulse(frame, fps, BULGE);
  const veilIn = play(frame, fps, VEIL, SPRING.calm);
  const veilOut = play(frame, fps, UNVEIL, SPRING.calm);
  const veil = Math.max(0, veilIn * (1 - veilOut));
  const digitIn = play(frame, fps, DIGIT, SPRING.expand);
  const digitOut = play(frame, fps, D0 + 2, SPRING.calm);
  const digitOpen = Math.max(0, digitIn * (1 - digitOut));
  const away = tuck * (1 - restore);

  const screenLeft = (width - SW) / 2;
  const screenTop = height * 0.2;
  const extraW = spoken * 168 + digitOpen * 52 + bulge * 14;
  const extraH = spoken * 40 + digitOpen * 24 + bulge * 6;
  const sx = (NW + extraW) / NW;
  const sy = (NH + extraH) / NH;
  const say = ramp(frame, BLOOM + 5, 0.18, fps) * (1 - ramp(frame, EXIT, 0.1, fps));
  const digit3 = ramp(frame, DIGIT + 5, 0.18, fps) * (1 - ramp(frame, D2, 0.1, fps));
  const digit2 = ramp(frame, D2, 0.18, fps) * (1 - ramp(frame, D1, 0.1, fps));
  const digit1 = ramp(frame, D1, 0.18, fps) * (1 - ramp(frame, D0, 0.1, fps));
  const person = ramp(frame, NOD - 18, 0.18, fps) * (1 - ramp(frame, NOD + 28, 0.1, fps));
  const wordOpacity = ramp(frame, LAND, 0.18, fps) * (1 - ramp(frame, WORDS_OUT, 0.1, fps));
  const remnant = land * 0.45 * (1 - ramp(frame, WORDS_OUT, 0.1, fps));
  const phoneDim = 1 - pass * 0.55;
  const match = ramp(frame, MATCH, 0.18, fps) * (1 - ramp(frame, UNVEIL + 20, 0.1, fps));

  const innerW = SW - 24;
  const notchCX = innerW / 2;
  const notchCY = NH / 2;
  const leftX = 36;
  const homeX = 250;
  const homeY = 150;
  const w1 = 420;
  const h1 = 270;
  const glideDx = (leftX - homeX) * glide;
  const dx = glideDx + (notchCX - (homeX + glideDx + w1 / 2)) * away;
  const dy = (notchCY - (homeY + h1 / 2)) * away;
  const home2X = 560;
  const home2Y = 118;
  const w2 = 300;
  const h2 = 210;
  const dx2 = (notchCX - (home2X + w2 / 2)) * away;
  const dy2 = (notchCY - (home2Y + h2 / 2)) * away;

  const notchLeft = screenLeft + 12 + (SW - 24 - NW * sx) / 2;
  const phoneX = screenLeft - 210;

  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        scale: zoom,
        transformOrigin: `${screenLeft + SW / 2}px ${screenTop + 36}px`,
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: phoneX,
          top: screenTop + 80,
          width: 168,
          height: 320,
          borderRadius: 28,
          background: '#15181D',
          border: '1px solid #252A32',
        }}
      >
        <div
          style={{
            position: 'absolute',
            left: 28,
            top: 148,
            width: 96,
            height: 8,
            borderRadius: 8,
            background: '#E8EBF0',
            opacity: phoneDim,
          }}
        />
        <div
          style={{
            position: 'absolute',
            inset: 10,
            borderRadius: 20,
            border: '1px solid #90A2FF',
            opacity: match,
          }}
        />
      </div>
      <div
        style={{
          position: 'absolute',
          left: phoneX + 48,
          top: screenTop + 228,
          width: 72,
          height: 8,
          borderRadius: 8,
          background: '#E8EBF0',
          opacity: pass * (1 - land),
          translate: `${(notchLeft - (phoneX + 48)) * pass}px ${(screenTop + 22 - (screenTop + 228)) * pass}px`,
        }}
      />
      <div style={{position: 'absolute', left: screenLeft, top: screenTop, perspective: 1200}}>
        <div
          style={{
            width: SW,
            height: SH,
            borderRadius: '28px 28px 8px 8px',
            background: '#15181D',
            padding: 12,
          }}
        >
          <div
            style={{
              position: 'relative',
              width: '100%',
              height: '100%',
              overflow: 'hidden',
              borderRadius: '20px 20px 3px 3px',
              background: '#191D23',
            }}
          >
            <Paper homeX={homeX} homeY={homeY} w={w1} h={h1} dx={dx} dy={dy} s={1 - away * 0.92} />
            <Paper homeX={home2X} homeY={home2Y} w={w2} h={h2} dx={dx2} dy={dy2} s={1 - away * 0.92} />
            <div
              style={{
                position: 'absolute',
                right: SW / 2 + (NW * sx) / 2 + 8,
                top: 18,
                width: 28,
                height: 8,
                borderRadius: 8,
                background: '#E8EBF0',
                opacity: remnant,
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: SW / 2 + (NW * sx) / 2 + 16,
                top: 8,
                color: '#E8EBF0',
                fontFamily: 'PingFang SC, Noto Sans SC, sans-serif',
                fontWeight: 600,
                fontSize: 22,
                opacity: wordOpacity,
                translate: `${(1 - land) * -28}px 0px`,
              }}
            >
              寫好了
            </div>
            <div
              style={{
                position: 'absolute',
                inset: 0,
                background: '#080A0E',
                opacity: veil,
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: (innerW - NW) / 2,
                top: 0,
                width: NW,
                height: NH,
                borderBottomLeftRadius: 16,
                borderBottomRightRadius: 16,
                background: '#000',
                transformOrigin: 'top center',
                scale: `${sx} ${sy}`,
              }}
            />
            <div
              style={{
                position: 'absolute',
                left: innerW / 2 - 70,
                top: 0,
                width: 140,
                textAlign: 'center',
                color: '#fff',
                fontFamily: 'PingFang SC, Noto Sans SC, sans-serif',
                fontWeight: 600,
                fontSize: 18,
                opacity: say,
                translate: `0px ${(NH * sy) / 2 - 12}px`,
              }}
            >
              左半屏
            </div>
            <div
              style={{
                position: 'absolute',
                left: innerW / 2 - 11,
                top: 0,
                width: 22,
                height: 16,
                borderRadius: 4,
                background: '#3A3E46',
                translate: `0px ${NH * sy - 6 + nod * 1.5}px`,
                opacity: say,
              }}
            />
            <Digit n="3" opacity={digit3} y={(NH * sy) / 2 - 14} />
            <Digit n="2" opacity={digit2} y={(NH * sy) / 2 - 14} />
            <Digit n="1" opacity={digit1} y={(NH * sy) / 2 - 14} />
          </div>
        </div>
        <div
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            width: SW,
            height: SH,
            borderRadius: '28px 28px 8px 8px',
            background: '#1A1C20',
            transformOrigin: 'center top',
            rotate: `x ${lid * -105}deg`,
          }}
        />
      </div>
      <div
        style={{
          position: 'absolute',
          left: screenLeft + SW / 2 - 16,
          top: screenTop - 78,
          width: 32,
          height: 32,
          borderRadius: 16,
          background: '#E8EBF0',
          opacity: person,
          translate: `0px ${nod * 10}px`,
        }}
      />
    </div>
  );
};
