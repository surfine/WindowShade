import React from "react";
import { useCurrentFrame } from "remotion";
import { C, FONT, mix, motion, tw } from "../theme";
import { Canvas, Caption, Cursor, Lamps, useVertical } from "../ui";

const colors = ["#248af0", "#e5ad2b", "#ee5b54", "#7966d5", "#4ba982", "#6c7e94"];
const names = ["邮件", "笔记", "日历", "照片", "参考", "工具"];
const Icon: React.FC<{ i: number; size?: number }> = ({ i, size = 76 }) => (
  <div style={{ width: size, height: size, borderRadius: size * .23, background: colors[i % 6], display: "grid", placeItems: "center", boxShadow: "inset 0 1px 1px #ffffff70, 0 3px 8px #17274518" }}>
    <svg width={size * .62} height={size * .62} viewBox="0 0 32 32" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      {i === 0 ? <><rect x="3" y="6" width="26" height="20" rx="3" /><path d="m4 8 12 10L28 8" /></> : i === 2 ? <><rect x="5" y="6" width="22" height="23" rx="3" /><path d="M5 13h22M11 3v6M21 3v6M12 19h8M12 24h5" /></> : i === 3 ? <><circle cx="16" cy="16" r="9" /><path d="M16 3v6M16 23v6M3 16h6M23 16h6M7 7l4 4M21 21l4 4M7 25l4-4M21 11l4-4" /></> : <><rect x="7" y="3" width="18" height="26" rx="3" /><path d="M11 10h10M11 16h10M11 22h6" /></>}
    </svg>
  </div>
);

// The same spatial story in both cuts: folder → library → drag out → Slide Over → notch.
export const Multitask: React.FC = () => {
  const f = useCurrentFrame();
  const vertical = useVertical();
  const box = vertical ? { x: 65, y: 530, w: 950, h: 1050 } : { x: 170, y: 290, w: 1580, h: 650 };
  const k = vertical ? .86 : 1;
  const folder = tw(f, 48, 80) * (1 - tw(f, 136, 156));
  const library = tw(f, 166, 190) * (1 - tw(f, 240, 258));
  const desktop = tw(f, 274, 330);
  const travel = motion(f, 270, "glide");
  const windowIn = tw(f, 320, 356);
  const tuck = motion(f, 409, "settle") - motion(f, 472, "flyOut");
  const fly = motion(f, 535, "flyOut");
  const notice = tw(f, 600, 622) * (1 - tw(f, 668, 690));
  const ww = vertical ? 450 : 420;
  const wh = vertical ? 730 : 450;
  const wx = box.w - ww - 26 + tuck * (ww + 40);
  const wy = (box.h - wh) / 2 + 20;
  const iconX = mix(box.w * .42, box.w - 95, travel);
  const iconY = mix(box.h * .34, box.h * .5, travel);
  return <Canvas>
    <Caption zh="App 有位置，窗口也有去处。" en="A home for your apps. A place for each window." at={0} out={260} />
    <Caption zh="从启动台，拖到屏幕边。" en="Drag an app out into Slide Over." at={266} out={405} />
    <Caption zh="推到边外，随时拉回来。" en="Tuck it away. Pull it back." at={408} out={530} />
    <Caption zh="甩进刘海，有变化再提醒。" en="Flick it into the notch. See what changes." at={533} />
    <div style={{ position: "absolute", left: box.x, top: box.y, width: box.w, height: box.h, overflow: "hidden", borderRadius: 26, background: C.wall, boxShadow: "0 28px 70px #1b254f24, 0 0 0 1px #1b254f18", fontFamily: FONT }}>
      <div style={{ position: "absolute", inset: 0, background: "#5479b3", opacity: .5 * (1 - desktop) }} />
      <div style={{ position: "absolute", left: 28, top: 18, fontSize: 17, color: desktop > .5 ? C.ink : "white" }}>WindowShade</div>
      <div style={{ position: "absolute", right: 28, top: 18, fontSize: 17, color: desktop > .5 ? C.ink : "white" }}>9:41</div>
      <div style={{ position: "absolute", inset: "90px 65px 80px", opacity: (1 - desktop) * (1 - library), filter: `blur(${folder * 10}px)`, display: "grid", gridTemplateColumns: "repeat(3, 1fr)", alignContent: "space-around", gap: 45 }}>
        {names.map((name, i) => <div key={name} style={{ display: "grid", justifyItems: "center", gap: 14, color: "white", fontSize: 23, opacity: i === 1 && f > 270 ? 0 : 1 }}>
          {i === 5 ? <div style={{ width: 76, height: 76, padding: 10, boxSizing: "border-box", borderRadius: 18, background: "#ffffff35", display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 4 }}>{Array.from({ length: 9 }, (_, j) => <div key={j} style={{ background: colors[j % 6], borderRadius: 3 }} />)}</div> : <Icon i={i} />}{name}
        </div>)}
      </div>
      {folder > 0 && <div style={{ position: "absolute", left: "50%", top: "50%", width: vertical ? 580 : 680, height: 360, translate: "-50% -50%", scale: String(mix(.3, 1, folder)), opacity: folder, background: "#e4eaf275", backdropFilter: "blur(24px)", border: "1px solid #ffffff70", borderRadius: 40, display: "flex", justifyContent: "space-evenly", alignItems: "center" }}>
        <div style={{ position: "absolute", top: -64, color: "white", fontSize: 32, fontWeight: 600 }}>工具</div>
        {["终端", "计算器", "预览"].map((n, i) => <div key={n} style={{ display: "grid", justifyItems: "center", gap: 18, color: "white", fontSize: 22 }}><Icon i={i + 3} />{n}</div>)}
      </div>}
      {library > 0 && <div style={{ position: "absolute", inset: vertical ? "130px 50px 90px" : "105px 120px 60px", opacity: library, translate: `${(1 - library) * 90}px 0`, display: "grid", gridTemplateColumns: vertical ? "repeat(2,1fr)" : "repeat(3,1fr)", alignContent: "center", gap: 30 }}>
        <div style={{ position: "absolute", top: -12, width: "100%", textAlign: "center", color: "white", fontSize: 27 }}>App 资料库</div>
        {["效率与财务", "创意", "工具"].map((name, i) => <div key={name} style={{ background: "#ffffff30", borderRadius: 30, padding: 22, display: "grid", gridTemplateColumns: "1fr 1fr", justifyItems: "center", gap: 18, position: "relative", marginBottom: 45 }}>{[0, 1, 2, 3].map(j => <Icon key={j} i={(i + j) % 6} size={vertical ? 70 : 88} />)}<div style={{ position: "absolute", bottom: -34, color: "white", fontSize: 22 }}>{name}</div></div>)}
      </div>}
      {desktop > 0 && <div style={{ position: "absolute", left: 60, top: vertical ? 170 : 115, width: vertical ? 680 : 880, height: vertical ? 740 : 430, borderRadius: 18, background: "#fffffff2", boxShadow: "0 15px 35px #33405b22", opacity: desktop, padding: 30, boxSizing: "border-box" }}><Lamps k={1} /><div style={{ paddingTop: 45, color: C.ink, fontSize: vertical ? 46 : 52, fontWeight: 600 }}>写到这里，<br />刚好需要看一眼。</div>{[90, 80, 95, 65].map((w, i) => <div key={i} style={{ width: `${w}%`, height: 10, background: "#2536570f", borderRadius: 5, marginTop: 20 }} />)}</div>}
      {f >= 270 && f < 355 && <div style={{ position: "absolute", left: iconX - 38, top: iconY - 38, scale: String(mix(1, 1.15, travel)), opacity: 1 - windowIn }}><Icon i={1} /></div>}
      {windowIn > 0 && fly < 1 && <div style={{ position: "absolute", left: mix(wx, box.w / 2 - ww / 2, fly), top: mix(wy, -wh / 2, fly), width: ww, height: wh, scale: String(mix(.85 + .15 * windowIn, .035, fly)), opacity: windowIn * (1 - tw(f, 563, 575)), transformOrigin: "50% 50%", borderRadius: 20, background: "#fffdf4", boxShadow: "0 18px 50px #15244440", overflow: "hidden" }}><div style={{ padding: 15, display: "flex", alignItems: "center", gap: 45, background: "#f6f3e9", fontSize: 20 }}><Lamps k={.8} />笔记</div><div style={{ padding: 28, color: C.ink, fontSize: 25 }}><strong>采访提纲</strong>{["核对三段引文", "补上时间地点", "周五交稿"].map(t => <div key={t} style={{ marginTop: 26, display: "flex", gap: 14 }}><span style={{ border: "2px solid #d1ac55", borderRadius: 99, width: 22, height: 22 }} />{t}</div>)}</div></div>}
      {tuck > .2 && <div style={{ position: "absolute", right: 0, top: "44%", width: 13, height: 90, borderRadius: "9px 0 0 9px", background: "#ffffffa0", opacity: tuck }} />}
      <div style={{ position: "absolute", top: 0, left: "50%", translate: "-50% 0", width: mix(140, 360, notice), height: mix(28 + 15 * fly, 90, notice), borderRadius: `0 0 ${mix(12, 28, notice)}px ${mix(12, 28, notice)}px`, background: "#08090b", color: "white", display: "flex", justifyContent: "center", alignItems: "center", gap: 14, overflow: "hidden" }}>{notice > .1 ? <><Icon i={1} size={42} /><div style={{ opacity: notice, fontSize: 21 }}>笔记<small style={{ display: "block", color: "#b8bdc8", fontSize: 17 }}>内容已更新</small></div></> : fly > .8 ? <span style={{ fontSize: 16, opacity: fly }}>笔记 · 1</span> : null}</div>
      {f >= 265 && f < 350 && <Cursor x={iconX + 16} y={iconY + 18} size={44 * k} />}
    </div>
    <div style={{ position: "absolute", top: box.y + box.h + 34, left: 0, right: 0, textAlign: "center", color: C.muted, fontFamily: FONT, fontSize: 21 }}>开发版功能演示 · 启动台 / 侧拉 / 收进刘海</div>
  </Canvas>;
};
