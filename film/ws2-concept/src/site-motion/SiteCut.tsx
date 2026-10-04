import {AbsoluteFill, useCurrentFrame, useVideoConfig} from 'remotion';
import {
  captionAt,
  foldAmount,
  islandAt,
  shadeMatrix,
  slideProgress,
  SLIDE_START,
} from './motion';

function matrixCss(amount: number, width: number, height: number) {
  const m = shadeMatrix(amount);
  const n = (x: number) => +x.toFixed(5);
  return `matrix3d(${n(m[0])},${n(m[1] * height / width)},0,${n(m[3] / width)},${n(m[4] * width / height)},${n(m[5])},0,${n(m[7] / height)},0,0,1,0,${n(m[12] * width)},${n(m[13] * height)},0,${n(m[15])})`;
}

export const SiteCut = () => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const portrait = height > width;
  const screenW = portrait ? 860 : 1280;
  const screenH = Math.round(screenW * 10 / 16);
  const island = islandAt(frame);
  const notchW = (screenW * island.w) / 100;
  const notchH = (screenW * island.h) / 100;
  const notchR = (screenW * island.r) / 100;
  const fold = frame < 260 ? foldAmount(frame) : 0;
  const pageW = screenW - 80;
  const pageH = screenH - 120;
  const fly = island.fly;
  const winW = 420 * (portrait ? 0.72 : 1);
  const winH = 280 * (portrait ? 0.72 : 1);
  const homeX = (screenW - winW) / 2;
  const homeY = screenH * 0.38;
  const intoX = (screenW - winW * 0.12) / 2;
  const intoY = 8;
  const winX = homeX + (intoX - homeX) * fly;
  const winY = homeY + (intoY - homeY) * fly;
  const winScale = 1 + (0.12 - 1) * fly;
  const slide = frame >= SLIDE_START ? slideProgress(frame, SLIDE_START) : 0;
  const slideX = slide * -(screenW * 0.42);
  const showWindow = frame >= 280 && frame < 1400 && fly < 1;
  const showSlide = frame >= SLIDE_START && frame < 1960;
  const caption = captionAt(frame);
  const placeholder =
    frame < 240
      ? '真机画面：合上盖子。要录桌面还在。'
      : frame < 620
        ? '真机画面：收进刘海。要录窗口飞进去。'
        : frame >= SLIDE_START && frame < 1960
          ? '真机画面：侧拉。要录窗口靠到屏幕边。'
          : null;

  return (
    <AbsoluteFill style={{background: '#0B0D12', color: '#F4F1EA', fontFamily: 'PingFang SC, sans-serif'}}>
      <div
        style={{
          position: 'absolute',
          left: (width - screenW) / 2,
          top: portrait ? 180 : (height - screenH) / 2 - 40,
          width: screenW,
          height: screenH,
          borderRadius: portrait ? 28 : 18,
          background: '#16181D',
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            position: 'absolute',
            left: 40,
            top: 72,
            width: pageW,
            height: pageH,
            borderRadius: 12,
            background: '#E7E1D6',
            transform: frame < 260 ? matrixCss(fold, pageW, pageH) : undefined,
            transformOrigin: '50% 100%',
          }}
        />
        {showWindow ? (
          <div
            style={{
              position: 'absolute',
              left: winX,
              top: winY,
              width: winW,
              height: winH,
              borderRadius: 16 + fly * 20,
              background: '#F7F4EE',
              transform: `scale(${winScale})`,
              transformOrigin: '50% 50%',
            }}
          />
        ) : null}
        {showSlide ? (
          <div
            style={{
              position: 'absolute',
              left: screenW * 0.28,
              top: screenH * 0.22,
              width: portrait ? 280 : 460,
              height: portrait ? 360 : 520,
              borderRadius: 16,
              background: '#F7F4EE',
              transform: `translateX(${slideX}px)`,
            }}
          />
        ) : null}
        <div
          style={{
            position: 'absolute',
            left: (screenW - notchW) / 2,
            top: 0,
            width: notchW,
            height: notchH,
            borderBottomLeftRadius: notchR,
            borderBottomRightRadius: notchR,
            background: '#0A0A0A',
            overflow: 'hidden',
            color: '#fff',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: portrait ? 22 : 28,
            fontWeight: 600,
          }}
        >
          {island.mode === 'alert' ? '编译完成' : island.mode === 'shelf' ? '1' : island.tucked ? '1' : ''}
        </div>
      </div>
      {placeholder ? (
        <div
          style={{
            position: 'absolute',
            left: portrait ? 48 : 80,
            right: portrait ? 48 : 80,
            bottom: portrait ? 280 : 148,
            fontSize: portrait ? 28 : 32,
            lineHeight: 1.35,
            color: 'rgba(244,241,234,0.72)',
          }}
        >
          {placeholder}
        </div>
      ) : null}
      {caption ? (
        <div
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: portrait ? 120 : 64,
            textAlign: 'center',
            fontSize: portrait ? 64 : 72,
            fontWeight: 600,
            letterSpacing: 0,
          }}
        >
          {caption}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};
