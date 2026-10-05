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
