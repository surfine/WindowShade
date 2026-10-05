# P0 动效边界审计 · 2026-10-05

尺子：位移写 `MotionSpring` 令牌名；边界有交接锚点；可打断；落定后真静止。不改令牌数字。

## Glance（看一眼）

| 边界 | 改前 | 令牌目标 | 交接锚点 |
| --- | --- | --- | --- |
| rollDown | Bézier `(0.23,1,0.32,1)` × 0.18s | `calm` | `rollMask` 高度连续 |
| setRoll（跟手） | 无动画 | 保持无动画 | 同一 mask |
| settleRoll | Bézier × 0.18×剩余 | `pull`（松手带动量） | 从当前高度 retarget |
| grow | `CASpring` 0.3/0（未写令牌名） | `settle` | 卡片 transform 从缩略图长出 |
| shrink | Bézier `(0.65,0,0.35,1)` × 0.16s | `calm`（退场不回弹） | 同一 transform 缩回 |
| rollUp | Bézier × 0.14s | `calm` | mask 高度 |
| Reduce Motion | fade 0.12 / 0.10 | `reducedNotch` 只淡 | 位置不动 |

## Fold（合盖进度）

| 边界 | 改前 | 令牌目标 | 交接锚点 |
| --- | --- | --- | --- |
| request → folded | duration 0.28×路程 × smoothstep | `settle` 解析弹簧 | `FoldTransition.value` 从当前值接 |
| request → open | duration 0.34×路程 × smoothstep | `calm` 解析弹簧 | 同上，反转不归零 |
| 重复同目标 | 不重启 | 保持 | — |
| Lid 进度映射 | `FoldDriver.ease`（角度） | 本轮不动（传感器映射，非 UI 位移） | — |

## Notch（周边；morph 主线已对齐则不动）

| 边界 | 改前 | 令牌目标 | 交接锚点 |
| --- | --- | --- | --- |
| morph 主弹簧 | 已接 expand/calm/bloom/catch… | 保持 | 岛外框 |
| auth spring | 硬编 0.28 / 0.02 | `calm`（解锁短、不回弹） | 岛 |
| 内容退场 fade | 0.18 | `calm.response`（只淡） | 内容层先淡再收形 |
| companion opacity | 0.10 / 0.18 | `calm` / `reducedNotch` | companion 层 |
| NSAnimationContext fade | 0.18 | `calm` / `reducedNotch` | — |
| hover dwell | 0.12（已对齐） | `dwell.hoverExpand` 0.12 | — |
| 格子 tile dwell | 0.2 | 对齐 0.12 | — |

## 本轮不做

Launchpad 曲线、胶囊五态、`island.hug`、alert 2.6 vs remind 4s、SlideOver/Welcome（P1 记账）。
