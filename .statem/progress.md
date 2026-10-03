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

## 第五、六份接入（当前 run：20261003-p56）

- 合并第五份（进程/身份/窗口中间层）与第六份（仲裁修正 + Scope/Selection/Budget/诊断尾部）：
  提交 `7c89d6d`；原件归档 `docs/handoff/chatgpt-review-2/part5|part6`。
- 工单 01：单岛仍是 `NotchLeaseHub`；`show` 改为先 acquire（可带 replacing）→ 挂载 → `isCurrent` 复核，
  不预先 dismiss；`beginAuthorization` 同样复核新租约。
- 工单 02：`WS2OwnedLaunchController` + 设置页四项；**真机阶段一通过**（提交 `6e9428f`）：
  codex-cli 0.153.0，2 个模型，thread/turn/completed/stop，`approvalsSeen=0`。
- 工单 06：`FoldCompletion.awaitFold(id:)` + `WS2FocusWindowPort`（逐窗收起/放回、先登记等待器、
  身份与 revision 复核），`admitted=false` 之前只计时（提交 `473ee55`）。
- 工单 07：`run-part6-archive-integrity.sh`（94 文件哈希全对）、`run-part6-readiness.sh`（如实 BLOCKED）。
- 工单 05：SRP 隔离探针 resolve + Mac Swift 6 编译通过，许可核过（证据在 part5-mac-probe/）；
  固定向量互测、实例工厂、原生 Remote 互操作仍未做 → 配对未准入。

### 真机发现（都属“只在 Mac 才暴露”）

1. CryptoKit 的 Ed25519 签名带随机量：不能拿自己产出的 M6 与确定性向量逐字节比；
   验收改为「对端能验证」+ 两次签名必须不同。
2. 按线程屏蔽 SIGPIPE 在多线程进程里挡不住：`WS2DuplexProcess` 改进程级忽略，EPIPE 仍如实返回。
3. codex 0.153.0 在初始化阶段就发 `remoteControl/status/changed`：Wire 原来把 ready 之前的通知
   当协议错误并自关；现在通知在未关闭状态都收，只有审批请求要求 ready。
4. codex 是 node 脚本：子进程环境要沿用 App 的 PATH（原先手写 PATH 缺 node）。
5. PROC04 在 macOS 上 OBSERVED_PASS（0.26–0.30 秒；探针阈值 0.7 秒），Linux 的 BLOCKED 不复现；
   工单里的 200 ms 目标未达到，记录为已知收尾时延。

### 最终验收（当前 HEAD）

| 检查 | 结果 |
| --- | --- |
| `cd prototype && ./build.sh --check` | 退出 0 |
| `bash tests/run-appkit-tests.sh all` | 八套全过（含 LEASE-H01…08） |
| 纯核 | contracts 9/24、part2 22/86、part3 55/147、part4 72/188、part5 40/97、part6 42/95 |
| 进程与 Wire | part5 8/26、part6 9/27、Wire 固定 schema 4/4 |
| 真机 | owned CLI 阶段一通过；PROC04 OBSERVED_PASS 0.26s；Mac 配对加密通过；Python 配对参考 14/14 |
| 门禁 | 隐私登记表 465 点、页面数据同源、交付归档 94 文件哈希、readiness 如实 BLOCKED |

## self_review（已完成）

- 契约与产物对照：四份材料都在 main 里，新增入口都有测试；未接项按第四份 REMAINING 记账，没有写成完成。
- 证据新鲜度：发现最后一次清理提交在编译检查之后，已在当前 HEAD（`bbe298d`）重跑 `build.sh --check` 通过。
- 之后又做了一步范围明确的收口：把「权限与启动」并进「隐私」一栏（`7c86e89`），
  重新跑了 `build.sh --check` 与八套 AppKit 回归，并看了隐私页浅深色截图（`2 块屏 / 未锁屏 / 未读取 / 已隐藏`）。
- 残余风险：真实窗口收窗/放回、真机探针、配对与 Keychain、owned Codex 允许路径、设备桥、live 订阅都未验。
