# 动效验收结果 · 2026-10-05

## 自动化

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| MotionTokensTests | PASS | `tests/run-motion-tokens-tests.sh` |
| SlideOverMotionTests | PASS | `tests/run-slide-over-tests.sh` |
| LaunchpadViewTests | PASS | `tests/run-launchpad-view-tests.sh` |
| PaperSurfaceTests | PASS | `tests/run-paper-tests.sh` |
| DuoCoreTests（含 FoldTransition 弹簧） | PASS | `tests/run-duo-tests.sh`（menu 集成断言与本轮无关） |
| LockOverlayLifecycleTests | PASS | `tests/run-lock-overlay-lifecycle-tests.sh` |
| `prototype/build.sh --check` | PASS | `build-check.log` |
| `run-glance-probe.sh --single` | PASS（P0） | `glance-single.log` |
| `run-glance-probe.sh --fold-timing` | PASS（P0） | `fold-timing.log` |

## 边界（代码层）

1. 进场内容 40%：Notch morph 主线未改（已有）。
2. 退场先字后形：Notch 仍先淡内容；时长改 `calm` / `reducedNotch`。
3. 中断：FoldTransition / Glance 从 presentation 或当前值 retarget。
4. 交接：rollMask / island / fold progress 连续。
5. 令牌：Glance `calm`/`pull`/`settle`；Fold `settle`/`calm`；auth→`calm`。
6. Reduce Motion：只淡走 `fadeDuration` / `reducedNotch`。
7. SlideOver 平移 `glide`/`settle`；Launchpad 槽位 `expand`、落地 `glide`、开文件夹 `flyOut`。
8. 其余淡入淡出去掉命名 Bézier，时长走 `fadeDuration`。

## 未收

Launchpad 玻璃、胶囊五态、`island.hug`、双时钟；编辑晃动、番茄钟线性、焦点拉出 0.065、分屏吸附仍用 cubic 插值。
