import React from "react";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { HISTORY } from "../timeline";
import { C, FONT, MONO, easeInOut, easeOut, mix, tw } from "../theme";
import { Caption, Canvas, Lamps, useVertical } from "../ui";

// Thirty years of the same bar. Each era's title bar lands on a beat; 2001 is the gap.

const chicago = `@font-face{font-family:EraChicago;src:url(${staticFile("ChicagoFLF.woff2")}) format('woff2')}`;
const BAR_W = 820;
const BAR_H = 64;
const X = 600;
const ROW_Y = [330, 450, 570, 690];
// 9:16: year above the bar, note below it, one era per block.
const ROW_Y_V = [500, 800, 1100, 1400];
const XV = (1080 - BAR_W) / 2;

const Classic: React.FC = () => (
  <div
    style={{ width: BAR_W, height: BAR_H, background: "#fff", border: "3px solid #000", position: "relative", display: "flex", alignItems: "center" }}
  >
    <div style={{ position: "absolute", inset: "10px 8px", background: "repeating-linear-gradient(#000 0 3px, transparent 3px 7px)" }} />
    <div
      style={{
        position: "absolute",
        left: 28,
        top: 16,
        width: 26,
        height: 26,
        background: "#fff",
        border: "3px solid #000",
        outline: "6px solid #fff",
      }}
    />
    <div
      style={{
        position: "relative",
        margin: "0 auto",
        padding: "0 18px",
        background: "#fff",
        fontFamily: "EraChicago, Chicago, sans-serif",
        fontSize: 30,
        color: "#000",
      }}
    >
      WindowShade
    </div>
  </div>
);

const Platinum: React.FC = () => (
  <div
    style={{
      width: BAR_W,
      height: BAR_H,
      background: "#dcdcdc",
      boxShadow: "inset 2px 2px 0 #fff, inset -2px -2px 0 #9a9a9a, 0 0 0 2px #444",
      position: "relative",
      display: "flex",
      alignItems: "center",
    }}
  >
    <div style={{ position: "absolute", inset: "14px 10px", background: "repeating-linear-gradient(#b8b8b8 0 2px, #f4f4f4 2px 5px)" }} />
    {[26, BAR_W - 112, BAR_W - 62].map((l, i) => (
      <div
        key={i}
        style={{
          position: "absolute",
          left: l,
          top: 17,
          width: 30,
          height: 30,
          background: "linear-gradient(135deg,#fff,#c4c4c4)",
          boxShadow: "inset 0 0 0 2px #555, 0 0 0 5px #dcdcdc",
        }}
      >
        {i === 2 ? <div style={{ position: "absolute", left: 5, right: 5, top: 12, height: 4, background: "#555" }} /> : null}
      </div>
    ))}
    <div
      style={{
        position: "relative",
        margin: "0 auto",
        padding: "0 18px",
        background: "#dcdcdc",
        fontFamily: "EraChicago, Charcoal, sans-serif",
        fontSize: 28,
        color: "#111",
      }}
    >
      WindowShade
    </div>
  </div>
);

const Aqua: React.FC = () => (
  <div
    style={{
      width: BAR_W,
      height: BAR_H,
      borderRadius: "14px 14px 0 0",
      background: "repeating-linear-gradient(#f2f2f2 0 2px, #e2e2e2 2px 4px)",
      boxShadow: "inset 0 1px 0 #fff, 0 0 0 1.5px #8d8d8d",
      display: "flex",
      alignItems: "center",
      padding: "0 20px",
      position: "relative",
    }}
  >
    <div style={{ display: "flex", gap: 12 }}>
      {["#ff5f4f", "#ffbd2e", "#35c848"].map((c) => (
        <div
          key={c}
          style={{
            width: 28,
            height: 28,
            borderRadius: "50%",
            background: `radial-gradient(circle at 50% 30%, #fff 0 12%, ${c} 45%, #7a2d1f 130%)`,
            boxShadow: "inset 0 0 0 1px rgba(0,0,0,.35)",
          }}
        />
      ))}
    </div>
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        textAlign: "center",
        fontFamily: '"Lucida Grande", "Helvetica Neue", sans-serif',
        fontSize: 27,
        color: "#222",
      }}
    >
      Untitled
    </div>
  </div>
);

const Today: React.FC = () => (
  <div
    style={{
      width: BAR_W,
      height: BAR_H,
      borderRadius: 32,
      background: C.bar,
      display: "flex",
      alignItems: "center",
      padding: "0 24px",
      position: "relative",
      boxShadow: `0 0 0 1px rgba(255,255,255,.4), 0 0 60px rgba(36,94,234,.55), 0 0 0 4px rgba(36,94,234,.5)`,
    }}
  >
    <Lamps k={1.9} />
    <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center", fontFamily: FONT, fontSize: 27, fontWeight: 600, color: C.winInk }}>
      WindowShade
    </div>
  </div>
);

const ROWS = [
  { year: "1994", bar: <Classic />, zh: "System 7.5 自带", en: "Built into System 7.5" },
  { year: "1997", bar: <Platinum />, zh: "Mac OS 8 加了按钮", en: "Mac OS 8 adds a button" },
  { year: "2001", bar: <Aqua />, zh: "Mac OS X 里没有了", en: "Gone in Mac OS X" },
  { year: "2026", bar: <Today />, zh: "WindowShade 带回来", en: "WindowShade brings it back" },
];

export const History: React.FC = () => {
  const frame = useCurrentFrame();
  const v = useVertical();
  const focus = tw(frame, HISTORY.focus, HISTORY.focus + 70, 0, 1, easeInOut);
  return (
    <Canvas dark>
      <style>{chicago}</style>
      <Caption dark zh="这个双击，比你的 Mac 还老。" en="This double-click is older than your Mac." at={2} />
      <AbsoluteFill
        style={{
          scale: String(mix(1, 1.18, focus)),
          transformOrigin: v ? `540px ${ROW_Y_V[3] + 70 + BAR_H / 2}px` : `${X + BAR_W / 2}px ${ROW_Y[3] + BAR_H / 2}px`,
          translate: `0 ${mix(0, -60, focus)}px`,
        }}
      >
        {ROWS.map((r, i) => {
          const at = HISTORY.rows[i];
          const p = tw(frame, at, at + 22, 0, 1, easeOut);
          const gone = i === 2;
          const dim = i < 3 ? mix(1, 0.3, focus) : 1;
          return (
            <div
              key={r.year}
              style={{
                position: "absolute",
                left: 0,
                right: 0,
                top: v ? ROW_Y_V[i] : ROW_Y[i],
                height: BAR_H,
                opacity: p * dim * (gone ? mix(1, 0.55, tw(frame, at + 24, at + 40)) : 1),
                translate: `${(1 - p) * -80}px 0`,
                filter: `blur(${(1 - p) * 8}px)`,
              }}
            >
              <div
                style={{
                  position: "absolute",
                  left: v ? XV : 300,
                  width: 250,
                  top: v ? 0 : 6,
                  fontFamily: MONO,
                  fontSize: 50,
                  fontWeight: 600,
                  color: i === 3 ? "#7ea4ff" : "#f4f5f7",
                  textAlign: v ? "left" : "right",
                }}
              >
                {r.year}
              </div>
              <div style={{ position: "absolute", left: v ? XV : X, top: v ? 70 : 0 }}>{r.bar}</div>
              <div style={{ position: "absolute", left: v ? XV : X + BAR_W + 40, top: v ? 150 : -2, fontFamily: FONT, whiteSpace: "nowrap" }}>
                <div style={{ fontSize: 32, fontWeight: 600, color: i === 3 ? "#7ea4ff" : "#f4f5f7" }}>{r.zh}</div>
                <div style={{ fontSize: 22, color: "#8b9099", marginTop: 4 }}>{r.en}</div>
              </div>
            </div>
          );
        })}
      </AbsoluteFill>
    </Canvas>
  );
};
