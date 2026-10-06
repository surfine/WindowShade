// 手機螢幕的高倍率驗收台。
// 目的只有一個：把 iPhone 18 Pro 的顯示面放到夠大，逐角看貼圖有沒有溢出圓角機身、
// 螢幕與邊框交界有沒有黑邊或白邊、邊框金屬有沒有高光與暗反射（不是一整片灰）。
// 用的是片子裡同一支 `Phone` 與同一個 `Studio`，所以量到的就是片子裡畫的。
import { useThree } from '@react-three/fiber';
import { AbsoluteFill } from 'remotion';
import { ThreeCanvas } from '@remotion/three';
import { useLayoutEffect } from 'react';
import * as THREE from 'three';
import { Phone, Studio } from './stage';

/** 每一格：一個角度，鏡頭只繞著手機自己（手機擺在世界原點）。 */
type Shot = { yaw: number; elev: number; dist: number; label: string };
const SHOTS: Shot[] = [
  { yaw: 0, elev: 0, dist: 0.52, label: '正面' },
  { yaw: -20, elev: 5, dist: 0.52, label: '左上斜' },
  { yaw: 20, elev: -5, dist: 0.52, label: '右下斜' },
  { yaw: 48, elev: 0, dist: 0.52, label: '側面（看邊框金屬）' },
];

const CELL = 1150;
/** 手機在世界裡的擺位（和片子同一個 z；x 用 dxOverride 拉回原點好對準）。 */
const PX = 0, PY = 0.15, PZ = -0.062;
/** 外送到達那一段，螢幕上有字，四角與內容都看得出來。 */
const QA_F = 2100;

function PhoneCam({ shot }: { shot: Shot }) {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  useLayoutEffect(() => {
    const yr = (shot.yaw * Math.PI) / 180;
    const er = (shot.elev * Math.PI) / 180;
    camera.fov = 26;
    camera.position.set(PX + shot.dist * Math.sin(yr) * Math.cos(er), PY + shot.dist * Math.sin(er), PZ + shot.dist * Math.cos(yr) * Math.cos(er));
    camera.lookAt(PX, PY, PZ);
    camera.updateProjectionMatrix();
  }, [camera, shot]);
  return null;
}

function Cell({ shot }: { shot: Shot }) {
  return (
    <div style={{ position: 'relative', width: CELL, height: CELL, background: '#2b2e35', overflow: 'hidden' }}>
      <ThreeCanvas
        width={CELL}
        height={CELL}
        dpr={1}
        gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1 }}
        camera={{ fov: 26, near: 0.005, far: 40, position: [0, 0.15, PZ + 0.52] }}
      >
        <PhoneCam shot={shot} />
        <Studio />
        <Phone f={QA_F} dxOverride={-0.28} />
      </ThreeCanvas>
      <div style={{ position: 'absolute', left: 6, top: 6, color: '#ffd24a', fontSize: 14, fontFamily: 'ui-sans-serif' }}>{shot.label} · yaw {shot.yaw}° elev {shot.elev}°</div>
    </div>
  );
}

export function PhoneQA() {
  return (
    <AbsoluteFill style={{ background: '#1b1d22', flexDirection: 'row', flexWrap: 'wrap' }}>
      {SHOTS.map((s) => (
        <Cell key={s.label} shot={s} />
      ))}
    </AbsoluteFill>
  );
}
