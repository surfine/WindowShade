import React from "react";
import { useCurrentFrame } from "remotion";
import { NOTCH_DEMO } from "../timeline";
import { C, FONT, mix, motion, pop, tw } from "../theme";
import { Canvas, Caption, Clicks, Cursor, Lines, MacWindow, useVertical } from "../ui";

// The notch, 1.0.18's headline home: park a window there, it taps you when the window
// changes, one click brings it back. Same light desk and window language as the rest
// of the film; the notch itself is the product's black pill on a menu-bar strip.

export const NotchDemo: React.FC = () => {
  const f = useCurrentFrame();
  const v = useVertical();
  const cx = v ? 540 : 960;

  // The window under hand. Same 参考资料 the film has been carrying since Ways.
  const winW = v ? 560 : 480;
  const winH = v ? 420 : 360;
  const winX = v ? (1080 - 560) / 2 : 720;
  const winY = v ? 880 : 330;

  const N = NOTCH_DEMO;
  // Flick: the cursor snaps up the title bar and the window is off (flyOut).
  const fly = motion(f, N.fly, "flyOut");
  // The notch takes it in, holds it as one cell, then taps when it changes.
  const takeIn = pop(f, N.arrive);
  const notice = tw(f, N.notice, N.notice + 24) * (1 - tw(f, N.noticeOut, N.noticeOut + 22));
  // Click, drawer, back.
  const drawer = motion(f, N.drawer, "expand") * (1 - tw(f, N.returnFly, N.returnFly + 14));
  const back = motion(f, N.returnFly, "flyOut");
  const unroll = motion(f, N.unroll, "settle");

  const gone = fly >= 1;
  const home = back >= 1;

  // Geometry of the notch pill: bare → one cell → notice → drawer.
  const notchW = mix(mix(150, 210, takeIn), 380, Math.max(notice, drawer));
  const notchH = mix(mix(30, 52, takeIn), 118, Math.max(notice, drawer));

  // The window: on the desk → in flight → a strip landing back → unrolled.
  const flyX = mix(winX + winW / 2, cx, fly);
  const flyY = mix(winY + 40, 16, fly);
  const flyS = mix(1, 0.16, fly);
  const backX = mix(cx, winX + winW / 2, back);
  const backY = mix(30, winY, back);
  const backS = mix(0.2, 1, back);

  // Cursor: title bar → flick up → across to the notch → click.
  const curX = mix(winX + winW * 0.62, cx, tw(f, N.cursorOver, N.click));
  const flickY = mix(winY + 44, winY - 6, tw(f, N.flick, N.flick + 16));
  const curY = mix(flickY, 66, tw(f, N.cursorOver, N.click));

  return (
    <Canvas>
      <Caption zh="暂时不看，收进刘海。" en="Park it in the notch." at={0} out={N.notice - 12} />
      <Caption zh="窗口有变化，它会提醒。" en="It taps you when a window changes." at={N.notice + 6} out={N.cursorOver - 10} />
      <Caption zh="点一下，放回。" en="One click brings it back." at={N.cursorOver + 26} />

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

      {/* the notch */}
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
        {drawer > 0.2 ? (
          /* drawer: the window waiting inside */
          <div style={{ opacity: drawer, scale: String(0.7 + 0.3 * drawer) }}>
            <MacWindow x={0} y={0} w={150} h={104} title="" k={0.6} roll={1} body="#fff" style={{ boxShadow: "0 8px 22px rgba(0,0,0,.5)" }} />
          </div>
        ) : notice > 0.1 ? (
          <>
            <div style={{ fontSize: 19, fontWeight: 650 }}>参考资料</div>
            <div style={{ fontSize: 14, color: "#b8bdc8" }}>内容已更新</div>
          </>
        ) : gone && !home ? (
          <div style={{ fontSize: 15, opacity: takeIn, color: "#c6cbd4" }}>参考资料 · 1</div>
        ) : (
          <div style={{ width: 7, height: 7, borderRadius: "50%", background: "#3a3f47" }} />
        )}
      </div>

      {/* the window on the desk, before and after its trip */}
      {!gone || home ? (
        <div
          style={{
            position: "absolute",
            left: (gone && home ? backX : winX + winW / 2) - winW / 2,
            top: (gone && home ? backY : winY),
            width: winW,
            transformOrigin: "50% 0%",
            transform: gone && home ? undefined : `translateX(${winW / 2}px) scale(${flyS}) translateX(-${winW / 2}px)`,
            opacity: gone && home ? 1 : 1 - tw(f, N.arrive - 6, N.arrive + 8),
          }}
        >
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} roll={gone && home ? 1 - unroll : 0} body={C.blueSoft}>
            <div style={{ padding: 40 }}>
              <div style={{ fontSize: 24, fontWeight: 600, color: C.accent }}>手册摘录 · 1994</div>
              <div style={{ fontFamily: '"Iowan Old Style","Songti SC",serif', fontSize: 52, lineHeight: 1.18, margin: "14px 0 22px", color: C.blueText }}>
                先让开，
                <br />
                待会儿回来。
              </div>
              <Lines k={1.5} widths={[100, 92, 96, 60]} color="rgba(33,72,132,.12)" />
            </div>
          </MacWindow>
        </div>
      ) : null}

      {/* the window in flight, both directions */}
      {!gone || home ? null : (
        <div
          style={{
            position: "absolute",
            left: flyX - winW / 2,
            top: flyY - 20,
            width: winW,
            transformOrigin: "50% 0%",
            transform: `translateX(${winW / 2}px) scale(${flyS}) translateX(-${winW / 2}px)`,
            opacity: 1 - tw(f, N.arrive - 8, N.arrive + 4),
          }}
        >
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} roll={Math.min(1, fly * 1.6)} body={C.blueSoft}>
            <div style={{ padding: 40 }} />
          </MacWindow>
        </div>
      )}
      {back > 0 && back < 1 ? (
        <div
          style={{
            position: "absolute",
            left: backX - winW / 2,
            top: backY,
            width: winW,
            transformOrigin: "50% 0%",
            transform: `translateX(${winW / 2}px) scale(${backS}) translateX(-${winW / 2}px)`,
          }}
        >
          <MacWindow x={0} y={0} w={winW} h={winH} title="参考资料" k={1.5} roll={1} body={C.blueSoft}>
            <div style={{ padding: 40 }} />
          </MacWindow>
        </div>
      ) : null}

      {/* flick ghost: one quick up-arrow of motion lines at the title bar */}
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

      <Cursor x={f < N.click ? curX : mix(curX, winX + winW * 0.62, tw(f, N.click + 30, N.click + 90))} y={f < N.click ? curY : mix(curY, winY + 44, tw(f, N.click + 30, N.click + 90))} size={v ? 44 : 46} opacity={1 - tw(f, N.unroll + 40, N.unroll + 70)} />
      <Clicks x={cx} y={64} at={[N.click]} />
    </Canvas>
  );
};
