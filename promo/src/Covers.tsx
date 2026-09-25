import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { C, FONT, SERIF } from "./theme";
import { Glass, Lines, MacWindow } from "./ui";

// Covers for the video pages. One idea each: double-click, and the window rolls into a bar.
// Built from the same parts as the film so the thumbnail and the video look like one thing.
// Keep the bottom-right corner clear: players print the duration there.

const K = 1.6;
const BAR = 36 * K;

/** Cursor and click rings frozen at the moment of the second click. */
const Clicked: React.FC<{ x: number; y: number; size?: number }> = ({ x, y, size = 56 }) => (
  <>
    {[0.55, 1].map((s, i) => (
      <div
        key={i}
        style={{
          position: "absolute",
          left: x - 50 * s,
          top: y - 50 * s,
          width: 100 * s,
          height: 100 * s,
          borderRadius: "50%",
          border: `${i ? 3 : 4}px solid ${C.accent}`,
          opacity: i ? 0.35 : 0.7,
        }}
      />
    ))}
    <svg
      width={size}
      height={size * 1.45}
      viewBox="0 0 20 29"
      style={{ position: "absolute", left: x - size * 0.12, top: y - size * 0.08, filter: "drop-shadow(0 4px 6px rgba(0,0,0,.3))" }}
    >
      <path d="M1.5 1.5 L1.5 22.5 L6.6 17.7 L10.2 26 L13.6 24.5 L10.1 16.5 L17.2 16.5 Z" fill="#000" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  </>
);

/** A window caught half way up: its body rolling into the title bar over the draft behind. */
const Rolling: React.FC<{ x: number; y: number; w: number; h: number; draft: { x: number; y: number; w: number; h: number } }> = ({ x, y, w, h, draft }) => (
  <>
    <MacWindow {...draft} title="文章草稿" k={K} active={false}>
      <div style={{ padding: "54px 60px", color: C.winInk }}>
        <div style={{ fontSize: 26, fontWeight: 600, color: C.winMuted }}>一个小动作的历史</div>
        <div style={{ fontFamily: SERIF, fontSize: 80, lineHeight: 1.15, margin: "18px 0 30px" }}>
          先让开，
          <br />
          待会儿回来。
        </div>
        <Lines k={K} widths={[100, 92, 96, 60]} />
      </div>
    </MacWindow>
    <MacWindow x={x} y={y} w={w} h={h} title="参考资料" k={K} roll={0.58} body={C.blueSoft}>
      <div style={{ padding: "48px 56px", color: C.blueText }}>
        <div style={{ fontSize: 26, fontWeight: 600, color: C.accent }}>手册摘录 · 1994</div>
        <div style={{ fontFamily: SERIF, fontSize: 68, lineHeight: 1.18, margin: "16px 0 26px" }}>System 7.5 手册</div>
        <Lines k={K} widths={[100, 90, 74]} color="rgba(33,72,132,.12)" />
      </div>
    </MacWindow>
    <Clicked x={x + w / 2 + 80} y={y + BAR / 2} />
  </>
);

const Wall: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ background: C.wall, fontFamily: FONT, overflow: "hidden" }}>{children}</AbsoluteFill>
);

const Brand: React.FC<{ text: string; size?: number }> = ({ text, size = 34 }) => (
  <div style={{ display: "flex", alignItems: "center", gap: size * 0.45 }}>
    <Img src={staticFile("icon.png")} style={{ width: size * 1.9, height: size * 1.9 }} />
    <div style={{ fontSize: size, fontWeight: 650, color: C.ink }}>{text}</div>
  </div>
);

/** 16:9 cover for Bilibili (and YouTube with `en`). */
export const CoverWide: React.FC<{ en?: boolean }> = ({ en }) => (
  <Wall>
    <div style={{ position: "absolute", left: 110, top: 170, width: 900 }}>
      <Brand text={en ? "WindowShade · free & open source" : "WindowShade · 免费开源"} />
      <div style={{ fontSize: en ? 148 : 176, fontWeight: 800, letterSpacing: "-0.03em", lineHeight: 1.04, marginTop: 44 }}>
        <div style={{ color: C.accent }}>{en ? "Double-click." : "双击，"}</div>
        <div style={{ color: C.ink }}>{en ? "Roll it up." : "收成一条。"}</div>
      </div>
      <div style={{ fontSize: 50, fontWeight: 600, color: C.muted, marginTop: 36 }}>
        {en ? "A 1994 Mac feature, back on your Mac." : "1994 年的 Mac 老功能，回来了"}
      </div>
    </div>
    <div style={{ position: "absolute", inset: 0, transform: "perspective(2200px) rotateY(-10deg) rotateX(4deg)", transformOrigin: "80% 40%" }}>
      <Rolling x={1030} y={210} w={800} h={540} draft={{ x: 1180, y: 300, w: 820, h: 620 }} />
    </div>
  </Wall>
);

/** 3:4 cover for Xiaohongshu. */
export const CoverTall: React.FC = () => (
  <Wall>
    <div style={{ position: "absolute", left: 80, right: 80, top: 110 }}>
      <Brand text="WindowShade · 免费开源" size={32} />
      <div style={{ fontSize: 118, fontWeight: 800, letterSpacing: "-0.03em", lineHeight: 1.1, marginTop: 40 }}>
        <div style={{ color: C.ink }}>Mac 窗口太多？</div>
        <div style={{ color: C.accent }}>双击，收成一条</div>
      </div>
    </div>
    <div style={{ position: "absolute", inset: 0, transform: "perspective(2200px) rotateX(8deg)", transformOrigin: "50% 60%" }}>
      <Rolling x={80} y={560} w={860} h={560} draft={{ x: 160, y: 680, w: 860, h: 600 }} />
    </div>
    <Glass radius={40} tint="rgba(255,255,255,.45)" style={{ left: 80, bottom: 70, height: 80, padding: "0 34px", display: "flex", alignItems: "center" }}>
      <div style={{ position: "relative", fontSize: 34, fontWeight: 600, color: C.ink, whiteSpace: "nowrap" }}>1994 年的老功能 · macOS 14 以上可用</div>
    </Glass>
  </Wall>
);
