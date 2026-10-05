// 「它没有 Face ID」：一镜到底。Neo 和午夜色 15 英寸 Air 摆在同一个场景里，镜头从一台走到另一台。
import { AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { MUSIC_SRC } from '../beats';
import { CJK, SFD } from '../glyphs';
import { seg, smooth } from '../time';
import { FPS, LINES, T } from './cues';
import { motion } from './springs';
import { Stage } from './stage';

export function Film({ blind = false }: { blind?: boolean }) {
  const { width: W, height: H, fps } = useVideoConfig();
  const f = useCurrentFrame() * (FPS / fps);
  return (
    <AbsoluteFill style={{ background: '#12141a', overflow: 'hidden' }}>
      {blind && <style>{'*{color:transparent!important;-webkit-text-fill-color:transparent!important;text-shadow:none!important}'}</style>}
      <Stage f={f} W={W} H={H} />
      <Caption f={f} W={W} H={H} />
      <EndMark f={f} W={W} H={H} />
      <Audio src={staticFile(MUSIC_SRC)} />
    </AbsoluteFill>
  );
}

/** 屏外字幕只淡入淡出，不打字、不上浮。一次一句中文。 */
function Caption({ f, W, H }: { f: number; W: number; H: number }) {
  const line = LINES.find((l) => f >= l.from && f < l.to);
  if (!line) return null;
  const a = smooth(seg(f, line.from, line.from + 12)) * (1 - smooth(seg(f, line.to - 6, line.to)));
  // 字幕带贴画面上缘；机身由 shot.ts 拉远俯视，银边全程低于这一行（审片 C10-02）。
  const size = Math.round(H * 0.042);
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: H * 0.038, textAlign: 'center', width: W, opacity: a }}>
      <div style={{ fontFamily: CJK, fontWeight: 600, fontSize: size, color: '#fff', letterSpacing: 1, lineHeight: 1.25, textShadow: '0 1px 12px rgba(0,0,0,.55)' }}>{line.text}</div>
    </div>
  );
}

function EndMark({ f, H }: { f: number; W: number; H: number }) {
  const p = motion(f, T.mark, 'settle');
  if (p <= 0) return null;
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: H * 0.128, display: 'flex', justifyContent: 'center', opacity: Math.min(1, p * 1.2), transform: `translateY(${(1 - p) * 10}px)` }}>
      <div style={{ fontFamily: SFD, fontSize: Math.round(H * 0.05), fontWeight: 600, color: '#fff', letterSpacing: -0.2 }}>WindowShade 2</div>
    </div>
  );
}

export const FilmLandscape = () => <Film />;
export const FilmBlind = () => <Film blind />;
