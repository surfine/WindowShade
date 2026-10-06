// 符号：照 SF Symbols 的线宽与比例手画（菜单栏、刘海里用到的几个）。
// 解鎖那一格（faceid / iphone / lock / 圓勾圓叉）已經換成 **真的 SF Symbols**，
// 見 `symbols.ts`（產物，由 `tools/gen-symbols.mjs` 從 macOS 的符號資料抽向量外框）。
import type { CSSProperties } from 'react';
import { SYMBOLS, LOCK_FRAME, type SymName } from './symbols';
import { clamp01, mix } from './time';

export const SF = '"SF Pro Text","SF Pro",-apple-system,"PingFang SC",sans-serif';
export const SFD = '"SF Pro Display","SF Pro",-apple-system,"PingFang SC",sans-serif';
export const SFR = '"SF Pro Rounded","SF Pro",-apple-system,"PingFang SC",sans-serif';
export const MONO = '"SF Mono",ui-monospace,Menlo,monospace';
export const CJK = '"PingFang SC","SF Pro Text",-apple-system,sans-serif';

type P = { size: number; color?: string };

const box = (viewBox: string) => viewBox.split(' ').map(Number);

/**
 * 真 SF Symbols 的畫法。`d` 是 Apple 自己那份向量外框（見 `symbols.ts`）。
 *
 * `size` 是**墨跡高度**（px），跟這支檔案裡其他手畫符號同語意：
 * 舊的手畫符號也是「size 就是畫出來多高」，換來源才不會忽然大一號。
 * 寬度按符號自己的長寬比走（例：`iphone` 在 size=30 時是 18.9×30）。
 */
export function Sym({ name, size, color = '#fff', opacity, frame, style }: {
  name: SymName; size: number; color?: string; opacity?: number; frame?: string; style?: CSSProperties;
}) {
  const s = SYMBOLS[name];
  const [vx, vy, vw, vh] = box(frame ?? s.viewBox);
  const k = size / vh;
  return (
    <svg width={vw * k} height={vh * k} viewBox={`${vx} ${vy} ${vw} ${vh}`} style={{ display: 'block', flex: 'none', ...style }} aria-hidden>
      <path d={s.d} fill={color} fillOpacity={opacity} fillRule="evenodd" />
    </svg>
  );
}

/** 實心圓＋挖空的符號（`checkmark.circle.fill`／`xmark.circle.fill`）：
 *  Apple 是「整塊圓餅、符號挖空」。舊的手畫版挖空處是塗黑的，
 *  所以底下墊一顆同尺寸的黑圓，圓餅蓋上去之後挖空處就是黑的，跟舊版一致。 */
function Disc({ name, size, color, inner = '#000', opacity, style }: {
  name: SymName; size: number; color: string; inner?: string; opacity?: number; style?: CSSProperties;
}) {
  const s = SYMBOLS[name];
  const [vx, vy, vw, vh] = box(s.viewBox);
  const k = size / vh;
  const r = Math.min(vw, vh) / 2;
  return (
    <svg width={vw * k} height={vh * k} viewBox={s.viewBox} style={{ display: 'block', flex: 'none', ...style }} aria-hidden>
      <circle cx={vx + vw / 2} cy={vy + vh / 2} r={r} fill={inner} />
      <path d={s.d} fill={color} fillOpacity={opacity} fillRule="evenodd" />
    </svg>
  );
}


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

/** 鎖：真的 `lock.fill`／`lock.open.fill`。
 *  兩態各自正規化的話鎖體會忽大忽小，所以疊在 `LOCK_FRAME`（兩者聯集）裡，
 *  並把每一態自己的墨跡在框中置中——這樣鎖體留在原地，只有鎖扣轉開。
 *  0.83 是舊手畫版「墨跡高 / 名目 size」的比值（20 格的框裡墨跡只有 16.6 格），
 *  乘上去，呼叫點的 `size` 才維持原來的視覺大小。 */
const LOCK_INK = 0.83;

export const Lock = ({ size, color = '#fff', open = 0 }: P & { open?: number }) => {
  const [fx, fy, fw, fh] = box(LOCK_FRAME);
  const k = (size * LOCK_INK) / box(SYMBOLS['lock.fill'].viewBox)[3];
  const shift = (n: SymName) => {
    const [x, y, w, h] = box(SYMBOLS[n].viewBox);
    return `translate(${(fw - w) / 2 + (fx - x)} ${(fh - h) / 2 + (fy - y)})`;
  };
  const t = clamp01(open);
  return (
    <svg width={fw * k} height={fh * k} viewBox={LOCK_FRAME} style={{ display: 'block', flex: 'none' }} aria-hidden>
      {t < 1 && <g transform={shift('lock.fill')}><path d={SYMBOLS['lock.fill'].d} fill={color} fillOpacity={1 - t} fillRule="evenodd" /></g>}
      {t > 0 && <g transform={shift('lock.open.fill')}><path d={SYMBOLS['lock.open.fill'].d} fill={color} fillOpacity={t} fillRule="evenodd" /></g>}
    </svg>
  );
};

/** iPhone：真的 `iphone` 符號（帶動態島的那顆）。
 *  0.96 = 舊手畫版墨跡高 / 名目 size（25 格的框裡墨跡 24 格），維持原本大小。 */
export const IPhone = ({ size, color = '#fff' }: P) => <Sym name="iphone" size={size * 0.96} color={color} />;

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

/** 綠勾：真的 `checkmark.circle.fill`（`ring={false}` 時用裸的 `checkmark`）。
 *  `draw` 以前是拉一條虛線把勾畫出來；真符號是整塊圓餅，所以改成 Apple 那種
 *  「彈出來」：由小放大 + 淡入，時間點不變。 */
export const Check = ({ size, color = '#30D158', draw = 1, ring = true }: P & { draw?: number; ring?: boolean }) => {
  const a = clamp01(draw);
  if (!ring) return <Sym name="checkmark" size={size * 0.52} color={color} opacity={a} style={{ transform: `scale(${mix(0.82, 1, a)})` }} />;
  return <Disc name="checkmark.circle.fill" size={size * 0.9} color={color} opacity={a} style={{ transform: `scale(${mix(0.82, 1, a)})`, transformOrigin: 'center' }} />;
};

export const XMark = ({ size, color = '#8e8e93' }: P) => <Disc name="xmark.circle.fill" size={size * 0.9} color={color} />;

/**
 * 刷臉：真的 `faceid` SF Symbol（見 `symbols.ts`），認出來換成真的 `checkmark`。
 *
 * 為什麼換掉舊的：舊版這顆是手畫的——`viewBox="0 0 100 100"`、56 根刻度繞一圈、
 * 四角括號、中間一個勾。那不是 Apple 的符號，Aaron 看到的「掃描轉盤」就是它。
 *
 * 動畫對映（照 Apple 實際的樣子，不自創）：
 *   掃描中 = `faceid`，由暗亮起來（`scan` 0→1：亮度 0.45→1、尺度 0.96→1 落定）；
 *   認出來 = 換成 `checkmark`（`ok` 0→1 交叉淡入、由小彈出來）。
 *   真符號沒有「跑一圈」的漸進動畫可接：`faceid` 在 macOS 這版 AppKit 取不到可變色
 *   圖層（`NSImage.SymbolConfiguration` 只有 `pointSize:weight:`，沒有 `variableValue:`），
 *   所以不假造刻度環。`sweep` 是舊版「亮環掃過」的參數，真符號沒有對應物，保留簽名不用。
 */
export function FaceGlyph({ size, scan, ok }: { size: number; scan: number; ok: number; sweep?: number }) {
  const green = '#30D158';
  const lock = clamp01(scan);
  const done = clamp01(ok);
  // 尺寸對照舊手畫版量出來的：舊版在 100 格框裡，外圈刻度直徑 1.43（66/46）、
  // 四角方框 0.84（38.6/46）。真 `faceid` 就是那個方框本身（外圈是自創的，本來不該有），
  // 但只按方框放會讓這一格明顯變小，所以取 1.05：比方框大一點、離舊外圈還有段距離，
  // 跟旁邊 30 的 `iphone`（墨跡 29）站在一起輕重才對。
  return (
    <div style={{ position: 'relative', width: size, height: size, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Sym name="faceid" size={size * 1.05} color={done > 0.02 ? green : '#fff'} opacity={mix(0.45, 1, lock) * (1 - done)} style={{ position: 'absolute', transform: `scale(${mix(0.96, 1, lock)})` }} />
      <Sym name="checkmark" size={size * 0.78} color={green} opacity={done} style={{ position: 'absolute', transform: `scale(${mix(0.84, 1, done)})` }} />
    </div>
  );
}


/** 選單列最左邊那顆蘋果（實心）。以前這裡掛的是空字串，選單列左端就空一格、看起來像壞掉。 */
export const AppleLogo = ({ size, color = '#fff' }: P) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color}>
    <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
  </svg>
);

/** macOS 的箭头指针。 */
export const Pointer = ({ size }: { size: number }) => (
  <svg width={size} height={size * 1.5} viewBox="0 0 16 24" style={{ overflow: 'visible', filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,.45))' }}>
    <path d="M 1 1 L 1 18.2 L 5.1 14.3 L 7.9 21 L 10.6 19.9 L 7.9 13.4 L 13.6 13.4 Z" fill="#000" stroke="#fff" strokeWidth={1.3} strokeLinejoin="round" />
  </svg>
);
