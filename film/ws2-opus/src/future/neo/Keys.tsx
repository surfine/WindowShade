// 关键帧样张：一帧一张，给 Aaron 过目用，不进成片。
// 推近不靠把画面放大：U（每厘米多少像素）和透视距离一起乘 zoom，等于换长焦，近处的底座不会穿过镜头。
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { CJK } from '../glyphs';
import { NEO } from './geom';
import { Neo, screenPoint, type Cam } from './Neo';
import { NeoScreen, type ScreenState } from './NeoScreen';

const U0 = 34, P0 = 2600;

type Key = { name: string; zoom: number; cam: Omit<Cam, 'dolly'> & { dolly?: number }; s: ScreenState; camOn?: boolean };

const mid: [number, number, number] = [0, -5.5, NEO.depth * 0.22];

export const KEYS: Key[] = [
  { name: 'K1 開場：錫色 Neo，盖子 113°，俯 17°', zoom: 0.9, cam: { elev: 17, yaw: -24, focus: mid }, s: { lock: 1, island: { kind: 'rest' } } },
  { name: 'K2 刷臉：鏡頭旁綠燈亮，島裡是 Face ID 符號', zoom: 3.1, cam: { elev: 9, yaw: -12, focus: screenPoint(704, 70) }, s: { lock: 1, island: { kind: 'face', scan: 1, ok: 0, sweep: 0.62 } }, camOn: true },
  { name: 'K3 點島開啟動台：指標落在島上（屏上畫的，看得見）', zoom: 1.7, cam: { elev: 13, yaw: 15, focus: screenPoint(704, 330) }, s: { lock: 0, island: { kind: 'hover' }, launch: 0.42, cursor: { x: 712, y: 16, press: 0.8 } } },
  { name: 'K4 讀唇：線描口型 + 打字游標，沒有臉', zoom: 4.4, cam: { elev: 6, yaw: -6, focus: screenPoint(704, 52) }, s: { lock: 0, island: { kind: 'lips', open: 0.55, text: '放到左半', caret: true } }, camOn: true },
  { name: 'K5 點頭：耳機往下點，左半屏預覽等確認', zoom: 1.9, cam: { elev: 10, yaw: 9, focus: screenPoint(560, 300) }, s: { lock: 0, island: { kind: 'nod', tilt: 14, ok: 0 }, ghost: true } },
  { name: 'K6 走開就鎖：高機位，島裡一把鎖', zoom: 0.92, cam: { elev: 26, yaw: 30, focus: mid }, s: { lock: 1, island: { kind: 'lock' } } },
];

export function NeoKeys() {
  const f = useCurrentFrame();
  const k = KEYS[Math.min(KEYS.length - 1, f)];
  return (
    <AbsoluteFill style={{ background: 'radial-gradient(90% 80% at 50% 35%, #1d1f24 0%, #0d0e11 60%, #060607 100%)', overflow: 'hidden' }}>
      <Neo cam={{ dolly: 0, ...k.cam }} U={U0 * k.zoom} persp={P0 * k.zoom} camOn={k.camOn} screen={<NeoScreen s={k.s} />} />
      <div style={{ position: 'absolute', left: 36, bottom: 28, fontFamily: CJK, fontSize: 22, color: 'rgba(255,255,255,.55)' }}>{k.name}</div>
    </AbsoluteFill>
  );
}
