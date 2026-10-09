# 2026-10-08 原生 Remote 真机通过

iPhone 控制中心的 Apple TV 遥控器已进入可操作界面。用户确认按键和滑动，第10轮接收器在完整 Pair-Verify 验签后的通道收到 **235条有效输入事件**：3次按下、3次松开，22次触控开始、185次移动、22次结束。连接持续到120秒窗口结束，关闭首因为owner-stop；发送队列已清空。此阶段的发现、PIN、会话与真实输入隔离计数已完成。

范围仍是独立接收器，没有接窗口、系统音量或助手动作；没有签名、替换或发布主应用。本轮基线为 `4accf310d505041f5d4458e204c62e55e022a900`，工作分支 `codex/ws2-remote-gpt6-handoff-20261007`，改动保留在工作区，未提交或推送。

## 真机结论

| 运行／连接 | 实际观测 |
|---|---|
| 第9轮 | 用户就绪后运行120秒，incoming/accepted均0；没有握手样本，AEAD和输入字段留null |
| 第10轮连接1 | PV→PS→enrolled；首frame8长5222字节，initial-PV-main rx0校验失败；protocol-reject关闭，没有兼容输入 |
| 第10轮连接2 | fresh PV完成验签，263条认证消息，其中235条有效HID事件；record RX263/TX35，37个完整记录已发送；owner-stop结束 |
| 手机观察 | 用户原话：“已进入，已按键和滑动” |
| 清理 | 两轮自然退出0；PID77790、81518的lsof及ps均exit1且无结果，应用均记录remainingListeners0 |

**成功的是fresh PV认证路径。** 初始PV-main候选并未匹配本轮手机；不扩大猜测、不改用其它key扫描。第一连接仍被拒绝，这份失败证据保留。由于本轮包含多处已验证修复，不能只把成功归因到某一个响应字段。第10轮由用户明确要求“再来一次”，沿用同一二进制和配置补样；新进程重新创建临时身份，不是严格因果对照实验。

[第10轮完整结果](evidence/live-10-result.json) · [脱敏日志](evidence/live-10.jsonl) · [退出清理](evidence/live-10-cleanup.json) · [第9轮零样本](evidence/live-result.json)

## 实现与本机验收

初始PV候选仅在完整PS成功、同连接enrollment receipt有效后启用，逐次检查peer/key/revision。它永不创建VerifiedSession或生产Message；首记录期限10秒、整轮120秒。fresh PV重新验签并切换key/counter，早期兼容输入不追认为认证输入。未采用原始PV-M3在PS后补完的提案。

profile按方法生成完整有序应答，一次进入有界队列；容量不足或发送失败即关闭，不重试已用nonce。按钮与触控按内容和序列计为有效输入，systemInfo不计输入。连接首因锁存一次；区分slice与完整record完成，失败AEAD也报告连接编号。默认及upstream-reference应答策略、M2/M6元数据与ID表示均在启动时固定，生产strict默认不变。

| 检查 | 结果 |
|---|---|
| 探针Swift6严格并发、warnings-as-errors | 构建退出0 |
| 离线profile/发现/清理 | 75项通过 |
| 独立完整字典、顺序与输入分类矩阵 | 168项通过 |
| 握手及会话回归 | 7个握手、10个会话场景通过 |
| 候选兼容通道及拒绝路径 | 13个场景通过，含超过256条连续记录 |
| 真实TCP完整流程 | current和upstream-reference均通过，兼容267条记录，两阶段各5个有效输入 |
| 真实TCP边界 | M5+首记录同一sendall、PS未完成提前输入、错误key诊断，3个场景通过 |
| Transport | 18个controlled及5个原生loopback场景通过 |
| 生产channel与CryptoKit参考向量 | strict/撤销/过期/发送失败、PS M5/M6签名/篡改/重放检查退出0 |
| 主应用 | 保持原优化参数的最终--check退出0；存在既有并发警告，未签名或运行App |

[构建输入及二进制SHA](evidence/probe-build-manifest.json)记录实际27个输入的编译前后匹配，真机前后复核通过。二进制SHA：`98e0efa4735430a97a24047fdebf92698b8d9dca5b6509798db8cb7efa6290fe`。两轮均采用 `current / default envelope / compact identifier / no M6 metadata`，发现使用atv-core。PIN仅在交互stderr显示，stdout落脱敏日志。真机期间没有重编或改写探针；独立的全App编译检查在后台完成。

[命令、退出码与日志SHA](evidence/checks.json) · [逐项矩阵与缺口](test-matrix.json) · [Transport原始回执](evidence/transport-receipt.json) · [复现入口](../../../tools/probes/remote-device/README.md)。`initial-pv-red.json`是修复前的合成红例，不作为手机证据。部分覆盖保持CHARACTERIZED，未执行项没有改为PASS。

## 后续边界

真机通过仅覆盖本机、本轮手机和这一组操作。第一连接的实际record key仍未知；原始PV-M3补完与同IP连接抢占未实现。原生RST、所有listener容量/辅助服务压力、慢日志消费者等尚无完整验收。探针stdout仍同步写入，本轮使用普通文件；未证明阻塞管道场景。当前证据足以确认隔离输入阶段，不代表生产动作集成或发布验收。

密码学核心与最终验收由主代理负责；原生协作负责profile矩阵、transport和独立TCP客户端，均核对实际差异及执行结果。DeepSeek此前余额不足，本轮未调用。
