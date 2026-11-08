import type { CSSProperties } from 'react';
import { SLOTS, type SlotFrame } from '../scene';
import type { Layout } from '../layout';

const FONT = '"Source Han Sans SC","Noto Sans SC","PingFang SC",sans-serif';

/** 没录的真机画面：一块写着要录什么的灰块。不画任何界面。 */
export function Placeholder({ L, slot }: { L: Layout; slot: SlotFrame }) {
  const { w: SW, h: SH } = L.screen;
  const cqw = SW / 100;
  const r = { x: (slot.rect.x / 100) * SW, y: (slot.rect.y / 100) * SH, w: (slot.rect.w / 100) * SW, h: (slot.rect.h / 100) * SH };
  const info = SLOTS[slot.id];
  const size = Math.max(15, Math.min(cqw * 1.75, r.w * 0.075));
  const style: CSSProperties = {
    position: 'absolute', left: r.x, top: r.y, width: r.w, height: r.h,
    transform: `scale(${slot.scale})`, transformOrigin: '50% 50%',
    borderRadius: slot.radius * cqw, opacity: slot.opacity, overflow: 'hidden',
    background: '#171a20', boxShadow: `inset 0 0 0 ${Math.max(1.5, cqw * 0.14)}px rgba(255,255,255,.28)`,
    backgroundImage: 'repeating-linear-gradient(135deg, rgba(255,255,255,.035) 0 10px, transparent 10px 20px)',
    fontFamily: FONT, color: 'rgba(255,255,255,.86)',
  };
  return (
    <div style={style}>
      <div style={{ position: 'absolute', left: size * 1.1 + ((info.labelLeft ?? 0) / 100) * r.w, right: size * 1.1, top: size * 1.0, lineHeight: 1.4 }}>
        <div style={{ fontSize: size, fontWeight: 600 }}>真机画面：{info.record}</div>
        <div style={{ fontSize: size * 0.82, marginTop: size * 0.4, color: 'rgba(255,255,255,.6)' }}>约 {info.seconds} 秒 · {info.how}</div>
      </div>
      <div style={{ position: 'absolute', right: size * 0.8, bottom: size * 0.6, fontSize: size * 0.8, color: 'rgba(255,255,255,.4)', fontFamily: 'Inter, sans-serif' }}>{info.id}</div>
    </div>
  );
}
