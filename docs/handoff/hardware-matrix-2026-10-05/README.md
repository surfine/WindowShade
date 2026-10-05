# 真机矩阵证据 · 2026-10-05

对照整改包 `03-hardware-matrix.json`（H01–H20）。机器证据在本目录；**不要把逻辑测试写成 hardware_pass**。

| 文件 | 内容 |
| --- | --- |
| `environment.txt` | commit、系统、双屏、相机/蓝牙摘要（UUID 已脱敏） |
| `matrix.json` | 逐案 status / evidence / result |
| `logs/` | 原始命令输出 |

本轮要点：

- 舞台：当日晚间完整 `--stage` WMO + `Apple Development` 签名成功（`logs/stage-build-rescue-fix2.log`，二进制 18:55）。
- 已通过：`silent-milestone`（含授权相机 head 路径）、`glance --single`、`fold-timing`、双屏遮罩观察、LEASE 15/0、camera-choice 逻辑、静音 integration。
- 根因修复：`WindowShade.rescue` 后台扫描踩 `@MainActor` 执行期断言 → SIGTRAP；扫描改 nonisolated + 主线程快照/夹紧。
- 仍缺口：H08 未做故意断流；H09–H13 夹具不足；BLE 不足以证明持有；120Hz/`H20` not_run。

## 第二轮 · 2026-10-06（带 R00–R04 的新构建）

逐案状态见 [`round2.json`](round2.json)，原始输出在 `logs/r2-*`。舞台：`cursor/silent-effect-receipts@6a51b9cfb1` 工作区新 `--stage`（WMO + Apple Development，二进制 02:10:18），TCC 跨重编保留。

- `silent-milestone`：4 次跑，3 次全绿；`R01 place/cancel/target-change`、`R03 pin/unpin/collapse/expand/slideOver/leaveSlideOver/controlled-fail` 都读到 `lastResult.isCompleted`，`R04` 管線計數真机採到（`capture=193 throttle=142 vision=49 delivered=49`）。
- `silent-cover`（R02）：全绿——双屏铺满、重复请求复用面板、别的 App 在前台 Esc 也能撤、退出无残留。热插拔要人手，仍 `not_run`。
- 离线：`run-silent-integration-tests --case r00..r04` 全 ok；`journal-numeric`、`silent-prep` PASS。
- 根因修复（探针侧）：两个静音探针都漏了 `setupStatusItem()`，收起/置顶触发的菜单重建里 `statusItem!` 解包成 nil → SIGTRAP。产品侧 `rebuildMenu` 仍是强解包，未动。
- 已知 flake（待裁）：极重负载（load ~163）那次 `collapse` 的 `FoldCompletion` 读成 `.unknown`（`observeFoldHide(.minimized)`），窗口其实已收起，R03 的 3 秒看护超时给出 `收起没有确认`；低负载 3/3 通过。`FoldVerifier` 自身预算约 0.95 秒，不是验证太慢。
