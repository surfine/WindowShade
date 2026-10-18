import React from "react";
import { useCurrentFrame } from "remotion";
import { NOTCH_DEMO } from "../timeline";
import { C, FONT, mix, motion, tw } from "../theme";
import { Canvas, Caption, Clicks, Cursor, Lines, MacWindow, useVertical } from "../ui";

// The notch, 1.0.18's headline home: park a window there, it taps you when the window
// changes, one click brings it back. Same light desk and window language as the rest
// of the film. Sizing runs on one chained spring track (settle → bloom → settle →
// expand → settle), so the pill never snaps; the window is one element per leg of the
// trip, crossfaded at matching positions, so nothing double-renders.

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
  const winY = v ? 880 : 330;

  const N = NOTCH_DEMO;

  // ---- one spring track for the pill: bare → cell → notice → cell → drawer → bare ----
  const cellIn = motion(f, N.arrive, "settle"); // bare → cell
  const noticeIn = motion(f, N.notice, "bloom"); // cell → notice (the product's own notch bloom)
  const noticeOut = motion(f, N.noticeOut, "settle"); // notice → cell
  const drawerIn = motion(f, N.drawer, "expand"); // cell → drawer
  const drawerOut = motion(f, N.returnFly, "settle"); // drawer → cell
  const open = Math.max(noticeIn * (1 - noticeOut), drawerIn * (1 - drawerOut));
  const notchW = 150 + 60 * cellIn + 170 * open;
  const notchH = 30 + 22 * cellIn + 66 * open;

  // ---- the window's trip: one element per leg, crossfaded at matching poses ----
  const fly = motion(f, N.fly, "flyOut"); // desk → notch
  const back = motion(f, N.returnFly, "flyOut"); // notch → desk
  const unroll = motion(f, N.unroll, "settle"); // strip → window at home

  const deskOut = tw(f, N.fly - 2, N.fly + 8);
  const upIn = tw(f, N.fly, N.fly + 8);
  const upOut = tw(f, N.arrive - 8, N.arrive + 2);
  const backIn = tw(f, N.returnFly, N.returnFly + 6);

  const pose = (x: number, y: number, s: number) => ({
    left: x - winW / 2,
    top: y,
    width: winW,
    transformOrigin: "50% 0%",
    transform: `translateX(${winW / 2}px) scale(${s}) translateX(-${winW / 2}px)`,
  });
  const deskPose = pose(winX + winW / 2, winY, 1);
  const upPose = pose(mix(winX + winW / 2, cx, fly), mix(winY + 40, 16, fly), mix(1, 0.16, fly));
  const backPose = pose(mix(cx, winX + winW / 2, back), mix(30, winY, back), mix(0.2, 1, back));

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
      <Caption zh="暂时不看，收进刘海。" en="Park it in the notch." at={0} out={N.notice - 12} top={v ? 200 : 170} />
      <Caption zh="窗口有变化，它会提醒。" en="It taps you when a window changes." at={N.notice + 6} out={N.cursorOver - 10} top={v ? 200 : 170} />
      <Caption zh="点一下，放回。" en="One click brings it back." at={N.cursorOver + 26} top={v ? 200 : 170} />

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

      {/* the notch pill */}
      <div
        style={{
          position: "absolute",
          left: cx - notchW / 2,
          top: 0,
          width: notchW,
          height: notchH,
          background: "#0a0b0d",
          borderBottomLeftRadius: 20,
          borderBottomRightRadius: 20,
          boxShadow: "0 14px 40px rgba(10,12,20,.35)",
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

      {/* leg 1: the window on the desk, until the flick */}
      {deskOut < 1 ? (
        <div style={{ position: "absolute", ...deskPose, opacity: 1 - deskOut }}>
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} body={C.blueSoft}>
            <DocBody />
          </MacWindow>
        </div>
      ) : null}

      {/* leg 2: up into the notch */}
      {fly > 0 && upOut < 1 ? (
        <div style={{ position: "absolute", ...upPose, opacity: upIn * (1 - upOut) }}>
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} roll={Math.min(1, fly * 1.6)} body={C.blueSoft}>
            <div style={{ padding: 40 }} />
          </MacWindow>
        </div>
      ) : null}

      {/* leg 3: back out of the notch, lands as a strip, unrolls in place */}
      {back > 0 ? (
        <div style={{ position: "absolute", ...backPose, opacity: backIn }}>
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} roll={1 - unroll} body={C.blueSoft}>
            <DocBody />
          </MacWindow>
        </div>
      ) : null}

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
        opacity={1 - tw(f, N.unroll + 40, N.unroll + 70)}
      />
      <Clicks x={cx} y={64} at={[N.click]} />
    </Canvas>
  );
};
