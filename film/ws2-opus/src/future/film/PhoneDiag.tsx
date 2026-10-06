// 手機穿幫的診斷台。同一支 `Phone`、同一個 `Studio`、同一個鏡頭，只切換畫什麼：
//   1 全開（機身＋螢幕貼圖）      2 只有機身（原材質）
//   3 只有機身（強制法線材質）    4 只有螢幕貼圖
//   5 俯視：全開                  6 俯視：只有機身（法線材質）
// 目的是把「機身根本不在」「機身在但太暗讀不出來」「貼圖蓋滿正面」三種可能分開，
// 不要憑猜。3 與 4 的剪影可以直接量出顯示區內縮了幾毫米。
import { useThree } from '@react-three/fiber';
import { AbsoluteFill, staticFile } from 'remotion';
import { ThreeCanvas, useOffthreadVideoTexture } from '@remotion/three';
import { useLayoutEffect } from 'react';
import * as THREE from 'three';
import { Phone, Studio, Laptop } from './stage';
import { SEAT, shotAt } from './shot';

const CELL = 960;
/** live 段的代表幀（60 fps），手機在畫面裡、字幕是「车快到了」。 */
const LIVE_F = 1860;

function FilmCam() {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  useLayoutEffect(() => {
    const p = shotAt(LIVE_F);
    camera.fov = p.fov;
    camera.near = 0.02;
    camera.far = 40;
    camera.position.set(p.pos[0], p.pos[1], p.pos[2]);
    camera.lookAt(p.aim[0], p.aim[1], p.aim[2]);
    camera.updateProjectionMatrix();
  }, [camera]);
  return null;
}

function TopCam() {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  useLayoutEffect(() => {
    camera.fov = 36;
    camera.near = 0.02;
    camera.far = 40;
    camera.position.set(SEAT.air + 0.16, 0.72, 0.14);
    camera.lookAt(SEAT.air - 0.06, 0.0, -0.05);
    camera.updateProjectionMatrix();
  }, [camera]);
  return null;
}

function Cell({ title, children, cam }: { title: string; children: React.ReactNode; cam: 'film' | 'top' }) {
  return (
    <div style={{ position: 'relative', width: CELL, height: CELL, background: '#2b2e35', overflow: 'hidden' }}>
      <ThreeCanvas
        width={CELL}
        height={CELL}
        dpr={1}
        gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1 }}
        camera={{ fov: 30, near: 0.02, far: 40, position: [0, 0.4, 1] }}
      >
        {cam === 'film' ? <FilmCam /> : <TopCam />}
        <Studio />
        {children}
      </ThreeCanvas>
      <div style={{ position: 'absolute', left: 8, top: 8, color: '#ffd24a', fontSize: 17, fontFamily: 'ui-sans-serif' }}>{title}</div>
    </div>
  );
}

function AirWithPlate() {
  const tex = useOffthreadVideoTexture({ src: staticFile('future/plates/air.mp4'), toneMapped: false });
  return <Laptop m="air" texture={tex} x={SEAT.air} />;
}

export function PhoneDiag() {
  return (
    <AbsoluteFill style={{ background: '#0d0e12', flexDirection: 'row', flexWrap: 'wrap' }}>
      <Cell title="1 全開：機身＋貼圖" cam="film">
        <Phone f={LIVE_F} />
      </Cell>
      <Cell title="2 只有機身（原材質）" cam="film">
        <Phone f={LIVE_F} hideCard />
      </Cell>
      <Cell title="3 只有機身（法線材質）" cam="film">
        <Phone f={LIVE_F} hideCard debugBody />
      </Cell>
      <Cell title="4 只有貼圖" cam="film">
        <Phone f={LIVE_F} hideBody />
      </Cell>
      <Cell title="5 俯視：全開（含 Air）" cam="top">
        <AirWithPlate />
        <Phone f={LIVE_F} />
      </Cell>
      <Cell title="6 俯視：只有機身（法線）" cam="top">
        <Phone f={LIVE_F} hideCard debugBody />
      </Cell>
    </AbsoluteFill>
  );
}
