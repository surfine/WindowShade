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

逐案状态见 [`round2.json`](round2.json)，原始输出在 `logs/r2-*`。舞台：`cursor/silent-effect-receipts` 工作区 `--stage`（WMO + Apple Development），最终一颗二进制 **07:14:41**，`sha256 128b76bd…`，TCC 跨重编保留。**同一颗二进制上重跑全部取证**；02:10:18、04:24:41、06:47:43 三颗都已由本组取代。

- `silent-milestone`：同一颗最终二进制 **9/9 全绿**。`R01 place/cancel/target-change`、`R03 pin/unpin/collapse/expand/slideOver/leaveSlideOver/controlled-fail` 全数读完；`R04` 管線计数真机采到。
  - `pip-zero-frame` **这次真的跑到了**：`sharingType = .none` 实测挡不住 SCK（见 F3），改用探针注入零帧，应用日志出现 `pip: ended reason=frame timedOut`，画中画按设计放弃、窗口留在原处。
  - `pin` 这次是**真回执** `pin-preview: silent completion ok`（F5）；`collapse` 的 `FoldCompletion` 为 `ok=true`。
- `silent-cover`（R02）：全绿——双屏铺满、重复请求复用面板、别的 App 在前台 Esc 也能撤、退出无残留。热插拔要人手，仍 `not_run`。
- 离线：`run-silent-integration-tests --case r00..r04` 全 ok；`journal-numeric`、`silent-prep` PASS；`build.sh --check` 退出 0。
- 产品侧修复（F5）：`window.pin` 原先「会话一装上」就算完成回执——装载不等于首帧到、失败了也不撤回，一笔没做成的置顶会报「已完成」。现在只在 `pinnedPreviewController.lastSilentCompletion` 的真回执（`id` 对得上、`at` 在本次确认之后、`ok=true`）到达后才算完成，探针同步改等 `lastResult` 落定再核对回执与会话三者一致。
- 产品侧修复（F1）：两个静音探针都漏了 `setupStatusItem()`，收起/置顶触发的菜单重建里 `statusItem!` 解包成 nil → SIGTRAP。**产品侧 `rebuildMenu` 也改成 `guard statusItem != nil`，`Preferences.quietNotice` 改 `statusItem?.`**。
- 探针侧加固（F4/F8）：`cancel`/`target-change`/`controlled-fail` 的「没动」改以 AX 位置为准并新增 `stableFrame`（CG 会被回位动画污染）；新增 `retryFreeze`，高负载对焦没及时生效时重新对焦再派发。`leaveSlideOver` 原先只查「有没有提案」，冻结落到另一扇临时窗口就假失败（`alreadySatisfied`）并漏收一个置顶会话——补上 `prepare + retryFreeze` 后 9/9 全绿。修前修后的样本都在 `logs/r2-*`，可复查。
- 已知 flake（已裁决，F2）：极重负载（load ~163）那次 `collapse` 的 `FoldCompletion` 读成 `.unknown`（`observeFoldHide(.minimized)`），窗口其实已收起。记录在案，不动产品验证语义。
- **待裁决（F7，本轮未动产品语义）**：收起若真的走了 private SLS 离屏停车，隐藏验证读的是 AX 几何，而 SkyLight 的移动不更新 AX 属性 → 判成「还看得见」→ 整支 fold 回滚（应用日志 `hide not yet verified ... hide=privateOffscreen` 紧接 `silent fold completion ok=false`）。本机多数时候 `private SLS ... did not park` 会退回 `minimized`，那条路验证是对的，所以难得复现；06:39 那颗二进制上真的停车成功时整支回滚。方向是 `privateOffscreen` 改读窗口服务器几何或等停车与 AX 同步，属产品验证语义，等裁决。
- 仍需人手：H07/H10/H11/H13/H15/H16/H17/H18/H19；H14 BLE 证据不足以证明持有。逐案理由见 `matrix.json`，无模糊项。

