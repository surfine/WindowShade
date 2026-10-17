# WindowShade 2 · 新片（ws2-next）草片

分镜：`docs/design-drafts/WindowShade 2 宣传片 分镜.html`（D1–D5 已定）。拆解：`TEARDOWN.md`。

## 做法

- 一条 30 fps、1440 帧的时间线（`src/plan.ts`）。窗口、指针、启动台是时间的闭式函数；相机与刘海是逐帧积分的弹簧，换目标时保留速度，结果缓存，确定性。
- 一镜到底：three.js 画 15 英寸 Air（与片尾的 Neo）的 glb；整块屏幕是一层网页，用同一个相机算出的投影矩阵贴到显示面上（`src/rig.ts`）。正对屏幕时是仿射矩阵，文字按最终尺寸栅格化。
- 相机跟主体：落后 0.1 秒追窗口、拖动时提前到落点、点头那一拍相机自己点头；`RESTS` 里的段落相机钉死，一个像素不动。
- 刘海：本机 Mac17,4 实测（762.38–947.62，深 33.26，底角沿边 15.07，肩沿边 7.12），ContinuousCorner 曲线，任何形状都保留肩。窗口被吞进的那一刻，刘海按窗口到达速度鼓起（`COVER`）。
- 屏幕里的窗口全是真实 WindowShade 截图（`docs/visual-qa/settings`、`docs/visual-qa/window-browser`）。

## 出片

```sh
npm install
~/.venvs/mg-styles/bin/python scripts/score.py        # 两版混音，见 AUDIO.md
npx remotion render src/index.ts WS2Next out/ws2-next-video.mp4 --codec=h264 --hardware-acceleration=required --video-bitrate=16M --gl=angle --muted
ffmpeg -i out/ws2-next-video.mp4 -i audio/mix-a-tonight.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest out/ws2-next-draft-a-tonight.mp4
ffmpeg -i out/ws2-next-video.mp4 -i audio/mix-b-original.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest out/ws2-next-draft-b-original.mp4
```

## 还是占位的

见交付报告；摘要：菜单栏是画的；启动台、落点小岛、实时活动、离开就锁、刷脸验证条、读唇、点头的刘海界面是按设计稿语言画的，不是产品录屏；启动台图标是 ws2-opus 里的 Apple 图标图片；Neo 屏幕是静态拼图。
需要现场录屏才能换成真画面的拍：B3 刘海一排卡片、B4 启动台、B5 落点小岛、B6 实时活动、B7 离开就锁。

## 草片验收（2026-10-18，1080p30，48.000 s）

| 项 | A · Tonight | B · 原创 | 线 |
| --- | --- | --- | --- |
| carry_flow | 1.00，15 个边界全承接，裸切 0，硬切 0 | 同一画面 | ≥ 0.80，裸切 0 |
| 最长静止（片尾外） | 2.60 s（37.40 s 起） | 同 | ≤ 3.0 s |
| 末帧停留 | 5.90 s | 同 | ≥ 1.0 s |
| 响度 / 真峰 | −14.1 LUFS / −3.2 dBFS | −14.0 LUFS / −3.2 dBFS | −14 ±1 / ≤ −1 |
| qc_gate 总判 | FAIL：只差 verify_promo 的 audio 腿要求 ≥ 15% 的帧是静音（实测 1.2% / 1.6%） | 同 | 见下 |

那条「15% 静音」是 onetake 短片的口径，和配乐不断的宣传片冲突（Aaron 之前判过「声音断断续续」），这次没有为它加静音。原始输出在 `qa/`，6 帧联系表 `qa/contact-6.jpg`。
