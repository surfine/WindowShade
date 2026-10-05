# 动效验收结果 · 2026-10-05（含 P2 收口）

## 自动化

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| MotionTokensTests | PASS | `tests/run-motion-tokens-tests.sh` |
| SlideOverMotionTests | PASS | `tests/run-slide-over-tests.sh` |
| LaunchpadViewTests | PASS | `tests/run-launchpad-view-tests.sh` |
| PaperSurfaceTests | PASS | `tests/run-paper-tests.sh` |
| Part2CoreTests（LEASE09 → alert.hold） | PASS | `tests/run-part2-core-tests.sh` |
| DisplayShapeTests（capsuleRadius） | PASS | `tests/run-display-shape-tests.sh` |
| `prototype/build.sh --check` | PASS | `build-check.log` |

## 本轮收口

1. 胶囊五态 / `island.hug`：真刘海 hug；无刘海 `capsuleRadius` + 展开/提醒 `allCorners`。
2. 双时钟：协调器 `remind` = `MotionHold.alert` 2.6s。
3. 启动台玻璃：控件层系统玻璃；内容层磨砂保留（§6-8）。
4. 编辑晃动 → `pop` 时长；番茄环保持线性；焦点拉出 `settle`；分屏吸附 `FluidMotion`+`settle`。

## 仍并陈

私有接口读时机稿上的 2s/1.5s vs §3.4；减少动态效果稿上 0.18 vs `reduced` 令牌。
