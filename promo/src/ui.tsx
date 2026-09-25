import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { C, FONT, MONO, easeOut, pop, tw } from "./theme";
import { Typed } from "./timeline";

// ---------------------------------------------------------------------------
// A macOS window, measured like the website's: 14 pt lamps on a 23 pt pitch, a 36 pt bar,
// ~18 pt corners. `k` is pixels per point. `roll` 0 → 1 takes the body up into the bar,
// the way WindowShade does it; at 1 what's left is the 卷帘条.
// ---------------------------------------------------------------------------

export type WinProps = {
  x: number;
  y: number;
  w: number;
  h: number;
  title: string;
  k?: number;
  roll?: number;
  active?: boolean;
  body?: string;
  opacity?: number;
  style?: React.CSSProperties;
  children?: React.ReactNode;
  lamps?: "color" | "gray";
};

export const Lamps: React.FC<{ k: number; gray?: boolean }> = ({ k, gray }) => {
  const colors = [
    ["#ec6a5e", "#c9463c"],
    ["#f4bf4f", "#c9952c"],
    ["#61c554", "#3f9a36"],
  ];
  return (
    <div style={{ display: "flex", gap: 9 * k, flex: "none" }}>
      {colors.map(([c, rim], i) => (
        <div
          key={i}
          style={{
            width: 14 * k,
            height: 14 * k,
            borderRadius: "50%",
            background: gray ? "linear-gradient(#e3e3e7,#ecedf0 70%,#e2e2e5)" : c,
            boxShadow: `inset 0 0 0 ${0.5 * k}px ${gray ? "#b4b5b9" : rim}`,
          }}
        />
      ))}
    </div>
  );
};

export const MacWindow: React.FC<WinProps> = ({
  x,
  y,
  w,
  h,
  title,
  k = 1.8,
  roll = 0,
  active = true,
  body = C.win,
  opacity = 1,
  style,
  children,
  lamps,
}) => {
  const bar = 36 * k;
  const radius = 18 * k;
  const bodyH = h - bar;
  const shown = bodyH * (1 - roll);
  const barRound = interpolate(roll, [0.93, 1], [0, radius], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const rolling = roll > 0.01 && roll < 0.995;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        height: bar + shown,
        borderRadius: `${radius}px ${radius}px ${roll > 0.93 ? barRound : radius}px ${roll > 0.93 ? barRound : radius}px`,
        overflow: "hidden",
        opacity,
        boxShadow: active
          ? `0 0 0 ${0.6}px rgba(0,0,0,.28), 0 ${10 * k}px ${34 * k}px rgba(22,28,45,.26), 0 ${2 * k}px ${6 * k}px rgba(22,28,45,.08)`
          : `0 0 0 ${0.6}px rgba(0,0,0,.2), 0 ${4 * k}px ${14 * k}px rgba(22,28,45,.16)`,
        background: body,
        ...style,
      }}
    >
      <div
        style={{
          position: "relative",
          height: bar,
          display: "flex",
          alignItems: "center",
          padding: `0 ${13 * k}px`,
          background: C.bar,
          boxShadow: roll > 0.97 ? "none" : `inset 0 -0.6px 0 ${C.line}`,
          fontFamily: FONT,
          fontSize: 13.5 * k,
          fontWeight: 600,
          color: active ? C.winInk : C.winMuted,
          zIndex: 2,
        }}
      >
        <Lamps k={k} gray={lamps ? lamps === "gray" : !active} />
        <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center", pointerEvents: "none", whiteSpace: "nowrap" }}>
          {title}
        </div>
      </div>
      <div style={{ position: "relative", height: bodyH, overflow: "hidden" }}>
        {children}
        {rolling ? (
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: shown - 16 * k,
              height: 16 * k,
              background:
                "linear-gradient(to bottom, rgba(0,0,0,0), rgba(0,0,0,.07) 35%, rgba(255,255,255,.85) 62%, rgba(0,0,0,.14) 100%)",
            }}
          />
        ) : null}
      </div>
    </div>
  );
};

/** Placeholder text lines, like the site's illustrations. */
export const Lines: React.FC<{ k: number; widths?: number[]; color?: string; gap?: number }> = ({
  k,
  widths = [100, 92, 96, 64],
  color = "rgba(0,0,0,.07)",
  gap = 12,
}) => (
  <div style={{ display: "grid", gap: gap * k }}>
    {widths.map((w, i) => (
      <div key={i} style={{ width: `${w}%`, height: 7 * k, borderRadius: 99, background: color }} />
    ))}
  </div>
);

// ---------------------------------------------------------------------------
// Pointer and clicks
// ---------------------------------------------------------------------------

export const Cursor: React.FC<{ x: number; y: number; size?: number; opacity?: number; press?: number }> = ({
  x,
  y,
  size = 46,
  opacity = 1,
  press = 0,
}) => (
  <svg
    width={size}
    height={size * 1.45}
    viewBox="0 0 20 29"
    style={{
      position: "absolute",
      left: x - size * 0.12,
      top: y - size * 0.08,
      opacity,
      scale: String(1 - press * 0.12),
      transformOrigin: "12% 6%",
      filter: "drop-shadow(0 3px 5px rgba(0,0,0,.28))",
      zIndex: 50,
    }}
  >
    <path d="M1.5 1.5 L1.5 22.5 L6.6 17.7 L10.2 26 L13.6 24.5 L10.1 16.5 L17.2 16.5 Z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

export const Clicks: React.FC<{ x: number; y: number; at: number[] }> = ({ x, y, at }) => {
  const frame = useCurrentFrame();
  return (
    <>
      {at.map((f, i) => {
        const t = tw(frame, f, f + 22, 0, 1);
        if (frame < f || t >= 1) return null;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x - 40,
              top: y - 40,
              width: 80,
              height: 80,
              borderRadius: "50%",
              border: `3px solid ${C.accent}`,
              opacity: 0.55 * (1 - t),
              scale: String(0.3 + t * 0.9),
              zIndex: 49,
            }}
          />
        );
      })}
    </>
  );
};

/** Pointer press amount for a click at frame f. */
export const pressAt = (frame: number, clicks: number[]) =>
  Math.max(0, ...clicks.map((f) => (frame >= f - 2 && frame < f + 5 ? 1 : 0)));

// ---------------------------------------------------------------------------
// Liquid Glass: thick, bright-rimmed, blurring and lifting what's behind it.
// ---------------------------------------------------------------------------

export const Glass: React.FC<{
  style?: React.CSSProperties;
  radius: number;
  tint?: string;
  children?: React.ReactNode;
  rim?: number;
  blur?: number;
}> = ({ style, radius, tint = "rgba(255,255,255,.28)", children, rim = 1.6, blur = 16 }) => (
  <div
    style={{
      position: "absolute",
      borderRadius: radius,
      background: `linear-gradient(160deg, rgba(255,255,255,.34), rgba(255,255,255,.08) 55%, rgba(255,255,255,.2)), ${tint}`,
      backdropFilter: `blur(${blur}px) saturate(190%) brightness(1.06)`,
      WebkitBackdropFilter: `blur(${blur}px) saturate(190%) brightness(1.06)`,
      boxShadow:
        "inset 0 1.5px 1px rgba(255,255,255,.95), inset 0 -1px 1px rgba(255,255,255,.4), inset 0 0 18px rgba(255,255,255,.28), 0 18px 44px rgba(20,28,48,.2), 0 3px 8px rgba(20,28,48,.08)",
      ...style,
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: radius,
        padding: rim,
        background:
          "linear-gradient(135deg, rgba(255,255,255,1), rgba(255,255,255,.15) 32%, rgba(255,255,255,0) 50%, rgba(255,255,255,.2) 70%, rgba(255,255,255,.9))",
        WebkitMask: "linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)",
        WebkitMaskComposite: "xor",
        maskComposite: "exclude",
        pointerEvents: "none",
      }}
    />
    {children}
  </div>
);

// ---------------------------------------------------------------------------
// The gesture HUD, the app's own: a 290 × 63 pt capsule under the title bar that says what
// letting go will do. The track fills white; full, it turns blue and gives a small pop.
// ---------------------------------------------------------------------------

export const Hud: React.FC<{
  cx: number;
  top: number;
  k: number;
  title: string;
  progress: number;
  opacity: number;
  armedAt?: number;
}> = ({ cx, top, k, title, progress, opacity, armedAt }) => {
  const frame = useCurrentFrame();
  const armed = progress >= 1;
  const bump = armedAt !== undefined && frame >= armedAt ? Math.sin(Math.min(1, (frame - armedAt) / 12) * Math.PI) * 0.045 : 0;
  const w = 290 * k;
  const h = 63 * k;
  const glyph = (dim: boolean) => (
    <div
      style={{
        position: "relative",
        width: 17 * k,
        height: 14 * k,
        borderRadius: 3 * k,
        boxShadow: `inset 0 0 0 ${1.3 * k}px ${dim ? "rgba(255,255,255,.5)" : "#fff"}`,
        overflow: "hidden",
        flex: "none",
      }}
    >
      <div style={{ height: 4.5 * k, background: dim ? "rgba(255,255,255,.5)" : "#fff" }} />
    </div>
  );
  return (
    <Glass
      radius={24 * k}
      tint="rgba(96,102,114,.6)"
      blur={34}
      style={{
        left: cx - w / 2,
        top,
        width: w,
        height: h,
        opacity,
        scale: String((0.94 + 0.06 * Math.min(1, opacity)) * (1 + bump)),
        zIndex: 40,
      }}
    >
      <div style={{ position: "relative", padding: `${10 * k}px ${16 * k}px 0`, display: "grid", gap: 7 * k }}>
        <div style={{ fontFamily: FONT, fontSize: 13 * k, fontWeight: 600, color: "rgba(255,255,255,.96)", textShadow: "0 1px 2px rgba(0,0,0,.18)" }}>{title}</div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 * k }}>
          {glyph(false)}
          <div style={{ flex: 1, height: 4 * k, borderRadius: 99, background: "rgba(0,0,0,.2)", overflow: "hidden" }}>
            <div
              style={{
                width: `${Math.min(1, progress) * 100}%`,
                height: "100%",
                borderRadius: 99,
                background: armed ? C.accent : "#fff",
                boxShadow: "0 0 0 .5px rgba(22,24,28,.18)",
              }}
            />
          </div>
          {glyph(true)}
        </div>
      </div>
    </Glass>
  );
};

// ---------------------------------------------------------------------------
// Trackpad with two fingertips, and a mouse with a wheel
// ---------------------------------------------------------------------------

export const Trackpad: React.FC<{
  x: number;
  y: number;
  w: number;
  fingers: { x: number; y: number; on: number; spread?: number };
  opacity?: number;
  style?: React.CSSProperties;
}> = ({ x, y, w, fingers, opacity = 1, style }) => {
  const h = w * 0.66;
  const d = w * 0.13;
  const gap = (fingers.spread ?? 1) * w * 0.14;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        height: h,
        borderRadius: w * 0.055,
        background: "linear-gradient(170deg,#eceef2,#d9dce2 60%,#cfd3da)",
        boxShadow:
          "inset 0 0 0 1.5px rgba(255,255,255,.9), inset 0 -2px 3px rgba(0,0,0,.05), 0 0 0 1px rgba(0,0,0,.08), 0 24px 50px rgba(20,28,48,.18), 0 3px 8px rgba(20,28,48,.08)",
        opacity,
        ...style,
      }}
    >
      {[-1, 1].map((s) => (
        <div
          key={s}
          style={{
            position: "absolute",
            left: fingers.x * w + s * gap * 0.5 - d / 2,
            top: fingers.y * h - d / 2 + (s > 0 ? -d * 0.18 : 0),
            width: d,
            height: d,
            borderRadius: "50%",
            background: "radial-gradient(circle at 45% 40%, rgba(255,255,255,.9), rgba(36,94,234,.45) 75%)",
            boxShadow: `0 0 0 3px rgba(36,94,234,.75), 0 8px 22px rgba(36,94,234,.35)`,
            opacity: fingers.on,
            scale: String(0.7 + 0.3 * fingers.on),
          }}
        />
      ))}
    </div>
  );
};

export const Mouse: React.FC<{ x: number; y: number; w: number; wheel: number; glow: number; opacity?: number }> = ({
  x,
  y,
  w,
  wheel,
  glow,
  opacity = 1,
}) => {
  const h = w * 1.62;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        height: h,
        borderRadius: `${w * 0.5}px ${w * 0.5}px ${w * 0.46}px ${w * 0.46}px`,
        background: "linear-gradient(170deg,#fafafb,#e6e8ec)",
        boxShadow: "inset 0 0 0 1.5px rgba(255,255,255,.9), 0 0 0 1px rgba(0,0,0,.08), 0 24px 50px rgba(20,28,48,.18)",
        opacity,
      }}
    >
      <div style={{ position: "absolute", left: w / 2 - 0.5, top: 0, width: 1, height: h * 0.36, background: "rgba(0,0,0,.1)" }} />
      <div
        style={{
          position: "absolute",
          left: w / 2 - w * 0.07,
          top: h * 0.12,
          width: w * 0.14,
          height: h * 0.2,
          borderRadius: 99,
          background: "#2b2e34",
          overflow: "hidden",
          boxShadow: `0 0 0 ${3 + glow * 5}px rgba(36,94,234,${0.35 * glow})`,
        }}
      >
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              height: 2,
              top: `${((i * 20 + wheel * 20) % 120) - 10}%`,
              background: "rgba(255,255,255,.35)",
            }}
          />
        ))}
      </div>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/** Typed text with a caret. The caret keeps blinking on the beat once the line is done. */
export const TypedText: React.FC<{
  t: Typed;
  style?: React.CSSProperties;
  caretUntil?: number;
  caretColor?: string;
}> = ({ t, style, caretUntil = Infinity, caretColor }) => {
  const frame = useCurrentFrame();
  const chars = [...t.text];
  const rate = t.rate ?? 4;
  const n = Math.max(0, Math.min(chars.length, Math.floor((frame - t.at) / rate) + 1));
  const typing = frame >= t.at && n < chars.length;
  const caretOn = frame < caretUntil && (typing || (frame >= t.at - 20 && Math.floor(frame / 15) % 2 === 0));
  return (
    <span style={{ whiteSpace: "pre", ...style }}>
      {chars.slice(0, frame >= t.at ? n : 0).join("")}
      <span
        style={{
          display: "inline-block",
          width: "0.06em",
          height: "1.05em",
          marginLeft: "0.06em",
          verticalAlign: "-0.14em",
          background: caretColor ?? "currentColor",
          opacity: caretOn ? 1 : 0,
          borderRadius: 2,
        }}
      />
    </span>
  );
};

/** A line that rises out of a mask and settles, then leaves upward at `out`. */
export const Rise: React.FC<{
  at: number;
  out?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
  distance?: number;
}> = ({ at, out = Infinity, children, style, distance = 1.1 }) => {
  const frame = useCurrentFrame();
  const inT = tw(frame, at, at + 26, 0, 1, easeOut);
  const outT = Number.isFinite(out) ? tw(frame, out, out + 18, 0, 1, easeOut) : 0;
  if (frame < at || outT >= 1) return null;
  return (
    <div style={{ overflow: "hidden", paddingBottom: "0.12em", ...style }}>
      <div
        style={{
          translate: `0 ${(1 - inT) * distance * 100 - outT * 100}%`,
          filter: `blur(${(1 - inT) * 10 + outT * 8}px)`,
          opacity: Math.min(1, inT * 1.4) * (1 - outT),
        }}
      >
        {children}
      </div>
    </div>
  );
};

/** Headline with an English line under it. Centered at the top of the frame. */
export const Caption: React.FC<{
  zh: string;
  en: string;
  at: number;
  out?: number;
  top?: number;
  dark?: boolean;
  size?: number;
}> = ({ zh, en, at, out, top = 88, dark, size = 76 }) => (
  <div style={{ position: "absolute", left: 0, right: 0, top, textAlign: "center", zIndex: 60 }}>
    <Rise at={at} out={out}>
      <div
        style={{
          fontFamily: FONT,
          fontSize: size,
          fontWeight: 650,
          letterSpacing: "-0.01em",
          color: dark ? "#f4f5f7" : C.ink,
          lineHeight: 1.15,
        }}
      >
        {zh}
      </div>
    </Rise>
    <Rise at={at + 6} out={out}>
      <div style={{ fontFamily: FONT, fontSize: 34, fontWeight: 500, color: dark ? "#9ea3ad" : C.muted, marginTop: 12 }}>{en}</div>
    </Rise>
  </div>
);

export const Canvas: React.FC<{ children?: React.ReactNode; dark?: boolean }> = ({ children, dark }) => (
  <AbsoluteFill
    style={{
      background: dark ? C.black : C.canvas,
      backgroundImage: dark
        ? "radial-gradient(rgba(255,255,255,.06) 1.3px, transparent 1.8px)"
        : `radial-gradient(${C.dot} 1.3px, transparent 1.8px)`,
      backgroundSize: "36px 36px",
      overflow: "hidden",
      fontFamily: FONT,
    }}
  >
    {children}
  </AbsoluteFill>
);

/** Entrance: tilted in space, settling flat, the way launch films float UI in. */
export const tiltIn = (frame: number, at: number, from: { rx?: number; ry?: number; y?: number; x?: number } = {}) => {
  const p = pop(frame, at, 16, 120);
  const o = tw(frame, at, at + 10);
  return {
    opacity: o,
    transform: `perspective(1600px) translate(${(1 - p) * (from.x ?? 0)}px, ${(1 - p) * (from.y ?? 120)}px) rotateX(${(1 - p) * (from.rx ?? 24)}deg) rotateY(${(1 - p) * (from.ry ?? 0)}deg) scale(${0.9 + 0.1 * p})`,
  } as React.CSSProperties;
};

export const Keycap: React.FC<{ label: string; press: number; size?: number }> = ({ label, press, size = 64 }) => (
  <div
    style={{
      minWidth: size,
      height: size,
      padding: `0 ${size * 0.22}px`,
      borderRadius: size * 0.22,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontFamily: FONT,
      fontSize: size * 0.42,
      fontWeight: 600,
      color: press > 0.5 ? "#fff" : C.ink,
      background: press > 0.5 ? C.accent : "linear-gradient(#ffffff,#f0f1f4)",
      boxShadow: `0 ${4 - press * 3}px 0 ${press > 0.5 ? "#1a47b8" : "#cfd3da"}, 0 ${8 - press * 5}px 18px rgba(20,28,48,.14), inset 0 0 0 1px rgba(0,0,0,.06)`,
      translate: `0 ${press * 3}px`,
    }}
  >
    {label}
  </div>
);

export { MONO };
