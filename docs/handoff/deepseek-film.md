# 交给 DeepSeek：WindowShade 2 概念片

这支片子由 DeepSeek 写合成代码；主模型负责录真机画面、渲染、出片验收和配声音。
片子的一切都在 `film/ws2-concept/`：

| 文件 | 内容 |
| --- | --- |
| `BRIEF.md` | 脚本和分镜，**以它为准** |
| `DIGEST.md` | 必须遵守的规则摘要 |
| `footage/SHOTLIST.md` | 真机镜头清单 |

一次交一个包：F1 → F2 → F3。用 `deepseek_agent`，后两个包用 `deepseek_agent_continue` 接着做，让它记得前面的上下文。

---

## 总则（每个包都贴）

你在 WindowShade 仓库里做一支 80 秒的概念片，用 HyperFrames（HTML + GSAP 的确定性视频合成）。项目已经建好，在 `film/ws2-concept/`。

动手前必须读完：

1. `film/ws2-concept/BRIEF.md`：脚本、分镜、视觉语言；
2. `film/ws2-concept/DIGEST.md`：HyperFrames 契约、动效总纲、WindowShade 的弹簧、沙箱限制；
3. 能读到的话，再读 DIGEST.md 开头列的几份原文（`~/.claude/skills/` 下）。读不到就以 DIGEST 为准，不要凭印象写 HyperFrames 的 API。

目标不是“动起来”。观众在每一秒都要知道：该看哪、为什么在看、它从哪来、要去哪。做出来要像 Apple 发布会里的一段，不像幻灯片。

### 硬规则

- **刘海是主角，也是唯一的衔接。**每个章节的出口，都照 BRIEF 表里“出口衔接”那一列做：刘海变形，或者从刘海里长出下一章。不许用淡入淡出、硬切代替；全片只有片尾一次纯淡出。
- **不画假界面。**还没做的功能只用抽象图形：刘海轮廓、几何形、设备线稿、轨迹、点、环。不画 macOS 的窗口内容、按钮、设置页。第 1 章只放灰色占位块，写“真机画面：……· 秒数”，等主模型换成真录屏。
- **弹簧和刘海尺寸照 DIGEST 第三节**，不自己发明缓动。
- **文字照 BRIEF**，一屏一句，≤ 12 个字，`system-ui, sans-serif`，主句 ≥ 56 px。
- **确定性**：每帧只取决于时间；没有 `Date.now()`、没设种子的随机数、网络请求。
- **静止是设计的一部分**：BRIEF 里每段“停”的秒数都要真静止，相机也不动；片尾最后 1.5 秒完全静止。
- **每章一个子合成**：`compositions/chN-名字.html`，id 前缀 `chN-`；`index.html` 只做宿主、舞台底和屏幕轮廓。
- **写文件分块，每块 ≤ 3000 字节**；命令 ≤ 3500 字节；命令里不出现感叹号；不写 shebang。
- **只改 `film/ws2-concept/` 里的文件**；不改 App 代码，不提交，不推送，不渲染成片（渲染由主模型做）。
- 不假装成功：`npm run check` 跑不起来（沙箱拦了网络或浏览器）时，原样贴出错误，在报告里说明。

### 交付报告

```text
做了什么：（一段话）
改了哪些文件：（列表）
检查：npm run check 的结果（原样贴末尾；跑不起来就贴错误）
时间轴：每个子合成的 data-start / data-duration，与 BRIEF 对照表
每个章节边界：什么活下来、怎么变成下一章（一句话一条）
静止段：起止秒列表
不确定或没做到的：（列表）
```

---

## F1：舞台、刘海、第 0–1 章

- `index.html`：
  - 根合成 80 秒，1920×1080；
  - 舞台底 `#0B0D12`，屏幕上沿细线和屏幕区域（1600 宽，居中）；
  - 一个**全片共用的刘海元素**，放在宿主里，各章都去动它，不是每章各画一个；
  - 八个子合成槽位，时间照 BRIEF。
- 刘海形状写成几个具名状态（安静、紧凑、提醒、展开）和一个 `morphNotch(to, at, springName)` 帮手函数，用 DIGEST 的弹簧。
- `ch0-cold.html`：照 BRIEF 第 0 章。
- `ch1-windows.html`：四个灰色占位块，依次出现在屏幕区域里，写清“真机画面：A1 甩一下收进刘海 · 3.5 秒”等。另外预留四个 `<video>`，指向 `footage/A1-…mov` 到 `A4`，先加 `data-hidden`，主模型录好后去掉。
- 第 1→2 章的出口：那一排里的一格亮起，相机推进。
- 跑 `npm run check`。

## F2：第 2–4 章

- `ch2-inputs.html`：
  - 五件设备线稿（触控板、滚轮鼠标、Siri 遥控器、PS5 手柄、iPhone）用 SVG 自己画，线宽一致、只用描边，不用品牌标志；
  - 发牌式入场，一件比一件快；每件“按一下”时，焦点框右移一格，并伴随一个 pop 弹簧。
- `ch3-conduct.html`：
  - 手指轨迹用 SVG path 按时间描出来（`stroke-dashoffset`），画三声 ˇ；
  - 刘海里同步画出缩小的同一条轨迹；
  - 五拍：手指原地落、弹五次（3+2 的节奏），刘海里五个点逐拍亮起；
  - 文案照 BRIEF。
- `ch4-approve.html`：Touch ID 环被光填满，这是全片唯一一次“最贵的光”；其余时间都不发光。
- 跑 `npm run check`。

## F3：第 5–7 章与整片

- `ch5-focus.html`：
  - 红环倒数的数字用等宽数字；
  - 时间加速用一条 ease-in 的映射，2.5 秒内从 25:00 走到 0:00；
  - 窗口块飞进刘海越来越快（glide 弹簧加递减的间隔）；
  - 呼吸光环的周期 5.5 秒，只在这一段呼吸。
- `ch6-away.html`：手机线稿走远、10 → 1 的倒数压在 2.0 秒内、整屏朝刘海折进去、锁屏、回来、两点变绿、密码点填满、桌面展开。
- `ch7-seal.html`：图标依次飞进刘海，最后一个落下时刘海一弹（pop），出现字标和副标；最后 1.5 秒完全静止，底部小字“概念演示 · 部分功能开发中”。
- 整片过一遍：
  - 每个边界都有“活下来的东西”；
  - 静止段总时长占比 ≥ 25%；
  - 没有任何一屏超过一句主文字。
- 跑 `npm run check`，把报告交回。

---

## 主模型在 F3 之后做的（不交给 DeepSeek）

1. 在 Aaron 空闲时，照 `footage/SHOTLIST.md` 录 A1–A4，替换占位块。
2. 草稿渲染（720p30）：`cd film/ws2-concept && npm run render`。
3. 验收：
   - `~/.venvs/onetake/bin/python ~/.claude/skills/motion-doctrine/scripts/qc_gate.py out.mp4`；
   - `~/.venvs/onetake/bin/python ~/.claude/skills/onetake-plus/scripts/carry_flow.py out.mp4`；
   - 抽四个时间点截图看画面。
4. 按问题给 DeepSeek 带时间码的修改单（用 `deepseek_agent_continue`），最多两轮；仍不行就主模型自己改。
5. 画面定了再做声音，终渲 1080p60，交给 Aaron 看。
