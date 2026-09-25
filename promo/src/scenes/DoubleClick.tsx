import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { DOUBLE } from "../timeline";
import { C, FONT, SERIF, easeInOut, easeOut, easeRoll, mix, tw } from "../theme";
import { Caption, Canvas, Clicks, Cursor, Glass, Lines, MacWindow, pressAt, tiltIn } from "../ui";

// The move itself, big: double-click, the window rolls up into its bar, the draft behind shows.
// Double-click again and it comes back exactly as it was.

const K = 1.7;
const REF = { x: 250, y: 300, w: 980, h: 600 };
const DRAFT = { x: 760, y: 360, w: 960, h: 620 };
const BAR = 36 * K;
const GRAB = { x: REF.x + REF.w / 2 + 70, y: REF.y + BAR / 2 };

export const DoubleClick: React.FC = () => {
  const frame = useCurrentFrame();
  const roll =
    tw(frame, DOUBLE.roll, DOUBLE.roll + 32, 0, 1, easeRoll) - tw(frame, DOUBLE.unroll, DOUBLE.unroll + 32, 0, 1, easeRoll);
  const arrive = tw(frame, 8, 54, 0, 1, easeOut);
  const cx = mix(1560, GRAB.x, arrive);
  const cy = mix(1060, GRAB.y, arrive);
  const clicks = [...DOUBLE.clicks, ...DOUBLE.clicksBack];
  const tag = tw(frame, DOUBLE.roll + 36, DOUBLE.roll + 50) * (1 - tw(frame, DOUBLE.swap - 6, DOUBLE.swap + 4));
  const zoom = mix(1, 1.05, tw(frame, 0, 360, 0, 1, easeInOut));

  return (
    <Canvas>
      <Caption zh="双击标题栏，窗口收起。" en="Double-click the title bar. It rolls up." at={2} out={DOUBLE.swap - 14} />
      <Caption zh="再双击，原样回来。" en="Double-click again. It’s back as it was." at={DOUBLE.swap} />
      <AbsoluteFill style={{ scale: String(zoom), transformOrigin: "50% 60%" }}>
        <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, 0, { y: 180, rx: 22 }) }}>
          <MacWindow {...DRAFT} title="文章草稿" k={K} active={false}>
            <div style={{ padding: "64px 70px", color: C.winInk }}>
              <div style={{ fontSize: 28, fontWeight: 600, color: C.winMuted }}>一个小动作的历史</div>
              <div style={{ fontFamily: SERIF, fontSize: 92, lineHeight: 1.15, margin: "22px 0 34px" }}>
                先让开，
                <br />
                待会儿回来。
              </div>
              <Lines k={K} widths={[100, 92, 96, 60]} />
            </div>
          </MacWindow>
        </div>
        <div style={{ position: "absolute", inset: 0, ...tiltIn(frame, 6, { y: 200, rx: 26 }) }}>
          <MacWindow {...REF} title="参考资料" k={K} roll={roll} body={C.blueSoft}>
            <div style={{ padding: "56px 64px", color: C.blueText }}>
              <div style={{ fontSize: 28, fontWeight: 600, color: C.accent }}>手册摘录 · 1994</div>
              <div style={{ fontFamily: SERIF, fontSize: 76, lineHeight: 1.18, margin: "18px 0 30px" }}>
                System 7.5 手册
                <br />
                第 48 页
              </div>
              <Lines k={K} widths={[100, 90, 74]} color="rgba(33,72,132,.12)" />
            </div>
          </MacWindow>
          <Glass
            radius={30}
            style={{
              left: REF.x + 10,
              top: REF.y + BAR + 30,
              height: 60,
              padding: "0 26px",
              display: "flex",
              alignItems: "center",
              opacity: tag,
              translate: `0 ${(1 - tag) * -14}px`,
            }}
          >
            <div style={{ position: "relative", fontFamily: FONT, fontSize: 30, fontWeight: 600, color: C.ink, whiteSpace: "nowrap" }}>
              卷帘条 <span style={{ color: C.muted, fontWeight: 500 }}>· stays in place</span>
            </div>
          </Glass>
        </div>
        <Clicks x={GRAB.x} y={GRAB.y} at={clicks} />
        <Cursor x={cx} y={cy} size={50} press={pressAt(frame, clicks)} opacity={tw(frame, 6, 14)} />
      </AbsoluteFill>
    </Canvas>
  );
};
