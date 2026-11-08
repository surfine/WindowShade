# 交给 DeepSeek：WindowShade 2 概念片

片子在 `film/ws2-concept/`，是一个已经装好、能渲染的 Remotion 4.0.484 工程。

| 文件 | 内容 |
| --- | --- |
| `BRIEF.md` | 脚本、五处 wow、分镜，**以它为准** |
| `DIGEST.md` | 写法规则 |
| `reference/` | 33 张镜头卡、调好参数的示例源码、审美准则、声音设计（来自 video-shotcraft，Apache 2.0） |
| `public/footage/` | 真机镜头清单 `SHOTLIST.md` 和登记表 `manifest.json` |

一次交一个包：F1 → F2 → F3 → F4 → F5。第一个包用 `deepseek_agent`，后面的用 `deepseek_agent_continue` 接着做。

## 派活参数（主模型照抄）

- `repo`：`/Users/aaron/Documents/WindowShade`（先确认概念片已经提交到 `main`）。
- `setup`：把主仓库已经装好的依赖链接进克隆：

  ```
  ["ln", "-s", "/Users/aaron/Documents/WindowShade/film/ws2-concept/node_modules", "film/ws2-concept/node_modules"]
  ```

  主仓库里没有 `node_modules` 时，主模型先在 `/Users/aaron/Documents/WindowShade/film/ws2-concept` 里跑一次 `npm install`。
- `checks`：`["npm", "--prefix", "film/ws2-concept", "run", "typecheck"]`
- 交回后，主模型在自己的检出里：
  1. `git apply --3way` 打上补丁；
  2. 用 `npx remotion still` 抽 BRIEF 里每章中段的帧，**自己看图**；
  3. 按问题写带时间码的修改单，用 continue 发回去。

## 总则（每个包都贴）

你在做 WindowShade 2 的概念片：126 秒，Remotion 工程，在 `film/ws2-concept/`。动手前必须读完：

1. `film/ws2-concept/BRIEF.md`：脚本、Aaron 点名的五处 wow、分镜；
2. `film/ws2-concept/DIGEST.md`：写法规则。最重要的是第一节：**照示例源码改，不要凭印象重写**；
3. 你这个包要用到的每张镜头卡（`reference/cards/<卡名>.md`）和它的示例源码（`reference/demos/<卡名>/*.tsx`），全文读。
4. `docs/design-drafts/README.md`：十四份可交互设计稿。画界面、刘海形状和动效之前先打开对应的稿。

目标不是“动起来”，是让人看了喊 wow。观众每一秒都要知道：该看哪、为什么在看、它从哪来、要去哪。像 Apple 发布会里的一段，不像幻灯片。

### 硬规则

- **刘海是主角，也是唯一的衔接。**全片只有一个刘海组件，章节边界照 BRIEF 的“出口”一列做；不用淡入淡出、硬切代替。
- **不画假界面。**
  - 已做的功能用 `Footage` 组件：有真机素材就放素材，没有就放占位块；
  - 没做的功能只用抽象图形：刘海、几何形、设备线稿、轨迹、点、环、光；
  - 不画 CarPlay 的界面和标志，不用 Face ID 图形。
- **照示例源码改。**每个镜头都从对应卡的示例源码复制起，“已知坑 / 命门”的参数不降档；示例里的粒子、彩纸、碎屑删掉。
- **弹簧和刘海尺寸照 DIGEST 第四节**，不自己发明缓动。
- **文字照 BRIEF**：一屏一句，≤ 12 个字。
- **确定性**：每帧只取决于帧号。
- **写文件分块，每块 ≤ 3000 字节**；命令 ≤ 3500 字节；命令里不出现感叹号；不写 shebang。
- **只改 `film/ws2-concept/src/` 里本包点名的文件**；不碰 `public/footage/manifest.json`（由主模型改）；不改 App 代码；不跑 `npm install`；不提交，不推送。
- 不假装成功：类型检查或抽帧失败就原样贴出来。

### 交付报告

```text
做了什么：（一段话）
改了哪些文件：（列表）
用了哪些镜头卡、各从哪个示例文件复制、改了什么参数：（表）
检查：npm run typecheck 的结果；抽了哪些帧、是否渲染成功
时间轴：每章的起止帧，与 BRIEF 对照
每个章节边界：什么活下来、怎么变成下一章
静止段：起止帧列表
没做到或拿不准的：（列表）
```

---

## F1：骨架、刘海、舞台、真机素材组件、第 0 章

- `src/scenes/Stage.tsx`：舞台底色、MacBook 屏幕轮廓（1600 宽居中）、全片共用的相机（缓推和几次大动作的接口）。
- `src/scenes/Notch.tsx`：全片唯一的刘海。用 DIGEST 的 `wsSpring` 在四种形状之间变形；内容区由各章传入。
  形状插值参考 `svg-shape-morph` 和 `morph-from-primitive` 的示例。
- `src/scenes/Footage.tsx`：读 `public/footage/manifest.json`，有素材用 `ClipCard`，没有就放占位块。
- `src/Film.tsx`：用 `<Series>` 按 BRIEF 的时间排九章，先放空的章节组件。
- `src/scenes/Ch0Unlock.tsx`：照 BRIEF 第 0 章做，用 `tension-camera-moves`（SlowPushIn）、`light-play-moves`（HalationBloom）、
  `fui-hud-moves`（ReticleLockOn）、`morph-from-primitive`。开盖用 3D `rotateX`，铰链在下沿。
- 抽帧：60、240、420、600、780、840。

## F2：第 1–2 章（灵动岛、窗口）

- `Ch1Island.tsx`：`spotlight-hero-card`、`svg-shape-morph`、`odometer-digit-roll`、`pill-slot-cycle`、`icon-performance-moves`（AttentionBounce）。
  真机素材 N1–N3 有了就换上。
- `Ch2Windows.tsx`：`crash-zoom-punch`、`spotlight-hero-card`、`quad-split-parallel-scenes`，真机素材都走 `Footage`。
- 抽帧：章内每 3 秒一帧。

## F3：第 3–4 章（启动台、任何输入）

- `Ch3Launchpad.tsx`：`deck-deal-flyin`（图标用 `L1-icons/` 的真图标，没有就用灰色圆角方块占位）、`type-and-filter`、`transition-travel`（SharedElementMorph）。
- `Ch4Inputs.tsx`：`list-stack-press`、`input-trigger-moves`（KeycapSmashCut 改成扳机）。六件设备线稿用 SVG 自己画：只描边，线宽一致，不用品牌标志。
  平滑滚动对比用 DIGEST 的弹簧。

## F4：第 5 章（vibe coding）

- `Ch5Conduct.tsx`：`draw-svg-trace`（三声轨迹，刘海里同步画缩小版）、`voice-waveform-live`、`glass-pill-dictation-typing`、
  `terminal-3d`（三扇终端放真机素材 T1–T3）、`ai-stream-response`、`light-play-moves`（SheenSweepRetry，全片只这一次）、`crash-zoom-punch`。
- 五拍要有 3+2 的节奏：前三拍等距，停半拍，后两拍。

## F5：第 6–8 章与整片

- `Ch6CarPlay.tsx`：`circle-match-iris`（光圈改成刘海的形状，从刘海张开）、`dataviz-landscape-open`（路线光束，蓝 `#4AA3FF`）、`tension-camera-moves`（PullBackIsolation）。
- `Ch7Focus.tsx`：`speed-ramp-freeze`。
- `Ch8Outro.tsx`：`outro-group-photo-launch`（去掉金尘和彩纸）、`logo-shrink-wordmark-lockup`（刘海收成字标）。
- 整片过一遍：每个边界都有活下来的东西；静止段 ≥ 25%；一屏不超过一句主文字；片尾 1.5 秒全静止。
- 抽帧：每章中段一帧，加 7560 帧前最后一秒的三帧。

---

## 主模型在 F5 之后做的（不交给 DeepSeek）

1. 在 Aaron 空闲时，照 `public/footage/SHOTLIST.md` 录素材，改 `manifest.json`。
2. 草稿：`npm run render:draft`。
3. 验收：
   - `~/.venvs/onetake/bin/python ~/.claude/skills/motion-doctrine/scripts/qc_gate.py out/draft.mp4`；
   - `~/.venvs/onetake/bin/python ~/.claude/skills/onetake-plus/scripts/carry_flow.py out/draft.mp4`；
   - 照 `reference/aesthetic-rules.md` 和 shotcraft 的 `final-review.md` 过一遍；
   - 看抽帧。
4. 修改单最多两轮，仍不行主模型自己改。
5. 声音照 `reference/sound-design.md`；终渲 1080p60，两版（带 BGM / 不带 BGM），交给 Aaron。
