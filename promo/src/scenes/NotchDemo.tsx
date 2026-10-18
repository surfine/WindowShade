import React from "react";
import { useCurrentFrame } from "remotion";
import { NOTCH_DEMO } from "../timeline";
import { C, FONT, mix, motion, tw } from "../theme";
import { Canvas, Caption, Clicks, Cursor, Lines, MacWindow, useVertical } from "../ui";

// The notch, 1.0.18's headline home, played the way the product plays it
// (prototype/App/Notch.swift):
//   · into the notch: the snapshot flies flat (no roll-up animation), settling dead-centre
//     into the pill — settle, no bounce, "终点是个口子" — and the pill swallows it
//     (it renders under the pill, so no fade is needed);
//   · the pill blooms open to catch it, settles to a one-cell size;
//   · out of the notch: flyOut with its landing bounce, straight back to its place,
//     full size — not a strip, no unroll beat.
// Text keeps breathing room below the pill (top 200 / pill visual bottom ~140).

const DocBody: React.FC = () => (
  <div style={{ padding: 40 }}>
    <div style={{ fontSize: 24, fontWeight: 600, color: C.accent }}>手册摘录 · 1994</div>
    <div
      style={{
        fontFamily: '"Iowan Old Style","Songti SC",serif',
        fontSize: 52,
        lineHeight: 1.18,
        margin: "14px 0 22px",
        color: C.blueText,
      }}
    >
      先让开，
      <br />
      待会儿回来。
    </div>
    <Lines k={1.5} widths={[100, 92, 96, 60]} color="rgba(33,72,132,.12)" />
  </div>
);

export const NotchDemo: React.FC = () => {
  const f = useCurrentFrame();
  const v = useVertical();
  const cx = v ? 540 : 960;

  const winW = v ? 560 : 480;
  const winH = v ? 420 : 360;
  const winX = v ? (1080 - 560) / 2 : 720;
  const winY = v ? 880 : 380;
  const pillY = 30; // cell centre: where the product lands the snapshot

  const N = NOTCH_DEMO;

  // ---- the pill: bare → (bloom open to catch) → cell → notice → cell → drawer ----
  const cellIn = motion(f, N.fly + 14, "bloom"); // opens as the window comes in (swallow)
  const noticeIn = motion(f, N.notice, "bloom");
  const noticeOut = motion(f, N.noticeOut, "settle");
  const drawerIn = motion(f, N.drawer, "expand");
  const drawerOut = motion(f, N.returnFly, "settle");
  const open = Math.max(noticeIn * (1 - noticeOut), drawerIn * (1 - drawerOut));
  const notchW = 150 + 60 * cellIn + 170 * open;
  const notchH = 30 + 22 * cellIn + 66 * open;
  const notchR = Math.max(10, Math.min(22, notchH * 0.22));

  // ---- the window's trip ----
  const fly = motion(f, N.fly, "settle"); // into the notch: settle, no bounce (product)
  const back = motion(f, N.returnFly, "flyOut"); // out: flyOut with landing bounce (product)

  const deskOut = tw(f, N.fly - 2, N.fly + 6); // the real window hides, the snapshot flies
  const upIn = tw(f, N.fly, N.fly + 6);
  const backIn = tw(f, N.returnFly, N.returnFly + 4);

  const pose = (x: number, y: number, s: number) => ({
    left: x - winW / 2,
    top: y,
    width: winW,
    transformOrigin: "50% 0%",
    transform: `translateX(${winW / 2}px) scale(${s}) translateX(-${winW / 2}px)`,
  });
  const deskPose = pose(winX + winW / 2, winY, 1);
  const upPose = pose(mix(winX + winW / 2, cx, fly), mix(winY, pillY, fly), mix(1, 0.3, fly));
  const backPose = pose(mix(cx, winX + winW / 2, back), mix(pillY, winY, back), mix(0.3, 1, back));

  // Cursor: title bar → flick up → across to the notch → click → drift home.
  const curX = mix(winX + winW * 0.62, cx, tw(f, N.cursorOver, N.click));
  const flickY = mix(winY + 44, winY - 6, tw(f, N.flick, N.flick + 16));
  const curY = mix(flickY, 66, tw(f, N.cursorOver, N.click));
  const afterClick = tw(f, N.click + 30, N.click + 90);

  const cellT = cellIn * (1 - noticeIn);
  const noticeT = noticeIn * (1 - noticeOut);
  const drawerT = drawerIn * (1 - drawerOut);

  return (
    <Canvas>
      <Caption zh="暂时不看，收进刘海。" en="Park it in the notch." at={0} out={N.notice - 12} top={v ? 230 : 200} />
      <Caption zh="窗口有变化，它会提醒。" en="It taps you when a window changes." at={N.notice + 6} out={N.cursorOver - 10} top={v ? 230 : 200} />
      <Caption zh="点一下，放回。" en="One click brings it back." at={N.cursorOver + 26} top={v ? 230 : 200} />

      {/* menu-bar strip grounds the notch at the top of the screen */}
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 0,
          height: v ? 60 : 56,
          background: "rgba(20,26,38,.045)",
          boxShadow: "inset 0 -0.6px 0 rgba(0,0,0,.08)",
        }}
      />
      <div style={{ position: "absolute", right: v ? 44 : 60, top: v ? 18 : 16, fontFamily: FONT, fontSize: 17, color: C.muted }}>9:41</div>

      {/* leg 1: the window on the desk, until the flick */}
      {deskOut < 1 ? (
        <div style={{ position: "absolute", ...deskPose, opacity: 1 - deskOut }}>
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} body={C.blueSoft}>
            <DocBody />
          </MacWindow>
        </div>
      ) : null}

      {/* leg 2: the snapshot flying flat into the pill's centre.
          Rendered under the pill (below in source order is wrong — Remotion stacks
          later on top — so the pill comes AFTER this), so once small it is covered:
          swallowed, no fade — the product does the same with the camera block. */}
      {fly > 0 && f < N.notice - 30 ? (
        <div style={{ position: "absolute", ...upPose, opacity: upIn }}>
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} body={C.blueSoft}>
            <DocBody />
          </MacWindow>
        </div>
      ) : null}

      {/* leg 3: back out of the notch — full size, straight home, landing bounce */}
      {back > 0 ? (
        <div style={{ position: "absolute", ...backPose, opacity: backIn }}>
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} body={C.blueSoft}>
            <DocBody />
          </MacWindow>
        </div>
      ) : null}

      {/* the notch pill — after the flight legs, so it covers them (the swallow) */}
      <div
        style={{
          position: "absolute",
          left: cx - notchW / 2,
          top: 0,
          width: notchW,
          height: notchH,
          background: "#0a0b0d",
          borderBottomLeftRadius: notchR,
          borderBottomRightRadius: notchR,
          boxShadow: "0 10px 30px rgba(10,12,20,.32)",
          overflow: "hidden",
          color: "#f4f5f7",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 4,
        }}
      >
        {cellT < 0.5 && noticeT < 0.5 && drawerT < 0.5 ? (
          <div style={{ width: 7, height: 7, borderRadius: "50%", background: "#3a3f47" }} />
        ) : null}
        {cellT > 0.02 ? (
          <div style={{ position: "absolute", fontSize: 16, color: "#c6cbd4", opacity: cellT }}>参考资料 · 1</div>
        ) : null}
        {noticeT > 0.02 ? (
          <div style={{ opacity: noticeT, display: "grid", justifyItems: "center", gap: 4 }}>
            <div style={{ fontSize: 19, fontWeight: 650 }}>参考资料</div>
            <div style={{ fontSize: 14, color: "#b8bdc8" }}>内容已更新</div>
          </div>
        ) : null}
        {drawerT > 0.02 ? (
          <div style={{ opacity: drawerT, scale: String(0.7 + 0.3 * drawerT) }}>
            <MacWindow x={0} y={0} w={150} h={104} title="" k={0.6} roll={1} body="#fff" style={{ boxShadow: "0 8px 22px rgba(0,0,0,.5)" }} />
          </div>
        ) : null}
      </div>

      {/* flick ghost: three quick motion lines off the title bar */}
      {f >= N.flick && f < N.flick + 22 ? (
        <div style={{ position: "absolute", left: winX + winW * 0.62 - 3, top: winY + 20, opacity: 1 - tw(f, N.flick + 6, N.flick + 22) }}>
          {[0, 8, 16].map((d) => (
            <div
              key={d}
              style={{
                position: "absolute",
                left: d,
                top: 18 - d * 0.9,
                width: 3,
                height: 16 - d * 0.3,
                borderRadius: 2,
                background: C.accent,
                opacity: 0.75,
                transform: `translateY(${-tw(f, N.flick + d * 0.4, N.flick + 14 + d) * 26}px)`,
              }}
            />
          ))}
        </div>
      ) : null}

      <Cursor
        x={f < N.click ? curX : mix(curX, winX + winW * 0.62, afterClick)}
        y={f < N.click ? curY : mix(curY, winY + 44, afterClick)}
        size={v ? 44 : 46}
        opacity={1 - tw(f, N.returnFly + 60, N.returnFly + 90)}
      />
      <Clicks x={cx} y={64} at={[N.click]} />
    </Canvas>
  );
};
