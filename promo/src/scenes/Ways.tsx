import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { WAYS } from "../timeline";
import { C, FONT, easeInOut, easeOut, easeRoll, mix, pop, tw } from "../theme";
import { Caption, Canvas, Clicks, Glass, Lines, MacWindow, Rise, tiltIn, useVertical } from "../ui";

// Three ways out of the way, side by side: close, minimize, roll up. Only the last one stays put.

const COLS = [390, 960, 1530];
const W = 520;
const H = 340;
const TOP = 350;
const K = 1.3;

// Where each of the three sits: side by side in 16:9, one per row in 9:16 (label on the right).
const ROWS_V = [470, 930, 1390];
const geo = (i: number, v: boolean) =>
  v
    ? {
        x: 60,
        top: ROWS_V[i],
        label: { left: 620, top: ROWS_V[i] + 80, width: 420, align: "left" as const },
        dock: { left: 620, top: ROWS_V[i] + 250 },
      }
    : {
        x: COLS[i] - W / 2,
        top: TOP,
        label: { left: COLS[i] - 260, top: TOP + H + 44, width: 520, align: "center" as const },
        dock: { left: COLS[i] - 150, top: TOP + H + 200 },
      };

const labels = [
  ["关掉", "Close", "窗口没了", "Gone"],
  ["最小化", "Minimize", "进了 Dock", "Off to the Dock"],
  ["收起", "Roll up", "还在原处", "Right where it was"],
];

const Body: React.FC = () => (
  <div style={{ padding: 30, color: C.blueText }}>
    <div style={{ fontSize: 17, fontWeight: 600, color: C.accent }}>手册摘录 · 1994</div>
    <div style={{ fontFamily: '"Iowan Old Style","Songti SC",serif', fontSize: 34, marginTop: 10, marginBottom: 22 }}>System 7.5 手册</div>
    <Lines k={K} widths={[100, 88, 70]} color="rgba(33,72,132,.12)" />
  </div>
);

export const Ways: React.FC = () => {
  const frame = useCurrentFrame();
  const v = useVertical();
  const focus = tw(frame, WAYS.focus, WAYS.focus + 80, 0, 1, easeInOut);

  // Close: shrink, blur, gone.
  const c = tw(frame, WAYS.close + 2, WAYS.close + 22, 0, 1, easeOut);
  // Minimize: squeeze toward the Dock below.
  const mz = tw(frame, WAYS.minimize + 4, WAYS.minimize + 34, 0, 1, easeInOut);
  // Roll up: in place.
  const roll = tw(frame, WAYS.shade + 10, WAYS.shade + 40, 0, 1, easeRoll);

  const lampPulse = (at: number) => 1 + 0.5 * Math.sin(Math.PI * tw(frame, at - 8, at + 4, 0, 1));
  const dock = pop(frame, WAYS.minimize - 24, 18, 160);

  return (
    <Canvas>
      <Caption zh="让开的办法有三种。" en="Three ways to get a window out of the way." at={0} out={WAYS.focus - 16} />
      <Caption zh="只有一种，不用回头找。" en="Only one leaves it where it was." at={WAYS.focus} />
      <AbsoluteFill
        style={{
          scale: String(mix(1, v ? 1.08 : 1.32, focus)),
          translate: v ? `0px ${mix(0, -460, focus)}px` : `${mix(0, -(COLS[2] - 960) * 1.32, focus)}px ${mix(0, 40, focus)}px`,
        }}
      >
        {COLS.map((_, i) => {
          const dim = i < 2 ? mix(1, 0.22, focus) : 1;
          const g = geo(i, v);
          const x = g.x;
          const TOP = g.top;
          let style: React.CSSProperties = {};
          if (i === 0) style = { opacity: 1 - c, scale: String(1 - c * 0.14), filter: `blur(${c * 12}px)` };
          if (i === 1)
            style = {
              opacity: mz < 1 ? 1 : 0,
              transformOrigin: `${g.dock.left + 150}px ${g.dock.top + 33}px`,
              transform: `translateY(${mz * 60}px) scale(${mix(1, 0.1, mz)}, ${mix(1, 0.06, Math.min(1, mz * 1.3))})`,
            };
          return (
            <div key={i} style={{ position: "absolute", inset: 0, opacity: dim, filter: i < 2 && focus > 0 ? `blur(${focus * 3}px)` : undefined }}>
              <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, WAYS.cards[i], { y: 160, rx: 30 }) }}>
                <div style={{ position: "absolute", inset: 0, ...style }}>
                  <MacWindow x={x} y={TOP} w={W} h={H} title="参考资料" k={K} roll={i === 2 ? roll : 0} body={C.blueSoft}>
                    <Body />
                  </MacWindow>
                  {/* the lamp that does the work pulses first */}
                  {i < 2 ? (
                    <div
                      style={{
                        position: "absolute",
                        left: x + 13 * K + i * 23 * K - 4,
                        top: TOP + 18 * K - 7 * K - 4,
                        width: 14 * K + 8,
                        height: 14 * K + 8,
                        borderRadius: "50%",
                        boxShadow: `0 0 0 3px ${i === 0 ? "rgba(236,106,94,.5)" : "rgba(244,191,79,.6)"}`,
                        opacity:
                          tw(frame, (i === 0 ? WAYS.close : WAYS.minimize) - 10, (i === 0 ? WAYS.close : WAYS.minimize) - 4) *
                          (1 - tw(frame, (i === 0 ? WAYS.close : WAYS.minimize) + 2, (i === 0 ? WAYS.close : WAYS.minimize) + 10)),
                        scale: String(lampPulse(i === 0 ? WAYS.close : WAYS.minimize)),
                      }}
                    />
                  ) : null}
                </div>
                {i === 2 ? <Clicks x={x + W / 2 + 30} y={TOP + 18 * K} at={[WAYS.shade, WAYS.shade + 8]} /> : null}
              </div>
              {i === 1 ? (
                <Glass
                  radius={22}
                  style={{ left: g.dock.left, top: g.dock.top, width: 300, height: 66, opacity: dock, scale: String(0.9 + 0.1 * dock) }}
                >
                  <div style={{ position: "relative", display: "flex", gap: 12, padding: 10, justifyContent: "center" }}>
                    {["#3d7bf7", "#f2a93b", "#48b865", C.blueSoft].map((bg, j) => (
                      <div
                        key={j}
                        style={{
                          width: 46,
                          height: 46,
                          borderRadius: 12,
                          background: bg,
                          boxShadow: "inset 0 0 0 1px rgba(0,0,0,.08)",
                          opacity: j === 3 ? tw(frame, WAYS.minimize + 26, WAYS.minimize + 34) : 1,
                          scale: j === 3 ? String(0.6 + 0.4 * pop(frame, WAYS.minimize + 26)) : undefined,
                        }}
                      />
                    ))}
                  </div>
                </Glass>
              ) : null}
              <div
                style={{
                  position: "absolute",
                  left: g.label.left,
                  width: g.label.width,
                  top: g.label.top,
                  textAlign: g.label.align,
                  fontFamily: FONT,
                }}
              >
                <Rise at={WAYS.cards[i] + 20}>
                  <div style={{ fontSize: 50, fontWeight: 650, color: i === 2 && focus > 0 ? C.accent : C.ink }}>
                    {labels[i][0]} <span style={{ fontSize: 30, fontWeight: 500, color: C.faint }}>{labels[i][1]}</span>
                  </div>
                </Rise>
                <Rise at={[WAYS.close + 22, WAYS.minimize + 36, WAYS.shade + 42][i]}>
                  <div style={{ fontSize: 34, fontWeight: 500, color: C.muted, marginTop: 8 }}>
                    {labels[i][2]} · <span style={{ color: C.faint }}>{labels[i][3]}</span>
                  </div>
                </Rise>
              </div>
            </div>
          );
        })}
      </AbsoluteFill>
    </Canvas>
  );
};
