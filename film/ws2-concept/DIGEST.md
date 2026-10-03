# 做这支片子之前必须知道的（摘要）

这份是给执行模型的摘要。能读到原文时，优先读原文：

| 原文 | 讲什么 |
| --- | --- |
| `~/.claude/skills/hyperframes-core/SKILL.md` | 合成契约 |
| `~/.claude/skills/hyperframes-animation/SKILL.md` | 动画规则与蓝图 |
| `~/.claude/skills/general-video/SKILL.md` | 本片走的路线 |
| `~/.claude/skills/motion-doctrine/references/doctrine.md` §1–§10 | 本机的动效总纲 |
| `~/.claude/skills/emil-design-eng/SKILL.md` | 动效判断 |
| `~/.claude/skills/apple-design/SKILL.md` | Apple 的流体界面 |

本目录的 `AGENTS.md` 是 HyperFrames 自带的说明。

## 一、HyperFrames 合成契约（不遵守就渲染失败）

1. 根节点 `<div id="root" data-composition-id="main" data-start="0" data-duration="80" data-width="1920" data-height="1080">` 直接放在 `<body>` 里。
   `#root` 用 `width:100%; height:100%`，不写死像素。
2. **每个合成只有一条** `gsap.timeline({ paused: true })`，挂在 `window.__timelines["<合成 id>"]` 上，key 等于 `data-composition-id`。
3. 有时间的元素加 `class="clip"`，以及 `data-start`、`data-duration`、`data-track-index`。**不许对 `.clip` 本身做 `autoAlpha`、`visibility`、`display` 动画**，要动它的子元素。
4. 不许在 CSS 里给一个元素写初始 `transform`，又用 GSAP 动同一个属性。初始状态写在 `gsap.fromTo` 里。居中用 flex 或 `inset`，不用 `translate(-50%,-50%)`。
5. 分章用子合成：`compositions/ch0-cold.html` …… `compositions/ch7-seal.html`。
   - 每个文件把根包在 `<template>` 里；
   - `<style>` 和 `<script>` 放在 `<template>` **里面**；
   - 宿主槽位、template、timeline 的 key 用同一个 id（例如 `ch3`）；
   - 所有 id 加章节前缀（`ch3-notch`），保证在拼好的整页里唯一。
6. **确定性**：不用 `Date.now()`、不用没设种子的 `Math.random()`、不联网取数据、不读输入状态。每一帧都只取决于时间 t。随机数用固定种子的小函数。
7. `<video>` 不能有 `crossorigin`；`<video data-start>` 的祖先不能再有 `data-start`；每个 `<audio>` 要有 `id`。
8. 正文里不用 `<br>`。字体只用 `system-ui, sans-serif` 这种通用族名；写具体字体名会被 lint 报错。
9. 检查：`npm run check`（含 lint）。lint 有 error 时，后面的版面和对比度检查等于没跑，要先清 error。

## 二、动效总纲里最要紧的（motion-doctrine）

- **不像幻灯片的四条**：
  1. 镜头长短要拉开，留真静止；
  2. 拍与拍之间要“长出来”，不是替换；
  3. 要有相机；
  4. 每镜一个主角。
- **衔接**：每个章节边界都写明“什么活下来、并且在动”。本片固定用一种：**刘海变形**，刘海就是那个活下来的容器。淡入淡出不算衔接；全片只允许片尾那一次纯淡出。
- **节奏**：静止帧要占到 25% 以上，至少一段 ≥ 1 秒的真静止；落位后稳 30–45 帧再走；片尾停 ≥ 1.5 秒。不为凑数给静物加漂浮。
- **主角与光**：主角高度 ≥ 内容区的 1/3；配角不发光；一帧里最多一处重点光；粒子、彩纸、碎屑一律不用。
- **文字**：一屏一句、≤ 12 个字；要读的字有效字高 ≥ 56 px；读不清就删。
- **相机**：每章 scale 1.00 → 1.04 的极缓推近，末键落在章节结束之后；静止段必须真静止（相机也不动）。
- **真画面**：产品界面必须是真实运行的画面。还没做出来的功能只能用抽象图形表达，不能画假界面。

## 三、WindowShade 的动效记号（照这个写，不自己发明）

弹簧用“响应时间 / 阻尼比”表示：

| 名字 | 响应 / 阻尼 | 用在 |
| --- | --- | --- |
| calm | 0.34 / 1.0 | 刘海回到安静 |
| settle | 0.38 / 1.0 | 落位、紧凑 |
| expand | 0.40 / 0.92 | 刘海展开成面板 |
| bloom | 0.42 / 0.84 | 提醒冒出来 |
| pop | 0.30 / 0.75 | 拍点、对勾 |
| glide | 0.42 / 0.88 | 窗口飞入飞出 |

“减少动态效果”时用 0.25 / 1.0。淡入 0.18 秒，淡出 0.10 秒。

GSAP 里这样用（时长取响应时间的 1.6 倍，足够停稳）：

```js
function spring(response, damping) {
  const w = 2 * Math.PI / response, dur = response * 1.6;
  const f = damping >= 1
    ? t => 1 - (1 + w * t) * Math.exp(-w * t)
    : t => { const wd = w * Math.sqrt(1 - damping * damping);
             return 1 - Math.exp(-damping * w * t) * (Math.cos(wd * t) + damping * w / wd * Math.sin(wd * t)); };
  return { duration: dur, ease: p => p >= 1 ? 1 : f(p * dur) };
}
// 用法：const s = spring(0.40, 0.92); tl.to("#ch1-notch", { width: 840, height: 220, duration: s.duration, ease: s.ease }, 6.0);
```

刘海的几何（1920 宽画面里，屏幕内宽按 1600 算）：

- 安静：宽 195、高 58、下圆角 18；
- 紧凑：宽 480、高 58；
- 提醒：宽 545、高 102；
- 展开：宽 740–860、高 200–300、下圆角 40。

刘海始终在屏幕上沿正中，贴边。

## 四、沙箱里的限制（DeepSeek Harness 实测）

- 每条命令 ≤ 3500 字节；**写文件分块，每块 ≤ 3000 字节**（先写骨架，再一段段追加）。
- 命令里不要出现感叹号字符（引号里也不行，会卡死）；文件第一行不要写 `#` 加感叹号开头的 shebang。
- 只能写进本仓库的克隆。联网、拉 CDN、开 Chrome 可能被拦：`npm run check` 跑不起来时，照实报告，交给主模型跑。
