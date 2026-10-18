import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { V1018 } from "../timeline";
import { C, FONT, mix, pop, tw } from "../theme";
import { Canvas, Caption, Clicks, Cursor, Glass, Lines, MacWindow, Rise, useVertical } from "../ui";

// 1.0.18: Settings now demonstrates each row, and the common features start on.
// Same light desk, same window language as the rest of the film; no dark room, no tension.

const PAGES = ["效果", "卷帘", "刘海", "手势", "窗口浏览", "快捷键", "隐私", "高级"];

const Icon: React.FC<{ kind: string; size: number }> = ({ kind, size }) => {
  const s = size;
  if (kind === "notch") {
    return (
      <div style={{ width: s, height: s, display: "grid", placeItems: "center" }}>
        <div style={{ width: s * 0.86, height: s * 0.32, borderRadius: `0 0 ${s * 0.18}px ${s * 0.18}px`, background: "#0a0b0d", position: "relative" }}>
          <div style={{ position: "absolute", left: "50%", bottom: 3, width: 3, height: 3, marginLeft: -1.5, borderRadius: "50%", background: "#3a3f47" }} />
        </div>
      </div>
    );
  }
  if (kind === "activity") {
    return (
      <div style={{ width: s, height: s, display: "grid", placeItems: "center" }}>
        <div style={{ width: s * 0.7, height: s * 0.7, borderRadius: s * 0.18, background: C.blueSoft, display: "grid", placeItems: "center" }}>
          <div style={{ width: 0, height: 0, borderLeft: `${s * 0.2}px solid ${C.accent}`, borderTop: `${s * 0.12}px solid transparent`, borderBottom: `${s * 0.12}px solid transparent`, marginLeft: s * 0.06 }} />
        </div>
      </div>
    );
  }
  if (kind === "shelf") {
    return (
      <div style={{ width: s, height: s, display: "grid", placeItems: "center" }}>
        <div style={{ width: s * 0.74, height: s * 0.5, borderRadius: s * 0.1, border: `3px solid ${C.accent}`, borderTop: "none", position: "relative" }}>
          <div style={{ position: "absolute", left: s * 0.1, top: -s * 0.2, width: s * 0.5, height: 3, background: C.accent, borderRadius: 2 }} />
          <div style={{ position: "absolute", left: s * 0.1, top: -s * 0.09, width: s * 0.34, height: 3, background: C.accent, borderRadius: 2, opacity: 0.6 }} />
        </div>
      </div>
    );
  }
  return (
    <div style={{ width: s, height: s, display: "grid", placeItems: "center" }}>
      <div style={{ width: s * 0.8, height: s * 0.34, borderRadius: s * 0.1, background: C.blueSoft, display: "flex", gap: s * 0.06, alignItems: "center", justifyContent: "center" }}>
        {[0, 1, 2].map((i) => (
          <div key={i} style={{ width: s * 0.14, height: s * 0.14, borderRadius: s * 0.035, background: i === 1 ? C.accent : "#9db6e8" }} />
        ))}
      </div>
    </div>
  );
};

const Chip: React.FC<{ kind: string; label: string; at: number; v: boolean; index: number }> = ({ kind, label, at, v, index }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, at);
  const s = v ? 440 : 270;
  const h = v ? 170 : 150;
  return (
    <Glass
      radius={v ? 30 : 26}
      tint="rgba(255,255,255,.62)"
      style={{
        left: v ? 88 + (index % 2) * (s + 24) : 387 + index * (s + 22),
        top: v ? 1300 + Math.floor(index / 2) * (h + 24) : 660,
        width: s,
        height: h,
        opacity: Math.min(1, p * 1.5),
        scale: String(0.86 + 0.14 * p),
      }}
    >
      <div style={{ position: "relative", height: h, display: "flex", alignItems: "center", gap: v ? 24 : 18, padding: v ? "0 30px" : "0 24px" }}>
        <Icon kind={kind} size={v ? 64 : 54} />
        <div style={{ display: "grid", gap: 8 }}>
          <div style={{ fontSize: v ? 34 : 28, fontWeight: 650, color: C.ink, whiteSpace: "nowrap" }}>{label}</div>
          <div style={{ display: "inline-flex", alignItems: "center", gap: 6, width: "fit-content", padding: "3px 9px", borderRadius: 99, background: C.blueSoft, color: C.accent, fontSize: v ? 18 : 16, fontWeight: 600 }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: C.accent }} />
            默认开
          </div>
        </div>
      </div>
    </Glass>
  );
};

export const Version1018: React.FC = () => {
  const f = useCurrentFrame();
  const v = useVertical();
  const win = v ? { x: 40, y: 330, w: 1000, h: 900, k: 1.35 } : { x: 100, y: 230, w: 1180, h: 760, k: 1.5 };
  const bar = 36 * win.k;
  const sideW = v ? 220 : 240;
  const contentX = sideW + 18;
  const contentW = win.w - contentX - 18;
  const bandH = v ? 200 : 220;
  const tileW = (contentW - 14) / 2;
  const rowsTop = bandH + 52;
  const rowH = v ? 66 : 62;

  // The band demonstrates the highlighted row: the mini window rolls up, then back.
  const roll = tw(f, 58, 98, 0, 1) * (1 - tw(f, 152, 192, 0, 1));
  const focus = tw(f, 34, 54) * (1 - tw(f, 220, 234));
  const cursorX = mix(win.x + win.w - 90, win.x + contentX + 250, tw(f, 12, 38));
  const cursorY = mix(win.y + win.h - 70, win.y + bar + rowsTop + rowH + rowH / 2, tw(f, 12, 38));
  const winOut = tw(f, 230, 248, 1, 0);

  return (
    <Canvas>
      <Caption
        zh="设置里，指到哪一行，就演哪一行。"
        en="Point at a row. Settings shows you."
        at={V1018.caption1}
        out={V1018.caption1Out}
        top={v ? 110 : undefined}
        size={v ? 60 : 76}
      />
      <Caption
        zh="这一版，常用功能默认打开。"
        en="On by default this release."
        at={V1018.caption2}
        out={V1018.caption2 + 86}
        top={v ? 110 : undefined}
        size={v ? 56 : 76}
      />
      <Caption
        zh="自己改过的，照你的来。"
        en="Your own choices stay."
        at={V1018.caption2 + 86}
        size={v ? 46 : 60}
        top={v ? 110 : undefined}
      />

      {/* Settings window */}
      <AbsoluteFill style={{ opacity: winOut, transform: `translateY(${(1 - winOut) * 28}px)` }}>
        <div style={{ position: "absolute", inset: 0 }}>
          <MacWindow x={win.x} y={win.y} w={win.w} h={win.h} title="WindowShade 设置" k={win.k} body="#ffffff">
            <div style={{ position: "absolute", inset: 0, display: "flex" }}>
              {/* sidebar */}
              <div style={{ width: sideW, height: "100%", background: "#f5f5f7", borderRight: "1px solid rgba(0,0,0,.06)", padding: 14, boxSizing: "border-box" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, height: 34, borderRadius: 8, background: "#eceef2", padding: "0 10px", color: C.muted, fontSize: 15 }}>
                  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke={C.muted} strokeWidth="1.8"><circle cx="7" cy="7" r="4.5" /><path d="m10.5 10.5 3 3" /></svg>
                  搜索
                </div>
                <div style={{ marginTop: 10, display: "grid", gap: 2 }}>
                  {PAGES.map((page, i) => (
                    <div
                      key={page}
                      style={{
                        height: v ? 40 : 38,
                        borderRadius: 8,
                        display: "flex",
                        alignItems: "center",
                        gap: 9,
                        padding: "0 10px",
                        fontSize: 15,
                        color: i === 0 ? C.ink : C.muted,
                        background: i === 0 ? "#e3e8f2" : "transparent",
                        fontWeight: i === 0 ? 600 : 500,
                      }}
                    >
                      <div style={{ width: 15, height: 15, borderRadius: 4, border: `1.6px solid ${i === 0 ? C.accent : "#aeb3bd"}`, opacity: 0.9 }} />
                      {page}
                    </div>
                  ))}
                </div>
              </div>

              {/* content */}
              <div style={{ position: "relative", flex: 1, padding: 16, boxSizing: "border-box" }}>
                <div style={{ display: "flex", gap: 14 }}>
                  {/* left tile: what you do */}
                  <div style={{ width: tileW, height: bandH, borderRadius: 16, background: "#f1f2f4", position: "relative", overflow: "hidden" }}>
                    <div style={{ position: "absolute", left: tileW * 0.18, top: bandH * 0.2, width: tileW * 0.64, height: bandH * 0.6, borderRadius: 12, background: "#fff", boxShadow: "0 6px 18px rgba(22,28,45,.10), 0 0 0 1px rgba(0,0,0,.05)", padding: 14, boxSizing: "border-box" }}>
                      <Lines k={0.9} widths={[86, 64, 78, 50]} />
                    </div>
                    <div style={{ position: "absolute", left: tileW * 0.56, top: bandH * 0.5 }}>
                      <Cursor x={0} y={0} size={34} />
                    </div>
                  </div>
                  {/* right tile: what happens */}
                  <div style={{ width: tileW, height: bandH, borderRadius: 16, background: "linear-gradient(160deg,#5b8ee8,#7fa8f0)", position: "relative", overflow: "hidden" }}>
                    <div style={{ position: "absolute", left: (tileW - 210) / 2, top: (bandH - 150) / 2 }}>
                      <MacWindow x={0} y={0} w={210} h={150} title="最后一版" k={0.72} roll={roll} body="#ffffff">
                        <div style={{ padding: 14 }}>
                          <Lines k={0.75} widths={[92, 74, 84, 56]} />
                        </div>
                      </MacWindow>
                    </div>
                  </div>
                </div>
                <div style={{ marginTop: 12, fontSize: v ? 16 : 14, color: C.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                  设置合盖桌面效果与窗口收起动画。传感器还没启动 · 当前 —
                </div>
                <div style={{ marginTop: 14, borderRadius: 14, background: "#f7f8fa", padding: 6 }}>
                  {[
                    { title: "合盖时的桌面", sub: "合上或打开时，桌面跟着动", on: true },
                    { title: "暂停效果", sub: "所有效果先停一停，开关保持原样", on: false },
                    { title: "收起窗口时的动画", sub: "收起或展开窗口时播放动画", on: true },
                    { title: "锁屏开合效果", sub: "锁屏时开合盖子，锁屏画面跟着动", on: true },
                  ].map((row, i) => (
                    <div
                      key={row.title}
                      style={{
                        height: rowH,
                        borderRadius: 10,
                        display: "flex",
                        alignItems: "center",
                        gap: 12,
                        padding: "0 12px",
                        position: "relative",
                        background: i === 2 ? `rgba(36,94,234,${0.09 * focus})` : "transparent",
                      }}
                    >
                      {i === 2 ? (
                        <div style={{ position: "absolute", left: 0, top: 12, bottom: 12, width: 3, borderRadius: 2, background: C.accent, opacity: focus }} />
                      ) : null}
                      <div style={{ width: 30, height: 30, borderRadius: 8, background: "#e9effc", display: "grid", placeItems: "center", flex: "none" }}>
                        <div style={{ width: 13, height: 13, borderRadius: 3, border: `2px solid ${C.accent}`, opacity: 0.85 }} />
                      </div>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontSize: v ? 18 : 16, fontWeight: 600, color: C.ink, whiteSpace: "nowrap" }}>{row.title}</div>
                        <div style={{ fontSize: v ? 13 : 12, color: C.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{row.sub}</div>
                      </div>
                      <div style={{ marginLeft: "auto", width: 44, height: 26, borderRadius: 99, background: row.on ? C.accent : "#e2e5ea", boxShadow: "inset 0 0 0 1px rgba(0,0,0,.05)", flex: "none" }}>
                        <div style={{ width: 22, height: 22, borderRadius: "50%", background: "#fff", margin: 2, marginLeft: row.on ? 20 : 2, boxShadow: "0 1px 3px rgba(0,0,0,.2)" }} />
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </MacWindow>
          <Cursor x={cursorX} y={cursorY} size={v ? 40 : 44} opacity={1 - tw(f, 220, 234)} />
          <Clicks x={win.x + contentX + 250} y={win.y + bar + rowsTop + rowH + rowH / 2} at={[V1018.click]} />
        </div>
      </AbsoluteFill>

      {/* Defaults chips */}
      <Chip kind="notch" label="刘海收纳" at={V1018.chips[0]} v={v} index={0} />
      <Chip kind="activity" label="实时活动" at={V1018.chips[1]} v={v} index={1} />
      <Chip kind="shelf" label="文件架" at={V1018.chips[2]} v={v} index={2} />
      <Chip kind="dock" label="Dock 预览" at={V1018.chips[3]} v={v} index={3} />
      <Rise at={V1018.chips[0] - 6}>
        <div
          style={{
            position: "absolute",
            right: v ? 60 : 88,
            top: v ? 1140 : 566,
            padding: "7px 14px",
            borderRadius: 99,
            background: C.accent,
            color: "#fff",
            fontFamily: FONT,
            fontSize: v ? 20 : 18,
            fontWeight: 650,
            letterSpacing: "0.02em",
            boxShadow: "0 8px 20px rgba(36,94,234,.28)",
          }}
        >
          1.0.18
        </div>
      </Rise>
    </Canvas>
  );
};
