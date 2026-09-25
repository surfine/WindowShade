import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { END } from "../timeline";
import { C, FONT, easeOut, pop, tw } from "../theme";
import { Canvas, Glass, Rise } from "../ui";

// Icon, name, the one line, where to get it.

export const End: React.FC = () => {
  const frame = useCurrentFrame();
  const icon = pop(frame, END.icon, 11, 120);
  const glow = tw(frame, END.cta, END.cta + 40, 0, 1, easeOut);
  const cta = pop(frame, END.cta, 14, 180);
  const fade = 1 - tw(frame, 330, 360);
  return (
    <Canvas>
      <AbsoluteFill style={{ opacity: fade }}>
        {/* soft wallpaper light for the glass to catch */}
        <div
          style={{
            position: "absolute",
            left: 460,
            top: 700,
            width: 1000,
            height: 320,
            borderRadius: "50%",
            background: "radial-gradient(closest-side, rgba(201,219,255,.9), rgba(241,217,238,.6) 55%, rgba(255,227,201,0) 100%)",
            filter: "blur(30px)",
            opacity: glow,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 960 - 110,
            top: 150,
            width: 220,
            height: 220,
            translate: `0 ${(1 - icon) * -260}px`,
            rotate: `${(1 - icon) * -18}deg`,
            filter: "drop-shadow(0 24px 34px rgba(20,28,48,.22))",
          }}
        >
          <Img src={staticFile("icon.png")} style={{ width: 220, height: 220 }} />
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 400, textAlign: "center", fontFamily: FONT }}>
          <Rise at={END.word}>
            <div style={{ fontSize: 118, fontWeight: 700, letterSpacing: "-0.03em", color: C.ink }}>WindowShade</div>
          </Rise>
          <Rise at={END.tagline}>
            <div style={{ fontSize: 60, fontWeight: 600, color: C.ink, marginTop: 6 }}>收起窗口，留下位置。</div>
          </Rise>
          <Rise at={END.tagline + 8}>
            <div style={{ fontSize: 32, color: C.muted, marginTop: 10 }}>Roll it up. Keep its place.</div>
          </Rise>
        </div>
        <Glass
          radius={44}
          tint="rgba(255,255,255,.4)"
          style={{
            left: 960 - 290,
            top: 800,
            width: 580,
            height: 88,
            opacity: Math.min(1, cta * 1.3),
            scale: String(0.85 + 0.15 * cta),
            boxShadow:
              "inset 0 1.5px 1px rgba(255,255,255,.95), inset 0 -1px 1px rgba(255,255,255,.4), 0 0 50px rgba(36,94,234,.28), 0 18px 44px rgba(20,28,48,.18)",
          }}
        >
          <div style={{ position: "relative", height: 88, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: FONT, fontSize: 40, fontWeight: 600, color: C.accent }}>
            windowshade.pages.dev
          </div>
        </Glass>
        <div style={{ position: "absolute", left: 0, right: 0, top: 924, textAlign: "center", fontFamily: FONT }}>
          <Rise at={END.facts}>
            <div style={{ fontSize: 28, color: C.muted }}>免费开源 · macOS 14 及以上 · Apple Silicon</div>
          </Rise>
        </div>
      </AbsoluteFill>
    </Canvas>
  );
};
