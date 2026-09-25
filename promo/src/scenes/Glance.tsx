import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { GLANCE, sceneFrames } from "../timeline";
import { C, FONT, SERIF, easeInOut, easeOut, mix, pop, tw } from "../theme";
import { Caption, Canvas, Cursor, Lines, MacWindow, tiltIn, useVertical } from "../ui";

// Rest on a 卷帘条 and a card drops below it, live. Move away and it goes back up.
// The window in the card is exporting, so you can see the picture is live.

const K = 1.6;
const LAYOUT = {
  h: { STRIP: { x: 230, y: 330, w: 820 }, DRAFT: { x: 780, y: 420, w: 960, h: 600 }, from: [1500, 1000], away: [1480, 820] },
  v: { STRIP: { x: 130, y: 520, w: 820 }, DRAFT: { x: 100, y: 760, w: 880, h: 900 }, from: [1000, 1800], away: [900, 1500] },
};
const BAR = 36 * K;
const CARD_H = 380;

const Exporting: React.FC<{ pct: number; frame: number }> = ({ pct, frame }) => (
  <div style={{ padding: "40px 48px", fontFamily: FONT, color: C.winInk }}>
    <div style={{ display: "flex", gap: 16 }}>
      {[0, 1, 2, 3, 4].map((i) => (
        <div
          key={i}
          style={{
            flex: 1,
            height: 120,
            borderRadius: 14,
            background: `linear-gradient(${140 + i * 30 + frame * 0.6}deg, #c9dbff, #f1d9ee 55%, #ffe3c9)`,
            opacity: i / 5 < pct ? 1 : 0.35,
          }}
        />
      ))}
    </div>
    <div style={{ display: "flex", justifyContent: "space-between", marginTop: 36, fontSize: 30, fontWeight: 600 }}>
      <span>宣传片.mov</span>
      <span style={{ fontVariantNumeric: "tabular-nums", color: C.accent }}>{Math.round(pct * 100)}%</span>
    </div>
    <div style={{ height: 12, borderRadius: 99, background: "rgba(0,0,0,.07)", marginTop: 18, overflow: "hidden" }}>
      <div style={{ width: `${pct * 100}%`, height: "100%", borderRadius: 99, background: C.accent }} />
    </div>
    <div style={{ fontSize: 24, color: C.winMuted, marginTop: 16 }}>还剩 {Math.max(1, Math.round((1 - pct) * 6))} 分钟</div>
  </div>
);

export const Glance: React.FC = () => {
  const frame = useCurrentFrame();
  const { STRIP, DRAFT, from, away } = LAYOUT[useVertical() ? "v" : "h"];
  const REST = { x: STRIP.x + STRIP.w / 2 + 90, y: STRIP.y + BAR / 2 + 4 };
  const arrive = tw(frame, 12, GLANCE.arrive, 0, 1, easeOut);
  const leave = tw(frame, GLANCE.leave, GLANCE.leave + 30, 0, 1, easeInOut);
  const cx = mix(mix(from[0], REST.x, arrive), away[0], leave);
  const cy = mix(mix(from[1], REST.y, arrive), away[1], leave);
  const open = frame < GLANCE.leave + 4 ? pop(frame, GLANCE.open, 22, 220) : 1 - tw(frame, GLANCE.leave + 4, GLANCE.leave + 20, 0, 1, easeOut);
  const pct = 0.42 + 0.003 * Math.max(0, frame - 20);

  return (
    <Canvas>
      <Caption zh="停一下，就看到。" en="Rest on the bar. See the window." at={2} out={GLANCE.second - 14} />
      <Caption zh="不用展开，也不用切过去。" en="No unrolling. No switching apps." at={GLANCE.second} />
      <AbsoluteFill style={{ scale: String(mix(1, 1.04, tw(frame, 0, sceneFrames("Glance"), 0, 1, easeInOut))), transformOrigin: "30% 45%" }}>
        <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, 0, { y: 160, rx: 20 }) }}>
          <MacWindow {...DRAFT} title="文章草稿" k={K} active>
            <div style={{ padding: "60px 70px", color: C.winInk }}>
              <div style={{ fontSize: 26, fontWeight: 600, color: C.winMuted }}>一个小动作的历史</div>
              <div style={{ fontFamily: SERIF, fontSize: 84, lineHeight: 1.15, margin: "20px 0 32px" }}>
                先让开，
                <br />
                待会儿回来。
              </div>
              <Lines k={K} widths={[100, 92, 96, 60]} />
            </div>
          </MacWindow>
        </div>
        <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, 8, { y: 120, rx: 20 }) }}>
          <MacWindow x={STRIP.x} y={STRIP.y} w={STRIP.w} h={BAR + 10} title="正在导出" k={K} roll={1} />
          {open > 0.001 ? (
            <div
              style={{
                position: "absolute",
                left: STRIP.x,
                top: STRIP.y + BAR + 14,
                width: STRIP.w,
                height: CARD_H,
                borderRadius: 18 * K,
                overflow: "hidden",
                background: C.win,
                transformOrigin: "50% 0",
                scale: `${mix(0.96, 1, open)} ${mix(0.8, 1, open)}`,
                opacity: Math.min(1, open * 1.6),
                clipPath: `inset(0 0 ${(1 - Math.min(1, open)) * 100}% 0 round ${18 * K}px)`,
                boxShadow: "0 0 0 .6px rgba(0,0,0,.28), 0 18px 50px rgba(22,28,45,.28)",
              }}
            >
              <Exporting pct={pct} frame={frame} />
            </div>
          ) : null}
        </div>
        <Cursor x={cx} y={cy} size={50} opacity={tw(frame, 10, 18)} />
      </AbsoluteFill>
    </Canvas>
  );
};
