import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { GESTURES as G } from "../timeline";
import { C, FONT, easeInOut, easeOut, easeRoll, mix, tw } from "../theme";
import { Caption, Canvas, Cursor, Glass, Hud, Lines, MacWindow, Mouse, Rise, Trackpad, TypedText, tiltIn } from "../ui";

// Title-bar gestures, told the way the app behaves: the window follows the fingers (0.55 of
// the way), the HUD says what letting go will do, full track turns blue, release commits.
// Pull back halfway and nothing happens. A mouse wheel does the same in three notches.

const FOLLOW = 0.55;
const K = 1.25;
const BAR = 36 * K;
const SCREEN = { x: 610, y: 262, w: 1210, h: 756 };
const MENU = 30;
const DOCK = 86;

type Rect = { x: number; y: number; w: number; h: number };
const NORMAL: Rect = { x: 250, y: 118, w: 700, h: 440 };
const FILL: Rect = { x: 0, y: MENU, w: SCREEN.w, h: SCREEN.h - MENU - DOCK };
const LEFT: Rect = { ...FILL, w: SCREEN.w / 2 };
const RIGHT: Rect = { ...FILL, x: SCREEN.w / 2, w: SCREEN.w / 2 };
const lerpRect = (a: Rect, b: Rect, t: number): Rect => ({
  x: mix(a.x, b.x, t),
  y: mix(a.y, b.y, t),
  w: mix(a.w, b.w, t),
  h: mix(a.h, b.h, t),
});

/** Progress of a two-finger gesture: 0 at touch, full (1) twelve frames before release. */
const progress = (f: number, g: { down: number; release: number }) =>
  interpolate(f, [g.down + 6, g.release - 12, g.release - 6], [0, 1, 1.12], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing2,
  });
function Easing2(t: number) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}
const commit = (f: number, g: { release: number }) => tw(f, g.release, g.release + 26, 0, 1, easeRoll);
const touching = (f: number, g: { down: number; release: number }) =>
  tw(f, g.down - 4, g.down + 4) * (1 - tw(f, g.release, g.release + 8));

type State = { rect: Rect; roll: number; hud?: { title: string; p: number; o: number; armedAt?: number }; fingers: { x: number; y: number; on: number } };

function stateAt(f: number): State {
  const rest = { x: 0.5, y: 0.55, on: 0 };
  // 1. push up → roll up
  if (f < G.expand.down - 10) {
    const g = G.shade;
    const p = progress(f, g);
    const c = commit(f, g);
    const roll = f < g.release ? Math.min(1, p * FOLLOW) : mix(Math.min(1, 1.12 * FOLLOW), 1, c);
    return {
      rect: NORMAL,
      roll,
      hud: { title: "收起窗口", p, o: touching(f, g) + (f > g.release ? 1 - tw(f, g.release, g.release + 10) : 0), armedAt: g.release - 12 },
      fingers: { x: 0.5, y: 0.66 - Math.min(p, 1.12) * 0.3, on: touching(f, g) },
    };
  }
  // 2. pull down on the bar → unroll
  if (f < G.fill.down - 10) {
    const g = G.expand;
    const p = progress(f, g);
    const c = commit(f, g);
    const roll = f < g.release ? 1 - Math.min(1, p * FOLLOW) : mix(1 - 1.12 * FOLLOW, 0, c);
    return {
      rect: NORMAL,
      roll,
      hud: { title: "展开窗口", p, o: touching(f, g) + (f > g.release ? 1 - tw(f, g.release, g.release + 10) : 0), armedAt: g.release - 12 },
      fingers: { x: 0.5, y: 0.34 + Math.min(p, 1.12) * 0.3, on: touching(f, g) },
    };
  }
  // 3. pull down again → fill the screen between menu bar and Dock
  const place = (g: { down: number; release: number }, from: Rect, to: Rect, title: string, fx: (p: number) => number, fy: (p: number) => number, next: number): State | null => {
    if (f >= next - 10) return null;
    const p = progress(f, g);
    const c = commit(f, g);
    const t = f < g.release ? Math.min(1, p * FOLLOW) : mix(1.12 * FOLLOW, 1, c);
    return {
      rect: lerpRect(from, to, t),
      roll: 0,
      hud: { title, p, o: touching(f, g) + (f > g.release ? 1 - tw(f, g.release, g.release + 10) : 0), armedAt: g.release - 12 },
      fingers: { x: fx(Math.min(p, 1.12)), y: fy(Math.min(p, 1.12)), on: touching(f, g) },
    };
  };
  return (
    place(G.fill, NORMAL, FILL, "铺满屏幕", () => 0.5, (p) => 0.34 + p * 0.3, G.left.down) ??
    place(G.left, FILL, LEFT, "左半屏", (p) => 0.64 - p * 0.28, () => 0.5, G.right.down) ??
    place(G.right, LEFT, RIGHT, "右半屏", (p) => 0.36 + p * 0.28, () => 0.5, G.cancel.down) ??
    cancelOrWheel(f, rest)
  );
}

function cancelOrWheel(f: number, rest: { x: number; y: number; on: number }): State {
  if (f < G.wheel.swap) {
    const g = G.cancel;
    const p = interpolate(f, [g.down + 6, g.peak, g.back], [0, 0.8, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing2 });
    const on = tw(f, g.down - 4, g.down + 4) * (1 - tw(f, g.back, g.back + 8));
    return {
      rect: RIGHT,
      roll: p * FOLLOW,
      hud: { title: "收起窗口", p, o: on * (f > g.back - 12 ? 1 - tw(f, g.back - 12, g.back + 2) : 1) },
      fingers: { x: 0.5, y: 0.66 - p * 0.3, on },
    };
  }
  const w = G.wheel;
  const steps = w.notches.map((n) => tw(f, n, n + 6, 0, 1 / 3, easeOut)).reduce((a, b) => a + b, 0);
  const c = commit(f, { release: w.commit });
  const t = f < w.commit ? steps * FOLLOW : mix(FOLLOW, 1, c);
  const hudOn = tw(f, w.notches[0] - 2, w.notches[0] + 4) * (1 - tw(f, w.commit, w.commit + 10));
  return {
    rect: lerpRect(RIGHT, FILL, t),
    roll: 0,
    hud: { title: "铺满屏幕", p: steps >= 0.999 ? 1 : steps, o: hudOn, armedAt: w.notches[2] + 1 },
    fingers: { ...rest },
  };
}

export const Gestures: React.FC = () => {
  const frame = useCurrentFrame();

  if (frame < G.desk) {
    return (
      <Canvas dark>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
          <div style={{ fontFamily: FONT, fontSize: 112, fontWeight: 700, letterSpacing: "-0.02em", color: "#f4f5f7" }}>
            <TypedText t={G.line} caretColor={C.accent} />
          </div>
          <Rise at={G.line.at + 60}>
            <div style={{ fontSize: 38, fontWeight: 500, color: "#9ea3ad", marginTop: 18 }}>Now try two fingers on the title bar.</div>
          </Rise>
        </AbsoluteFill>
      </Canvas>
    );
  }

  const s = stateAt(frame);
  const r = s.rect;
  // Pointer rests on the title bar; between gestures it glides to where the bar is now.
  const downs = [G.shade.down, G.expand.down, G.fill.down, G.left.down, G.right.down, G.cancel.down, G.wheel.notches[0]];
  const barCenter = (st: State) => ({ x: SCREEN.x + st.rect.x + st.rect.w / 2 + 60, y: SCREEN.y + st.rect.y + BAR / 2 + 2 });
  let cur = { x: 1700, y: 1060 };
  for (const d of downs) {
    const target = barCenter(stateAt(d - 20));
    const t = tw(frame, d - 34, d - 10, 0, 1, easeInOut);
    cur = { x: mix(cur.x, target.x, t), y: mix(cur.y, target.y, t) };
  }

  const mouseOn = tw(frame, G.wheel.swap, G.wheel.swap + 20, 0, 1, easeOut);
  const wheelTurns = G.wheel.notches.map((n) => tw(frame, n, n + 8, 0, 1, easeOut)).reduce((a, b) => a + b, 0);
  const wheelGlow = Math.max(...G.wheel.notches.map((n) => tw(frame, n, n + 3) * (1 - tw(frame, n + 6, n + 16))));

  return (
    <Canvas>
      <Caption zh="往上推，收起。" en="Push up to roll it up." at={G.shade.down - 20} out={G.expand.down - 24} />
      <Caption zh="往下拉，展开。" en="Pull down to unroll it." at={G.expand.down - 14} out={G.fill.down - 18} />
      <Caption zh="再往下拉，铺满屏幕。" en="Pull down again to fill the screen." at={G.fill.down - 8} out={G.left.down - 26} />
      <Caption zh="左右滑，各占半屏。" en="Swipe sideways for half the screen." at={G.left.down - 14} out={G.cancel.down - 22} />
      <Caption zh="滑到一半往回拉，就当没发生过。" en="Pull back halfway and nothing happens." at={G.cancel.down - 12} out={G.wheel.swap - 14} />
      <Caption zh="用鼠标，滚三格也一样。" en="On a mouse, three notches of the wheel." at={G.wheel.swap} />

      {/* the Mac */}
      <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, G.desk, { y: 220, rx: 26, ry: -8 }) }}>
        <div
          style={{
            position: "absolute",
            left: SCREEN.x,
            top: SCREEN.y,
            width: SCREEN.w,
            height: SCREEN.h,
            borderRadius: 26,
            overflow: "hidden",
            background: C.wall,
            boxShadow: "0 0 0 10px #1c1d21, 0 0 0 11px #3a3b40, 0 50px 90px rgba(20,28,48,.3)",
          }}
        >
          <div
            style={{
              position: "absolute",
              inset: "0 0 auto",
              height: MENU,
              display: "flex",
              alignItems: "center",
              gap: 26,
              padding: "0 22px",
              fontSize: 17,
              color: C.winInk,
              background: "rgba(255,255,255,.5)",
              backdropFilter: "blur(12px)",
              zIndex: 5,
            }}
          >
            <b></b>
            <b style={{ fontWeight: 650 }}>文本编辑</b>
            <span>文件</span>
            <span>编辑</span>
            <span>显示</span>
            <span>窗口</span>
            <span style={{ marginLeft: "auto" }}>9:41</span>
          </div>
          <MacWindow x={r.x} y={r.y} w={r.w} h={r.h} title="会议记录" k={K} roll={s.roll} body={C.blueSoft}>
            <div style={{ padding: "34px 40px", color: C.blueText }}>
              <div style={{ fontSize: 18, fontWeight: 600, color: C.accent }}>周四 · 产品例会</div>
              <div style={{ fontFamily: '"Iowan Old Style","Songti SC",serif', fontSize: 54, lineHeight: 1.2, margin: "12px 0 24px" }}>
                先把能删的
                <br />
                删掉。
              </div>
              <Lines k={K} widths={[100, 86, 94, 62]} color="rgba(33,72,132,.12)" />
            </div>
          </MacWindow>
          <Glass radius={24} style={{ left: SCREEN.w / 2 - 260, top: SCREEN.h - 74, width: 520, height: 64, zIndex: 6 }}>
            <div style={{ position: "relative", display: "flex", gap: 12, padding: 9, justifyContent: "center" }}>
              {["#3d7bf7", "#f2a93b", "#48b865", "#e85d75", "#8d6bf0", "#1fb5c9"].map((bg) => (
                <div key={bg} style={{ width: 46, height: 46, borderRadius: 12, background: bg, boxShadow: "inset 0 0 0 1px rgba(0,0,0,.08)" }} />
              ))}
            </div>
          </Glass>
          {s.hud && s.hud.o > 0.001 ? (
            <Hud
              cx={r.x + r.w / 2}
              top={Math.min(r.y + BAR + 12, SCREEN.h - 190)}
              k={1.8}
              title={s.hud.title}
              progress={s.hud.p}
              opacity={Math.min(1, s.hud.o)}
              armedAt={s.hud.armedAt}
            />
          ) : null}
        </div>
        <Cursor x={cur.x} y={cur.y} size={44} opacity={tw(frame, G.desk + 10, G.desk + 20)} />
      </div>

      {/* the hand */}
      <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, G.desk + 8, { y: 200, rx: 30 }) }}>
        <Trackpad x={50} y={500} w={500} fingers={s.fingers} opacity={1 - mouseOn} style={{ translate: `0 ${mouseOn * 40}px` }} />
        {mouseOn > 0 ? <Mouse x={215} y={440 + (1 - mouseOn) * 60} w={190} wheel={wheelTurns} glow={wheelGlow} opacity={mouseOn} /> : null}
        <div style={{ position: "absolute", left: 50, width: 500, top: 860, textAlign: "center", fontFamily: FONT, fontSize: 26, color: C.muted }}>
          {mouseOn > 0.5 ? "鼠标滚轮 · Mouse wheel" : "触控板 · Trackpad"}
        </div>
      </div>
    </Canvas>
  );
};
