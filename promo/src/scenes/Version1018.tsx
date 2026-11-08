import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { V1018 } from "../timeline";
import { C, FONT, mix, pop, tw } from "../theme";
import { Canvas, Caption, Clicks, Cursor, Glass, Lines, MacWindow, Rise, useVertical } from "../ui";

// 1.0.18: Settings now demonstrates each row, and the common features start on.
// Same light desk, same window language as the rest of the film; no dark room, no tension.

const PAGES = ["效果", "卷帘", "刘海", "手势", "窗口浏览", "快捷键", "隐私", "高级"];

// Each default is shown as itself, not as an icon: the card is a small vignette of
// what turns on, so the block carries weight instead of floating four chips.
const Vignette: React.FC<{ kind: string; w: number; h: number }> = ({ kind, w, h }) => {
  if (kind === "notch") {
    return (
      <div style={{ position: "relative", width: w, height: h }}>
        <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 26, background: "rgba(20,26,38,.05)", boxShadow: "inset 0 -1px 0 rgba(0,0,0,.06)" }} />
        <div
          style={{
            position: "absolute",
            left: (w - 132) / 2,
            top: 4,
            width: 132,
            height: 40,
            background: C.black,
            borderBottomLeftRadius: 13,
            borderBottomRightRadius: 13,
            display: "grid",
            placeItems: "center",
          }}
        >
          <div style={{ fontSize: 12, color: "#c6cbd4", letterSpacing: "0.02em" }}>参考资料 · 1</div>
        </div>
        {[0, 1, 2].map((i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: w / 2 - 20 + i * 14,
              top: 64 + i * 8,
              width: 3,
              height: 18 - i * 3,
              borderRadius: 2,
              background: C.accent,
              opacity: 0.42 - i * 0.09,
            }}
          />
        ))}
        <div
          style={{
            position: "absolute",
            left: (w - 88) / 2 + 4,
            top: h - 88,
            width: 88,
            height: 68,
            borderRadius: 8,
            overflow: "hidden",
            background: "#fff",
            boxShadow: "0 8px 20px rgba(22,28,45,.18), 0 0 0 1px rgba(0,0,0,.06)",
          }}
        >
          <div style={{ height: 17, background: C.bar, borderBottom: "1px solid rgba(0,0,0,.07)", display: "flex", alignItems: "center", gap: 3, padding: "0 6px" }}>
            {["#ec6a5e", "#f4bf4f", "#61c554"].map((c) => (
              <div key={c} style={{ width: 4.5, height: 4.5, borderRadius: "50%", background: c }} />
            ))}
          </div>
          <div style={{ padding: "10px 10px" }}>
            <Lines k={0.55} widths={[100, 74, 88]} color="rgba(33,72,132,.16)" />
          </div>
        </div>
      </div>
    );
  }
  if (kind === "activity") {
    return (
      <div style={{ position: "relative", width: w, height: h }}>
        <div
          style={{
            position: "absolute",
            left: (w - 208) / 2,
            top: 18,
            width: 208,
            height: 92,
            background: C.black,
            borderRadius: 18,
            boxShadow: "0 14px 30px rgba(10,12,20,.28)",
            padding: "13px 16px",
            boxSizing: "border-box",
            display: "grid",
            gap: 8,
            alignContent: "start",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
            <div style={{ width: 9, height: 9, borderRadius: "50%", background: "#ff6b5e" }} />
            <div style={{ fontSize: 15, fontWeight: 650, color: "#f4f5f7" }}>番茄钟</div>
            <div style={{ marginLeft: "auto", fontSize: 12, color: "#9aa0ab" }}>12:04</div>
          </div>
          <div style={{ height: 6, borderRadius: 99, background: "rgba(255,255,255,.14)" }}>
            <div style={{ width: "62%", height: "100%", borderRadius: 99, background: "#7fa8f0" }} />
          </div>
          <div style={{ fontSize: 12, color: "#9aa0ab" }}>专注中 · 还有 12 分钟</div>
        </div>
        <div style={{ position: "absolute", left: (w - 132) / 2, top: 132, width: 132, height: 34, borderRadius: 12, border: "1.5px dashed rgba(22,28,45,.16)", display: "grid", placeItems: "center", fontSize: 12, color: C.muted }}>
          更多活动
        </div>
      </div>
    );
  }
  if (kind === "shelf") {
    return (
      <div style={{ position: "relative", width: w, height: h }}>
        <div
          style={{
            position: "absolute",
            left: 14,
            right: 14,
            bottom: 30,
            height: 12,
            borderRadius: 6,
            background: "linear-gradient(180deg, rgba(36,94,234,.3), rgba(36,94,234,.16))",
            boxShadow: "0 6px 14px rgba(36,94,234,.18)",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: w / 2 - 86,
            bottom: 40,
            width: 66,
            height: 82,
            borderRadius: 7,
            background: "#fff",
            boxShadow: "0 8px 18px rgba(22,28,45,.16), 0 0 0 1px rgba(0,0,0,.05)",
            transform: "rotate(-5deg)",
            padding: "10px 9px",
            boxSizing: "border-box",
          }}
        >
          <div style={{ width: 20, height: 4, borderRadius: 2, background: C.accent, opacity: 0.85 }} />
          <div style={{ marginTop: 9 }}>
            <Lines k={0.5} widths={[100, 78, 92]} color="rgba(0,0,0,.08)" />
          </div>
        </div>
        <div
          style={{
            position: "absolute",
            left: w / 2 + 8,
            bottom: 42,
            width: 62,
            height: 78,
            borderRadius: 7,
            background: "#fff",
            boxShadow: "0 8px 18px rgba(22,28,45,.16), 0 0 0 1px rgba(0,0,0,.05)",
            transform: "rotate(4deg)",
            padding: "10px 9px",
            boxSizing: "border-box",
          }}
        >
          <div style={{ width: 20, height: 4, borderRadius: 2, background: "#f2b46b" }} />
          <div style={{ marginTop: 9 }}>
            <Lines k={0.5} widths={[92, 70]} color="rgba(0,0,0,.08)" />
          </div>
        </div>
        <div
          style={{
            position: "absolute",
            right: 16,
            bottom: 36,
            width: 22,
            height: 22,
            borderRadius: "50%",
            background: C.accent,
            color: "#fff",
            fontSize: 15,
            fontWeight: 600,
            display: "grid",
            placeItems: "center",
            boxShadow: "0 6px 14px rgba(36,94,234,.3)",
          }}
        >
          +
        </div>
      </div>
    );
  }
  return (
    <div style={{ position: "relative", width: w, height: h }}>
      <div
        style={{
          position: "absolute",
          left: (w - 152) / 2,
          top: 16,
          width: 152,
          height: 96,
          borderRadius: 12,
          background: "rgba(255,255,255,.94)",
          boxShadow: "0 14px 30px rgba(22,28,45,.18), 0 0 0 1px rgba(0,0,0,.05)",
          padding: 11,
          boxSizing: "border-box",
        }}
      >
        <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
          <div style={{ width: 16, height: 16, borderRadius: 4, background: C.blueSoft, border: `1.5px solid ${C.accent}` }} />
          <div style={{ fontSize: 11.5, fontWeight: 600, color: C.ink, whiteSpace: "nowrap" }}>页面 1 — 手稿</div>
        </div>
        <div style={{ marginTop: 9 }}>
          <Lines k={0.5} widths={[100, 84, 92, 58]} color="rgba(0,0,0,.07)" />
        </div>
      </div>
      <div style={{ position: "absolute", left: w / 2 - 8, top: 106, width: 16, height: 16, borderRadius: 3, background: "rgba(255,255,255,.94)", transform: "rotate(45deg)" }} />
      <div
        style={{
          position: "absolute",
          left: (w - 204) / 2,
          bottom: 26,
          width: 204,
          height: 48,
          borderRadius: 15,
          background: "rgba(255,255,255,.6)",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,.95), 0 10px 24px rgba(22,28,45,.16), 0 0 0 1px rgba(255,255,255,.7)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 9,
        }}
      >
        {["#7fa8f0", "#8fd0b0", "#f2b46b", "#d79ce8", "#9aa8bd"].map((c, i) => (
          <div
            key={i}
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              background: c,
              boxShadow: i === 0 ? `0 0 0 2px ${C.accent}, 0 4px 10px rgba(36,94,234,.3)` : "0 2px 6px rgba(22,28,45,.12)",
            }}
          />
        ))}
      </div>
    </div>
  );
};

const SUB: Record<string, string> = {
  notch: "窗口收进刘海，点一下回来",
  activity: "番茄钟、下载，在刘海里看进度",
  shelf: "拖来的文件，先放在屏幕边上",
  dock: "指一下 Dock，就知道是哪扇窗",
};

const FeatureCard: React.FC<{ kind: string; label: string; at: number; v: boolean; index: number }> = ({ kind, label, at, v, index }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, at);
  const w = v ? 900 : 640;
  const h = v ? 260 : 252;
  return (
    <Glass
      radius={30}
      tint="rgba(255,255,255,.66)"
      style={{
        left: v ? 90 : 306 + (index % 2) * 668,
        top: v ? 500 + index * 280 : 372 + Math.floor(index / 2) * 280,
        width: w,
        height: h,
        opacity: Math.min(1, p * 1.5),
        scale: String(0.9 + 0.1 * p),
      }}
    >
      <div style={{ position: "relative", height: h, display: "flex", alignItems: "center", gap: v ? 26 : 24, padding: v ? "0 32px" : "0 26px", boxSizing: "border-box" }}>
        <Vignette kind={kind} w={240} h={200} />
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: v ? 34 : 32, fontWeight: 650, color: C.ink, whiteSpace: "nowrap" }}>{label}</div>
          <div style={{ marginTop: 8, fontSize: v ? 21 : 20, lineHeight: 1.35, color: C.muted, whiteSpace: "nowrap" }}>{SUB[kind]}</div>
          <div
            style={{
              marginTop: 14,
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              padding: "4px 11px",
              borderRadius: 99,
              background: C.blueSoft,
              color: C.accent,
              fontSize: 17,
              fontWeight: 600,
            }}
          >
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
  const win = v ? { x: 40, y: 330, w: 1000, h: 680, k: 1.35 } : { x: 370, y: 250, w: 1180, h: 660, k: 1.5 };
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

      {/* Defaults, each shown as itself */}
      <FeatureCard kind="notch" label="刘海收纳" at={V1018.chips[0]} v={v} index={0} />
      <FeatureCard kind="activity" label="实时活动" at={V1018.chips[1]} v={v} index={1} />
      <FeatureCard kind="shelf" label="文件架" at={V1018.chips[2]} v={v} index={2} />
      <FeatureCard kind="dock" label="Dock 预览" at={V1018.chips[3]} v={v} index={3} />
      <div style={{ position: "absolute", left: 0, right: 0, top: v ? 1652 : 948, display: "flex", justifyContent: "center" }}>
        <Rise at={V1018.chips[0] - 6}>
          <div
            style={{
              padding: "7px 14px",
              borderRadius: 99,
              background: C.accent,
              color: "#fff",
              fontFamily: FONT,
              fontSize: 18,
              fontWeight: 650,
              letterSpacing: "0.02em",
              boxShadow: "0 8px 20px rgba(36,94,234,.28)",
            }}
          >
            1.0.18
          </div>
        </Rise>
      </div>
    </Canvas>
  );
};
