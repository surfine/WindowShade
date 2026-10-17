// 一镜到底：three.js 画机身，整块屏幕是一层网页，按同一个相机投影贴在显示面上。
// 字幕在画面下方（D5：全片 4 句 + 片尾字标，60 px，没有标题带）。
import type React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { FPS, approach, seg } from './motion';
import { CAPTIONS, WORDMARK, camAt, pullQ } from './plan';
import { H, W, camera, pose, screenTransform } from './rig';
import { Screen } from './Screen';
import { Stage } from './Stage';
import { storyOf } from './warp';

const K = 2; // 网页按 2× 排，贴图时再缩

function Caption({ t }: { t: number }) {
  const c = CAPTIONS.find((x) => t >= x.from - 0.01 && t < x.to);
  if (!c) return null;
  const inP = approach(t - c.from, 0.5, 0.86);
  const out = seg(t, c.to - 0.25, c.to);
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: 958, textAlign: 'center', opacity: Math.min(1, inP) * (1 - out),
      transform: `translateY(${((1 - inP) * 14).toFixed(2)}px)`, fontFamily: '"PingFang SC",-apple-system,sans-serif', fontSize: 60, fontWeight: 600,
      color: '#fff', letterSpacing: 1, textShadow: '0 2px 18px rgba(0,0,0,.55)' }}>{c.text}</div>
  );
}

function Wordmark({ t }: { t: number }) {
  const p = approach(t - WORDMARK.at, 0.7, 0.9);
  if (p <= 0) return null;
  return (
    <div style={{ position: 'absolute', left: 0, right: 0, top: 118, textAlign: 'center', opacity: Math.min(1, p), transform: `translateY(${((1 - p) * -10).toFixed(2)}px)` }}>
      <div style={{ fontFamily: '"SF Pro Display",-apple-system,sans-serif', fontSize: 76, fontWeight: 650, color: '#fff', letterSpacing: -0.5 }}>{WORDMARK.text}</div>
    </div>
  );
}

export function Film({ audio }: { audio?: string }) {
  const f = useCurrentFrame();
  const t = storyOf(f / FPS); // 片子帧 → 故事时间（warp.ts）
  const p = pose(camAt(t), pullQ(t));
  const cam = camera(p);
  const m = screenTransform(cam, 1710 * K, 1107 * K);
  return (
    <AbsoluteFill style={{ background: '#12141a' }}>
      <Stage p={p} neo W={W} H={H} />
      <div style={{ position: 'absolute', left: 0, top: 0, width: 1710 * K, height: 1107 * K, transformOrigin: '0 0', transform: m }}>
        <div style={{ position: 'absolute', left: 0, top: 0, width: 1710, height: 1107, zoom: K } as React.CSSProperties}>
          <Screen t={t} />
        </div>
      </div>
      <Caption t={t} />
      <Wordmark t={t} />
      {audio ? <Audio src={staticFile(audio)} /> : null}
    </AbsoluteFill>
  );
}
