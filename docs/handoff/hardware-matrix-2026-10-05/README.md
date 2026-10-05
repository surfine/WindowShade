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

逐案状态见 [`round2.json`](round2.json)，原始输出在 `logs/r2-*`。舞台：`cursor/silent-effect-receipts` 工作区新 `--stage`（WMO + Apple Development，二进制 **04:24:41**），TCC 跨重编保留。**同一颗二进制上重跑全部取证**，先前的 02:10:18 那颗由本组取代。

- `silent-milestone`：同一颗最终二进制 **3/3 全绿**（负载 4–94 都过）。`R01 place/cancel/target-change`、`R03 pin/unpin/collapse/expand/slideOver/leaveSlideOver/controlled-fail` 全数读完；`R04` 管線计数真机采到。
  - `pip-zero-frame` **这次真的跑到了**：`sharingType = .none` 实测挡不住 SCK（见 F3），改用探针注入零帧，应用日志出现 `pip: ended reason=frame timedOut`，画中画按设计放弃、窗口留在原处。
  - `pin` 这次是**真回执** `pin-preview: silent completion ok`（F5：原先探针抢跑把它做成假通过）；`collapse` 的 `FoldCompletion` 为 `ok=true`。
- `silent-cover`（R02）：全绿——双屏铺满、重复请求复用面板、别的 App 在前台 Esc 也能撤、退出无残留。热插拔要人手，仍 `not_run`。
- 离线：`run-silent-integration-tests --case r00..r04` 全 ok；`journal-numeric`、`silent-prep` PASS。
- 根因修复：两个静音探针都漏了 `setupStatusItem()`，收起/置顶触发的菜单重建里 `statusItem!` 解包成 nil → SIGTRAP。**产品侧 `rebuildMenu` 也改成 `guard statusItem != nil`，`Preferences.quietNotice` 改 `statusItem?.`**（F1）。
- 已知 flake（已裁决）：极重负载（load ~163）那次 `collapse` 的 `FoldCompletion` 读成 `.unknown`（`observeFoldHide(.minimized)`），窗口其实已收起；低负载与最终二进制 3/3 通过。记录在案，不动产品验证语义。
- 本轮探针侧加固（F4/F5）：`cancel`/`target-change`/`controlled-fail` 的「没动」改以 AX 位置为准并新增 `stableFrame`（CG 会被回位动画污染）；新增 `retryFreeze`，高负载对焦没及时生效时重新对焦再派发。最终二进制在负载 94 下仍 3/3。
- 仍需人手：H07/H10/H11/H13/H15/H16/H17/H18/H19；H14 BLE 证据不足以证明持有。逐案理由见 `matrix.json`，无模糊项。

