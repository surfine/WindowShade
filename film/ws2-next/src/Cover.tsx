// 封面：片中同一时刻、同一套机身与屏幕，只换一个更近的镜头和一行大字（≤ 8 个字）。
import type React from 'react';
import { AbsoluteFill } from 'remotion';
import { pose, camera, screenTransform, W, H } from './rig';
import { Screen } from './Screen';
import { Stage } from './Stage';

const K = 2;
export type CoverProps = { t: number; ax: number; ay: number; s: number; text: string };

export function Cover({ t, ax, ay, s, text }: CoverProps) {
  const p = pose({ ax, ay, s }, 0);
  const m = screenTransform(camera(p), 1710 * K, 1107 * K);
  return (
    <AbsoluteFill style={{ background: '#12141a' }}>
      <Stage p={p} neo={false} W={W} H={H} />
      <div style={{ position: 'absolute', left: 0, top: 0, width: 1710 * K, height: 1107 * K, transformOrigin: '0 0', transform: m }}>
        <div style={{ position: 'absolute', left: 0, top: 0, width: 1710, height: 1107, zoom: K } as React.CSSProperties}>
          <Screen t={t} />
        </div>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 470, background: 'linear-gradient(to bottom, rgba(6,8,14,0), rgba(6,8,14,.88) 55%)' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 120, textAlign: 'center', fontFamily: '"PingFang SC",-apple-system,sans-serif', fontSize: 168, fontWeight: 800,
        color: '#fff', letterSpacing: 4, textShadow: '0 6px 30px rgba(0,0,0,.7)' }}>{text}</div>
    </AbsoluteFill>
  );
}
