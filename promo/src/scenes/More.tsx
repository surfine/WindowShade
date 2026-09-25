import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { MORE } from "../timeline";
import { C, FONT, easeInOut, easeOut, mix, pop, tw } from "../theme";
import { Caption, Canvas, Cursor, Glass, Keycap, Lamps, tiltIn } from "../ui";

// The rest of the app in three cards: pin, carry to every desktop, window browsing.

const XS = [390, 960, 1530];
const CW = 520;
const TOP = 300;
const ART_H = 330;

const Mini: React.FC<{ x: number; y: number; w: number; h: number; title: string; body?: string; style?: React.CSSProperties; children?: React.ReactNode }> = ({
  x,
  y,
  w,
  h,
  title,
  body = "#fff",
  style,
  children,
}) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width: w,
      height: h,
      borderRadius: 14,
      overflow: "hidden",
      background: body,
      boxShadow: "0 0 0 .6px rgba(0,0,0,.25), 0 10px 24px rgba(22,28,45,.22)",
      ...style,
    }}
  >
    <div style={{ height: 30, background: C.bar, display: "flex", alignItems: "center", padding: "0 9px", position: "relative", fontSize: 14, fontWeight: 600, color: C.winInk }}>
      <Lamps k={0.72} />
      <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center" }}>{title}</div>
    </div>
    {children}
  </div>
);

const Pin: React.FC<{ frame: number }> = ({ frame }) => {
  const k = MORE.keys[0];
  const pinned = frame >= k + 12;
  const slide = tw(frame, MORE.cards[0] + 20, MORE.cards[0] + 60, 0, 1, easeInOut) - tw(frame, k + 16, k + 50, 0, 0.35, easeInOut);
  const badge = pop(frame, k + 12, 12, 200);
  return (
    <>
      <Mini x={48} y={70} w={230} h={170} title="尺寸参考" body={C.blueSoft} style={{ zIndex: pinned ? 3 : 1, scale: String(1 + 0.04 * Math.sin(Math.PI * tw(frame, k + 12, k + 24))) }}>
        <div style={{ padding: 16, fontSize: 26, color: C.blueText, fontWeight: 600 }}>240 × 160 mm</div>
      </Mini>
      <Mini x={mix(420, 170, slide)} y={120} w={280} h={180} title="产品说明" style={{ zIndex: 2 }}>
        <div style={{ padding: 16, display: "grid", gap: 10 }}>
          {[100, 80, 90].map((w) => (
            <div key={w} style={{ width: `${w}%`, height: 8, borderRadius: 9, background: "rgba(0,0,0,.08)" }} />
          ))}
        </div>
      </Mini>
      <div
        style={{
          position: "absolute",
          left: 250,
          top: 56,
          width: 40,
          height: 40,
          borderRadius: 20,
          background: C.accent,
          color: "#fff",
          fontSize: 22,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          zIndex: 4,
          scale: String(badge),
          boxShadow: "0 6px 14px rgba(36,94,234,.4)",
        }}
      >
        <svg width="22" height="22" viewBox="0 0 24 24" fill="#fff"><path d="M15 3l6 6-3 1-4 4 1 5-2 2-4-4-5 5-1-1 5-5-4-4 2-2 5 1 4-4z" /></svg>
      </div>
    </>
  );
};

const Carry: React.FC<{ frame: number }> = ({ frame }) => {
  const k = MORE.keys[1];
  const move = tw(frame, k + 24, k + 60, 0, 1, easeInOut);
  const bar = pop(frame, k + 12, 16, 200);
  return (
    <>
      <div style={{ position: "absolute", inset: 0, display: "flex", gap: 20, translate: `${-move * (CW + 20)}px 0` }}>
        {[C.wall, "radial-gradient(120% 90% at 20% 0%,#d6f0e0 0%,transparent 60%),radial-gradient(100% 90% at 100% 100%,#dde4ff 0%,transparent 60%),#eef1f4"].map((bg, i) => (
          <div key={i} style={{ flex: "none", width: CW, height: ART_H, background: bg, position: "relative" }}>
            <div style={{ position: "absolute", left: 18, top: 16, fontSize: 18, fontWeight: 600, color: C.winMuted }}>桌面 {i + 1}</div>
            {i === 0 ? <Mini x={60} y={70} w={300} h={200} title="会议记录" body={C.blueSoft} /> : <Mini x={120} y={110} w={320} h={190} title="邮件" />}
          </div>
        ))}
      </div>
      <div
        style={{
          position: "absolute",
          right: 18,
          top: 14,
          width: 200,
          height: 30,
          borderRadius: 15,
          background: C.bar,
          display: "flex",
          alignItems: "center",
          padding: "0 9px",
          fontSize: 14,
          fontWeight: 600,
          color: C.winInk,
          boxShadow: `0 0 0 .6px rgba(0,0,0,.25), 0 6px 16px rgba(22,28,45,.2), 0 0 0 ${3 * bar}px rgba(36,94,234,.45)`,
          opacity: bar,
          scale: String(0.8 + 0.2 * bar),
          zIndex: 5,
        }}
      >
        <Lamps k={0.72} />
        <div style={{ position: "absolute", left: 0, right: 0, textAlign: "center" }}>会议记录</div>
      </div>
    </>
  );
};

const Browse: React.FC<{ frame: number }> = ({ frame }) => {
  const k = MORE.keys[2];
  const arrive = tw(frame, k - 40, k - 8, 0, 1, easeOut);
  const panel = pop(frame, k, 16, 190);
  const icons = ["#3d7bf7", "#ffffff", "#48b865", "#e85d75"];
  return (
    <>
      <div style={{ position: "absolute", inset: 0, background: C.wall }} />
      <Glass
        radius={22}
        style={{ left: 30, top: 70, width: CW - 60, height: 160, opacity: panel, scale: String(0.9 + 0.1 * panel), transformOrigin: "35% 100%" }}
      >
        <div style={{ position: "relative", display: "flex", gap: 14, padding: 16 }}>
          {["参考资料", "文章草稿", "尺寸参考"].map((t, i) => (
            <div key={t} style={{ flex: 1 }}>
              <div style={{ height: 88, borderRadius: 10, background: i === 0 ? C.blueSoft : "#fff", boxShadow: "0 0 0 .6px rgba(0,0,0,.18)" }} />
              <div style={{ fontSize: 16, fontWeight: 600, color: C.winInk, marginTop: 8, textAlign: "center" }}>{t}</div>
            </div>
          ))}
        </div>
      </Glass>
      <Glass radius={22} style={{ left: CW / 2 - 150, top: ART_H - 78, width: 300, height: 64 }}>
        <div style={{ position: "relative", display: "flex", gap: 12, padding: 9, justifyContent: "center" }}>
          {icons.map((bg, i) => (
            <div
              key={i}
              style={{
                width: 46,
                height: 46,
                borderRadius: 12,
                background: bg,
                boxShadow: "inset 0 0 0 1px rgba(0,0,0,.1)",
                scale: i === 1 ? String(1 + 0.15 * arrive) : undefined,
                translate: i === 1 ? `0 ${-6 * arrive}px` : undefined,
                fontSize: 26,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: C.accent,
                fontWeight: 700,
              }}
            >
              {i === 1 ? "A" : ""}
            </div>
          ))}
        </div>
      </Glass>
      <Cursor x={mix(CW - 40, CW / 2 - 60, arrive)} y={mix(ART_H + 30, ART_H - 40, arrive)} size={34} />
    </>
  );
};

const CARDS = [
  { zh: "置顶", en: "Pin a window", sub: "一直在最前面", keys: ["⌃", "⌘", "P"], Art: Pin },
  { zh: "带到每张桌面", en: "Carry it to every desktop", sub: "别的桌面也能看一眼", keys: ["⌃", "⌘", "G"], Art: Carry },
  { zh: "窗口浏览", en: "Window browsing", sub: "停在 Dock 图标上，看到它所有窗口", keys: [], Art: Browse },
];

export const More: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <Canvas>
      <Caption zh="老动作之外，它还帮你看住每扇窗口。" en="Beyond the old trick, it keeps track of every window." at={2} size={68} />
      <AbsoluteFill style={{ scale: String(mix(1, 1.03, tw(frame, 0, 360, 0, 1, easeInOut))) }}>
        {CARDS.map((c, i) => {
          const keyAt = MORE.keys[i];
          const lit = tw(frame, keyAt - 6, keyAt + 6) * (1 - tw(frame, keyAt + 80, keyAt + 100));
          return (
            <div key={c.zh} style={{ position: "absolute", inset: 0, ...tiltIn(frame, MORE.cards[i], { y: 200, rx: 28, ry: (i - 1) * -12 }) }}>
              <div
                style={{
                  position: "absolute",
                  left: XS[i] - CW / 2,
                  top: TOP,
                  width: CW,
                  borderRadius: 34,
                  background: "#fff",
                  overflow: "hidden",
                  boxShadow: `0 0 0 1px rgba(20,26,38,.06), 0 30px 60px rgba(20,28,48,.12), 0 0 0 ${lit * 4}px rgba(36,94,234,.5)`,
                }}
              >
                <div style={{ position: "relative", height: ART_H, overflow: "hidden", background: "#eef0f4" }}>
                  <c.Art frame={frame} />
                </div>
                <div style={{ padding: "26px 32px 30px", fontFamily: FONT }}>
                  <div style={{ fontSize: 44, fontWeight: 650, color: C.ink }}>
                    {c.zh}
                    <div style={{ fontSize: 24, fontWeight: 500, color: C.faint, marginTop: 2 }}>{c.en}</div>
                  </div>
                  <div style={{ fontSize: 26, color: C.muted, marginTop: 8 }}>{c.sub}</div>
                  <div style={{ display: "flex", gap: 10, marginTop: 22, height: 58, alignItems: "center" }}>
                    {c.keys.map((key, j) => {
                      const d = keyAt + j * 6;
                      const press = tw(frame, d, d + 2) * (1 - tw(frame, d + 30 - j * 6, d + 36 - j * 6));
                      return <Keycap key={j} label={key} press={press} size={56} />;
                    })}
                    {c.keys.length === 0 ? (
                      <div style={{ fontSize: 24, color: C.faint }}>快捷键可以自己设 · or your own shortcut</div>
                    ) : null}
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </AbsoluteFill>
    </Canvas>
  );
};
