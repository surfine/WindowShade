// 符号：照 SF Symbols 的线宽与比例手画（菜单栏、刘海里用到的几个）。
import { clamp01, mix } from './time';

export const SF = '"SF Pro Text","SF Pro",-apple-system,"PingFang SC",sans-serif';
export const SFD = '"SF Pro Display","SF Pro",-apple-system,"PingFang SC",sans-serif';
export const SFR = '"SF Pro Rounded","SF Pro",-apple-system,"PingFang SC",sans-serif';
export const MONO = '"SF Mono",ui-monospace,Menlo,monospace';
export const CJK = '"PingFang SC","SF Pro Text",-apple-system,sans-serif';

type P = { size: number; color?: string };

export const Wifi = ({ size, color = '#fff' }: P) => (
  <svg width={size} height={size * 0.75} viewBox="0 0 24 18">
    {[0, 1, 2].map((i) => {
      const r = 4 + i * 5.2;
      return <path key={i} d={`M ${12 - r * 0.78} ${16 - r * 0.62} A ${r} ${r} 0 0 1 ${12 + r * 0.78} ${16 - r * 0.62}`} fill="none" stroke={color} strokeWidth={2.3} strokeLinecap="round" />;
    })}
    <circle cx={12} cy={15.6} r={1.9} fill={color} />
  </svg>
);

export const Battery = ({ size, color = '#fff', level = 0.82 }: P & { level?: number }) => (
  <svg width={size} height={size * 0.46} viewBox="0 0 28 13">
    <rect x={0.75} y={0.75} width={23.5} height={11.5} rx={3.6} fill="none" stroke={color} strokeOpacity={0.45} strokeWidth={1.2} />
    <rect x={2.4} y={2.4} width={20.2 * level} height={8.2} rx={2} fill={color} />
    <path d="M 25.6 4.4 Q 27.2 4.6 27.2 6.5 Q 27.2 8.4 25.6 8.6 Z" fill={color} fillOpacity={0.45} />
  </svg>
);

export const ControlCenter = ({ size, color = '#fff' }: P) => (
  <svg width={size} height={size} viewBox="0 0 20 20">
    <rect x={2} y={3.2} width={16} height={5.6} rx={2.8} fill="none" stroke={color} strokeWidth={1.5} />
    <circle cx={6.1} cy={6} r={1.7} fill={color} />
    <rect x={2} y={11.2} width={16} height={5.6} rx={2.8} fill="none" stroke={color} strokeWidth={1.5} />
    <circle cx={13.9} cy={14} r={1.7} fill={color} />
  </svg>
);

export const Search = ({ size, color = '#fff' }: P) => (
  <svg width={size} height={size} viewBox="0 0 20 20">
    <circle cx={8.4} cy={8.4} r={5.6} fill="none" stroke={color} strokeWidth={1.9} />
    <path d="M 12.6 12.6 L 17 17" stroke={color} strokeWidth={2.1} strokeLinecap="round" />
  </svg>
);

export const Lock = ({ size, color = '#fff', open = 0 }: P & { open?: number }) => (
  <svg width={size} height={size} viewBox="0 0 20 20">
    <path d={`M 6 ${9} V ${6.4 - open * 0} A 4 4 0 0 1 14 6.4 V ${mix(9, 6.6, open)}`} transform={`translate(${open * 5.2} 0)`} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
    <rect x={3.6} y={8.6} width={12.8} height={9.4} rx={2.4} fill={color} />
  </svg>
);

export const IPhone = ({ size, color = '#fff' }: P) => (
  <svg width={size * 0.56} height={size} viewBox="0 0 14 25">
    <rect x={1} y={1} width={12} height={23} rx={3.2} fill="none" stroke={color} strokeWidth={1.6} />
    <rect x={5.1} y={2.8} width={3.8} height={1.3} rx={0.65} fill={color} />
  </svg>
);

/** AirPods Pro：两只，柄朝下。tilt 是点头（度），sway 是摇头（度）。 */
export const AirPods = ({ size, color = '#fff', tilt = 0, sway = 0 }: P & { tilt?: number; sway?: number }) => (
  <svg width={size} height={size} viewBox="0 0 32 32" style={{ overflow: 'visible' }}>
    <g transform={`rotate(${sway} 16 16) translate(0 ${tilt * 0.12}) rotate(${tilt * 0.5} 16 10)`}>
      {[0, 1].map((i) => (
        <g key={i} transform={i ? 'translate(32 0) scale(-1 1)' : undefined}>
          <path d="M 3.6 8 C 3.4 3.4 9.6 1.8 12.6 4.6 C 14.6 6.6 14.2 10.6 11.4 12 L 11 25 A 1.9 1.9 0 0 1 7.2 25 L 7.4 13.2 C 5 12.6 3.7 10.6 3.6 8 Z" fill={color} />
          <ellipse cx={12.3} cy={7.6} rx={1.1} ry={1.9} fill="#000" fillOpacity={0.5} />
        </g>
      ))}
    </g>
  </svg>
);

export const Check = ({ size, color = '#30D158', draw = 1, ring = true }: P & { draw?: number; ring?: boolean }) => (
  <svg width={size} height={size} viewBox="0 0 30 30">
    {ring && <circle cx={15} cy={15} r={13.5} fill={color} />}
    <path d="M 8.6 15.6 L 13 20 L 21.6 10.6" fill="none" stroke={ring ? '#000' : color} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - clamp01(draw)} />
  </svg>
);

export const XMark = ({ size, color = '#8e8e93' }: P) => (
  <svg width={size} height={size} viewBox="0 0 30 30">
    <circle cx={15} cy={15} r={13.5} fill={color} />
    <path d="M 10.2 10.2 L 19.8 19.8 M 19.8 10.2 L 10.2 19.8" stroke="#000" strokeWidth={2.8} strokeLinecap="round" />
  </svg>
);

/**
 * 刷脸：四个角、两只眼、鼻子、笑。scan 0–1 是绕一圈的刻度，ok 0–1 是脸变成勾。
 * 尺寸单位：size 是整个符号的边长。
 */
export function FaceGlyph({ size, scan, ok, sweep }: { size: number; scan: number; ok: number; sweep: number }) {
  const C = 50, ticks = 56;
  const green = '#30D158';
  const face = 1 - clamp01(ok * 1.6);
  const ink = ok > 0.02 ? green : '#fff';
  const corner = (rot: number) => (
    <path key={rot} d="M 22 8 H 16 A 8 8 0 0 0 8 16 V 22" fill="none" stroke={ink} strokeWidth={3.2} strokeLinecap="round" transform={`rotate(${rot} 50 50) translate(${-ok * 3} ${-ok * 3})`} />
  );
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" style={{ overflow: 'visible' }}>
      {Array.from({ length: ticks }, (_, i) => {
        const a = (i / ticks) * Math.PI * 2 - Math.PI / 2;
        const u = i / ticks;
        // 扫描头走到哪里，哪里亮；身后留一截渐暗的尾巴。
        const lag = ((sweep - u) % 1 + 1) % 1;
        const lit = clamp01(scan) > u ? 0.42 + 0.58 * Math.max(0, 1 - lag * 3.2) : 0.12;
        const done = clamp01(ok * 2.2 - u * 0.6);
        const r0 = 62 + done * 2, r1 = mix(71, 76, done) + (lag < 0.08 && ok < 0.01 ? 4 : 0);
        return (
          <line
            key={i}
            x1={C + Math.cos(a) * r0} y1={C + Math.sin(a) * r0} x2={C + Math.cos(a) * r1} y2={C + Math.sin(a) * r1}
            stroke={done > 0.01 ? green : '#fff'} strokeOpacity={Math.max(lit, done)} strokeWidth={2.6} strokeLinecap="round"
          />
        );
      })}
      {[0, 90, 180, 270].map(corner)}
      <g opacity={face}>
        <line x1={37} y1={36} x2={37} y2={43} stroke="#fff" strokeWidth={3.2} strokeLinecap="round" />
        <line x1={63} y1={36} x2={63} y2={43} stroke="#fff" strokeWidth={3.2} strokeLinecap="round" />
        <path d="M 51 36 V 53 Q 51 56 47.5 56" fill="none" stroke="#fff" strokeWidth={3.2} strokeLinecap="round" strokeLinejoin="round" />
        <path d="M 37 64 Q 50 73 63 64" fill="none" stroke="#fff" strokeWidth={3.2} strokeLinecap="round" />
      </g>
      <path d="M 33 51 L 45 63 L 68 38" fill="none" stroke={green} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={1} strokeDashoffset={1 - clamp01((ok - 0.35) / 0.55)} />
    </svg>
  );
}

/** macOS 的箭头指针。 */
export const Pointer = ({ size }: { size: number }) => (
  <svg width={size} height={size * 1.5} viewBox="0 0 16 24" style={{ overflow: 'visible', filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,.45))' }}>
    <path d="M 1 1 L 1 18.2 L 5.1 14.3 L 7.9 21 L 10.6 19.9 L 7.9 13.4 L 13.6 13.4 Z" fill="#000" stroke="#fff" strokeWidth={1.3} strokeLinejoin="round" />
  </svg>
);
