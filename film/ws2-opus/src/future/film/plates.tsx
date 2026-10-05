// 螢幕畫面先畫成平面，再貼到顯示網格上。高度凑成偶數，多出來的一列是黑的。
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import type { MachineId } from './machines';
import { ScreenView } from './Screen';

export const PLATE = {
  neo: { w: 1408, h: 882 },
  air: { w: 1710, h: 1108 },
} as const;

export const PlateNeo = () => <Plate m="neo" />;
export const PlateAir = () => <Plate m="air" />;

export function Plate({ m }: { m: MachineId }) {
  const f = useCurrentFrame() * 2;
  return (
    <AbsoluteFill style={{ background: '#000' }}>
      <ScreenView m={m} f={f} physicalNotch />
    </AbsoluteFill>
  );
}
