# P0 动效验收结果 · 2026-10-05

## 自动化

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| MotionTokensTests | PASS | `tests/run-motion-tokens-tests.sh` |
| DuoCoreTests（含 FoldTransition 弹簧） | PASS | `tests/run-duo-tests.sh`（menu 集成断言与本轮无关） |
| LockOverlayLifecycleTests | PASS | `tests/run-lock-overlay-lifecycle-tests.sh` |
| `prototype/build.sh --check` | PASS | `build-check.log` |
| `run-glance-probe.sh --single` | PASS | `glance-single.log` |
| `run-glance-probe.sh --fold-timing` | PASS | `fold-timing.log` |

## 边界（代码层）

1. 进场内容 40%：Notch morph 主线未改（已有）。
2. 退场先字后形：Notch 仍先淡内容；时长改 `calm` / `reducedNotch`。
3. 中断：FoldTransition / Glance 从 presentation 或当前值 retarget。
4. 交接：rollMask / island / fold progress 连续。
5. 令牌：Glance `calm`/`pull`/`settle`；Fold `settle`/`calm`；auth→`calm`。
6. Reduce Motion：Glance / Notch fade → `reducedNotch`。

## 未收

Launchpad、SlideOver、Welcome、胶囊五态、`island.hug`、双时钟。
