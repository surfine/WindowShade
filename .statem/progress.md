# 进度（每个状态边界更新一次）

契约摘要:
当前交付物身份（路径 / 服务）:
试过的命令:
跑过的检查与结果:
残余风险:
下一步:
# 进展

## solve（进行中）

- 四份材料已全部并进 main：part1 纯核与合同、part2 协调器/S1/T2、part3 菜单与配置事务等、
  part4 配对加密与审批 review。归档在 docs/handoff/chatgpt-review-2/part1…part4。
- 本轮在 Mac 上真编译、真跑，修掉只有真机才暴露的问题：CryptoKit 切片下标（配对 TLV 一编码就崩）、
  SDK 27 手柄扳机方法名、协调器接上后 cancelLease 缺分支、S1 的隔离错误、根级 /var 符号链接、
  FileHandle 重复关闭、wsSpring 元组展开。
- 新增验证入口：tests/run-part4-core-tests.sh（72/188）、tests/run-mac-crypto-tests.sh、
  tests/run-privacy-registry-check.sh（458 点）、tests/run-privacy-page-sync.sh、
  tests/NotchLeaseHostTests.swift（8 场景）。
- 设置里新增「隐私」一栏（由登记表生成，private 值默认隐藏）；番茄钟闭环（预设/快捷键/工具/卡片/负一屏）；
  T3 窗口执行器按所有权收据收窗放回，休息时点一下刘海可放回。

## 下一步

- contract_check：把契约里的对照检查全跑一遍并留证。
- 未接项（按第四份 REMAINING）：owned Codex 进程与允许路径、首次 Pair-Setup/Keychain、
  HID/鼠标/手柄生产桥、会话与指挥 live 订阅、系统锁后端；真机证据仍需 Aaron 在场。

## contract_check 证据（2026-10-03 夜）

| 检查 | 结果 |
| --- | --- |
| `cd prototype && ./build.sh --check` | 退出 0，`编译验证通过` |
| `bash tests/run-appkit-tests.sh all` | 退出 0，八套全过（含 NotchLeaseHostTests 8 场景 0 失败） |
| `bash tests/run-part4-core-tests.sh` | `SCENARIOS=72 ASSERTIONS=188 FAILURES=0` |
| `bash tests/run-mac-crypto-tests.sh` | CryptoKit 向量、M1–M4、双向记录、重放关闭会话全过 |
| `python3 tests/crypto-reference.py` | 18 例 OK |
| `python3 tests/check-approval-schema.py` | PASS（validator=builtin-constraints，1 条合成响应） |
| `bash tests/run-privacy-registry-check.sh` | `PASS privacy-registry: 458 lexical sites` |
| `bash tests/run-privacy-page-sync.sh` | `PASS privacy-page: 生成的数据源与登记表一致` |
| contracts / part2 / part3 与第一份十二个包 | 全部 PASS（9/24、22/86、55/147、121/334） |

提交：`c9bb354`…`faa4015` 共 9 笔（含第四份合并、隐私页、T3 执行器）。

## self_review（已完成）

- 契约与产物对照：四份材料都在 main 里，新增入口都有测试；未接项按第四份 REMAINING 记账，没有写成完成。
- 证据新鲜度：发现最后一次清理提交在编译检查之后，已在当前 HEAD（`bbe298d`）重跑 `build.sh --check` 通过。
- 之后又做了一步范围明确的收口：把「权限与启动」并进「隐私」一栏（`7c86e89`），
  重新跑了 `build.sh --check` 与八套 AppKit 回归，并看了隐私页浅深色截图（`2 块屏 / 未锁屏 / 未读取 / 已隐藏`）。
- 残余风险：真实窗口收窗/放回、真机探针、配对与 Keychain、owned Codex 允许路径、设备桥、live 订阅都未验。
