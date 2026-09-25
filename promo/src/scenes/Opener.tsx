import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { OPENER } from "../timeline";
import { C, FONT, easeInOut, easeOut, mix, tw } from "../theme";
import { Canvas, Lamps, Lines, MacWindow, Rise, TypedText, tiltIn } from "../ui";

// Windows pile up until the words are buried; then black, and the one line that matters.
// The caret closes into a dot, stretches into a bar, and the bar opens onto the next scene.

const PILE = [
  { title: "参考资料", x: 120, y: 120, w: 620, h: 420, from: { x: -500, ry: -30 } },
  { title: "邮件", x: 1180, y: 90, w: 620, h: 440, from: { x: 500, ry: 30 } },
  { title: "文章草稿", x: 520, y: 520, w: 700, h: 460, from: { y: 500 } },
  { title: "日历", x: 1300, y: 560, w: 520, h: 420, from: { x: 400, y: 300 } },
  { title: "会议记录", x: 60, y: 600, w: 560, h: 380, from: { x: -400, y: 300 } },
  { title: "预览", x: 760, y: 60, w: 520, h: 360, from: { y: -400, rx: -30 } },
  { title: "访达", x: 330, y: 330, w: 600, h: 400, from: { x: -300, y: -200 } },
  { title: "备忘录", x: 1000, y: 330, w: 560, h: 420, from: { x: 300, y: -200 } },
  { title: "音乐", x: 640, y: 380, w: 640, h: 420, from: { y: 400 } },
];

const tints = [C.blueSoft, "#fff", "#fff", "#fdf6ee", "#fff", "#f4f1fb", "#fff", "#fffbe8", "#fff"];

export const Opener: React.FC = () => {
  const frame = useCurrentFrame();
  const black = frame >= OPENER.black;
  const zoom = mix(1, 1.07, tw(frame, 40, OPENER.black, 0, 1, easeInOut));

  if (!black) {
    return (
      <Canvas>
        <AbsoluteFill style={{ scale: String(zoom) }}>
          {PILE.map((w, i) => {
            const at = OPENER.pile[i];
            if (frame < at) return null;
            return (
              <div key={w.title} style={{ position: "absolute", inset: 0, ...tiltIn(frame, at, w.from) }}>
                <MacWindow x={w.x} y={w.y} w={w.w} h={w.h} title={w.title} k={1.35} active={i === PILE.length - 1} body={tints[i]}>
                  <div style={{ padding: 36 }}>
                    <Lines k={1.35} widths={[70, 100, 94, 100, 58]} />
                  </div>
                </MacWindow>
              </div>
            );
          })}
        </AbsoluteFill>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", zIndex: 10 }}>
          <div
            style={{
              fontFamily: FONT,
              fontSize: 120,
              fontWeight: 700,
              letterSpacing: "-0.02em",
              color: C.ink,
              textShadow: "0 0 40px rgba(244,245,247,1), 0 0 18px rgba(244,245,247,1), 0 0 6px rgba(244,245,247,1)",
            }}
          >
            <TypedText t={OPENER.lineA} caretUntil={OPENER.lineB.at} />
            {frame >= OPENER.lineB.at ? <TypedText t={OPENER.lineB} caretColor={C.accent} /> : null}
          </div>
          <Rise at={OPENER.lineB.at + 30}>
            <div style={{ fontSize: 38, fontWeight: 500, color: C.muted, marginTop: 18, textShadow: "0 0 20px #f4f5f7, 0 0 8px #f4f5f7" }}>
              More windows, less desk.
            </div>
          </Rise>
        </AbsoluteFill>
      </Canvas>
    );
  }

  // Black half: the line, then the caret turns into the bar that opens the next scene.
  const m = OPENER.morph;
  const textOut = tw(frame, m - 10, m, 1, 0);
  const dot = tw(frame, m, m + 14, 0, 1, easeInOut); // bar → dot
  const stretch = tw(frame, m + 14, m + 34, 0, 1, easeOut); // dot → pill
  const open = tw(frame, m + 36, m + 60, 0, 1, easeInOut); // pill → screen
  const w = frame < m + 14 ? mix(8, 22, dot) : mix(22, 980, stretch);
  const h = frame < m + 14 ? mix(120, 22, dot) : mix(22, 72, stretch);
  const W = mix(w, 2400, open);
  const H = mix(h, 1400, open);
  return (
    <Canvas dark>
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity: textOut }}>
        <div style={{ fontFamily: FONT, fontSize: 132, fontWeight: 700, letterSpacing: "-0.02em", color: "#f4f5f7" }}>
          <TypedText t={OPENER.lineC} caretColor={C.accent} caretUntil={m - 10} />
        </div>
        <Rise at={OPENER.lineC.at + 48}>
          <div style={{ fontSize: 38, fontWeight: 500, color: "#9ea3ad", marginTop: 18 }}>Don’t close it yet.</div>
        </Rise>
      </AbsoluteFill>
      {frame >= m ? (
        <div
          style={{
            position: "absolute",
            left: 960 - W / 2,
            top: 540 - H / 2,
            width: W,
            height: H,
            borderRadius: (Math.min(W, H) / 2) * (1 - open),
            background: frame < m + 14 ? C.accent : open > 0 ? C.canvas : C.bar,
            display: "flex",
            alignItems: "center",
            padding: "0 26px",
            overflow: "hidden",
          }}
        >
          {/* the bar is a 卷帘条: lamps and a name, just before it opens */}
          <div style={{ display: "flex", alignItems: "center", width: "100%", position: "relative", opacity: tw(frame, m + 26, m + 34) * (1 - tw(frame, m + 36, m + 44)) }}>
            <Lamps k={1.9} />
            <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center", fontFamily: FONT, fontSize: 28, fontWeight: 600, color: C.winInk }}>
              WindowShade
            </div>
          </div>
        </div>
      ) : null}
    </Canvas>
  );
};
