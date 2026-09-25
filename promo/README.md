# WindowShade 宣传片

62 秒，1920 × 1080，60 fps。全片是动画，不是录屏；界面按官网插画的尺寸画（14 pt 信号灯、23 pt 间距、36 pt 标题栏、约 18 pt 圆角），手势的跟手比例（0.55）、提示浮窗（290 × 63 pt）和动作名称都照应用本身来。

## 结构

120 bpm，一小节 2 秒，每个镜头切在拍子上。画面和声音读同一份提示表 [`src/timeline.ts`](src/timeline.ts)：改一个时间点，打字声、音效、音乐段落跟着走。

| 小节 | 镜头 | 说的事 |
| --- | --- | --- |
| 0–3 | Opener | 窗口一多，桌面就满了。先别急着关。光标收成一点，拉长成卷帘条 |
| 4–7 | Ways | 关掉、最小化、收起，只有收起不用回头找 |
| 8–10 | DoubleClick | 双击标题栏收起，再双击原样回来 |
| 11–13 | History | 1994、1997、2001、2026 四个年代的标题栏 |
| 14–16 | Glance | 停在卷帘条上，看一眼 |
| 17–24 | Gestures | 标题栏手势：收起、展开、铺满、半屏、往回拉取消、鼠标滚三格 |
| 25–27 | More | 置顶、带到每张桌面、窗口浏览 |
| 28–30 | End | 图标、名字、官网地址 |

## 命令

```bash
npm i
npm run audio      # 由 scripts/audio.ts 合成 public/soundtrack.wav（音乐和音效都是代码生成的）
npm run dev        # Remotion Studio 预览，每个镜头也单独注册在 Scenes 文件夹里
npm run render     # 合成音轨并输出 out/windowshade-promo.mp4
node scripts/stills.mjs <目录> 120 900 2400   # 抽几帧看构图
```

文案按 [`docs/copy-guide.md`](../docs/copy-guide.md) 写：动作叫“收起窗口 / 展开窗口”，收起后留下的那条叫“卷帘条”，手势动作名和应用里的提示浮窗一致。
