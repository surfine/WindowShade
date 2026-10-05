# 做这支片子之前必须知道的

这是给执行模型的摘要。能读到原文就读原文：

| 原文 | 讲什么 |
| --- | --- |
| `~/.claude/skills/video-shotcraft/SKILL.md`、`references/pipeline.md` | 本片走的路线（自主自由创作） |
| `~/.claude/skills/remotion-markup/SKILL.md` | Remotion 写法 |
| `~/.claude/skills/motion-doctrine/references/doctrine.md` §1–§10 | 本机动效总纲 |
| `~/.claude/skills/emil-design-eng/SKILL.md`、`~/.claude/skills/apple-design/SKILL.md` | 动效判断、Apple 流体界面 |
| [`docs/design-drafts/README.md`](../../docs/design-drafts/README.md) | 2026-10-04 的十四份可交互画面稿。画界面和刘海动效之前先打开 |

本目录 `reference/` 里放着本片要用的 33 张镜头卡、它们调好参数的示例源码、审美准则和声音设计，都是从 video-shotcraft 复制的
（Apache 2.0，见 `reference/LICENSE-video-shotcraft`）。

## 一、最重要的一条：照示例源码改，不要凭印象重写

video-shotcraft 的原话：配方卡给的是语义和参数表，**准确的 demo 源码才是调校过的参数真相**，包括缓动、时值配比、摘罩时机、已知坑的写法。
凭卡名和理解新写，等于放弃全部调校积累。

所以每做一个镜头：

1. 读 `reference/cards/<卡名>.md` 全文，尤其“已知坑 / 命门”；
2. 读 `reference/demos/<卡名>/` 里对应的 `.tsx` 全文；
3. 把它复制到 `src/scenes/`，再改成本片的内容：换素材、换颜色、换尺寸、换文字。
   - **卡上标“已知坑 / 命门”的参数不许降档**；
   - 时值按本片的帧率（60 fps）等比换算；
   - 示例里 import 的 `_fixtures`、`_textures` 是它的假场景件，改成本片的刘海、舞台和素材组件，不要把假 UI 搬进来。

## 二、Remotion 写法（不遵守就渲染错）

- 动画只用 `useCurrentFrame()` + `interpolate()` / `spring()`。**CSS transition、CSS animation、Tailwind 动画类都渲染不出来。**
- 每一帧只取决于帧号：不用 `Date.now()`、不用没设种子的 `Math.random()`（用 `src/lib/helpers/rand.ts` 的 mulberry32）、不联网取数据。
- 素材放 `public/`，用 `staticFile()` 引用。视频用 `OffthreadVideo`，或 `src/lib/ClipCard.tsx`（它会把短素材无缝续播）。
- 优先用 `scale`、`translate`、`rotate` 这几个 CSS 属性，不要把它们拼进一个 `transform` 字符串。
- 章节用 `<Series>` 或带 `from` / `durationInFrames` 的 `<Sequence>` 排；所有时间写成 `秒 * fps`。
- `src/lib/` 里有可直接用的组件：
  - `PageCam`：2.5D 页面相机，所有“真实页面”镜头的地基；
  - `ClipCard`：把视频素材包成卡片主角；
  - `DigitRoll`、`FlashCut`、`Caption`；
  - `helpers/`：rand、shake、camera、motion。
- 检查命令：
  - 类型：`npm run typecheck`；
  - 抽一帧：`npx remotion still src/index.ts WS2Concept out/f.png --frame=<帧号>`；
  - 草稿：`npm run render:draft`。

## 三、动效总纲最要紧的

- **不像幻灯片的四条**：
  1. 镜头长短要拉开，留真静止；
  2. 拍与拍之间要“长出来”，不是替换；
  3. 要有相机；
  4. 每镜一个主角。
- **衔接**：每个章节边界写明“什么活下来、并且在动”。本片固定用刘海变形。
- **节奏**：静止帧占 25% 以上；落位后稳 30–45 帧再走；不为凑数给静物加漂浮。
- **主角与光**：主角高度 ≥ 内容区的 1/3；配角不发光；一帧里最多一处重点光；**不用粒子、彩纸、碎屑**（示例里有的，删掉）。
- **文字**：一屏一句、≤ 12 个字；要读的字有效字高 ≥ 56 px。

## 四、WindowShade 的弹簧和刘海

弹簧用“响应时间 / 阻尼比”表示：

| 名字 | 响应 / 阻尼 | 用在 |
| --- | --- | --- |
| calm | 0.34 / 1.0 | 回到安静 |
| settle | 0.38 / 1.0 | 落位、紧凑 |
| expand | 0.40 / 0.92 | 展开 |
| bloom | 0.42 / 0.84 | 提醒冒出来 |
| pop | 0.30 / 0.75 | 拍点、对勾 |
| glide | 0.42 / 0.88 | 飞入飞出 |

在 Remotion 里写成帧号的函数：

```ts
// 返回 0→1（阻尼 < 1 时会略微过冲）。startFrame 起算，fps=60。
export function wsSpring(frame: number, startFrame: number, response: number, damping: number, fps = 60) {
  const t = Math.max(0, (frame - startFrame) / fps);
  const w = (2 * Math.PI) / response;
  if (damping >= 1) return 1 - (1 + w * t) * Math.exp(-w * t);
  const wd = w * Math.sqrt(1 - damping * damping);
  return 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + ((damping * w) / wd) * Math.sin(wd * t));
}
```

刘海尺寸（布局示意，以约 1600 宽屏幕为准；非硬件测量）：

| 状态 | 宽 × 高 | 下圆角 | 备注 |
| --- | --- | --- | --- |
| 安静 | 195 × 58 | 18 | 贴硬件 |
| 紧凑（岛） | 480 × 58 | 18 | 左右耳读成一件事 |
| 提醒 | 545 × 102 | 28 | 短下鼓；先形后字 |
| 展开（半岛） | 矮 ≈300×130；高 ≈420×176 起 | 40 | 避开临界高度；顶边贴传感器，无额头 |

半岛三规则：① 顶边贴传感器；② 紧凑与展开相对位置连续；③ 该静则静（ch1 勿空转变形）。界面文案不叫灵动岛/半岛。

刘海始终贴在屏幕上沿正中。全片只有一个刘海组件（`src/scenes/Notch.tsx`），各章传入形状和内容，不各画各的。

## 五、真机画面怎么接

`public/footage/manifest.json` 是一张表：文件名 → 是否已录。组件 `src/scenes/Footage.tsx` 读这张表：

- 有素材：用 `ClipCard` 放；
- 没有：放占位块（深灰圆角卡片，中间一行“真机画面：A1 甩进刘海 · 2.5 秒”）。

主模型录好后只改这张表，代码不用动。镜头清单在 `public/footage/SHOTLIST.md`。

## 六、沙箱里的限制（DeepSeek Harness 实测）

- 每条命令 ≤ 3500 字节。**写文件分块，每块 ≤ 3000 字节**：先写骨架，再一段段追加。
- 命令里不要出现感叹号字符（引号里也不行）；文件第一行不要写 shebang。
- 只能写进本仓库的克隆。`node_modules` 由主模型用 setup 链接进来；`npm install` 会联网，不要跑。
- 你看不到图片：`remotion still` 只能证明那一帧渲染不崩，好不好看由主模型看图判断。
