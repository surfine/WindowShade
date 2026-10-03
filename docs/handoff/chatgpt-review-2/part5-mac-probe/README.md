# swift-srp 依赖准入：这台 Mac 上实际做到的与还差的

2026-10-03。按第五份 `workorders/01-首次配对.md` 与 `tests/ACCEPTANCE.md` 的边界执行：
隔离目录 `/private/tmp/srp-probe`（`tools/prepare-srp-probe.py` 生成），不写仓库、不改 home。

## 已完成（有原始输出）

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 生成隔离探针 | `python3 docs/handoff/chatgpt-review-2/part5/tools/prepare-srp-probe.py --out /private/tmp/srp-probe` | 目录生成；`input-hashes.json` 记录 adapter 与 primitive 的 SHA256 |
| 解析依赖 | `xcrun swift package resolve` | 退出 0；`Package.resolved` 见本目录。pins：`swift-srp` 1345dfe…、`big-num` 2.0.3、`swift-crypto` 4.5.2、`swift-asn1` 1.7.3 |
| Mac 编译（Swift 6 严格并发、warnings-as-errors） | `xcrun swift build -Xswiftc -swift-version -Xswiftc 6 -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` | 退出 0，`Build complete!`；原始输出见 `build.txt`（含一条“language mode 被额外 flag 覆盖”的提示） |
| 许可审核 | 逐包 `LICENSE*` 的 SHA256 与首行 | 见下表，全部为宽松许可（Apache-2.0 / MIT），允许依赖使用；发布时需随包附许可与 NOTICE |

| 包 | 许可 | SHA256（文件） |
| --- | --- | --- |
| adam-fowler/swift-srp | Apache License 2.0 | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` |
| adam-fowler/big-num | MIT | `8b54814d9042aef74a4ceee4d4e6a569720be8e544bd089e278d4537d02740fd` |
| apple/swift-crypto | Apache 2.0 | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| apple/swift-asn1 | Apache 2.0 | `8c6db340475136df3c1201d458fa5755698eace76e510471ecc9d857d6083dac` |

Python 参考（`tests/crypto-reference-pairing.py`）在这台机器上 14 项全过，见 `tests/run-part5-mac-crypto-tests.sh` 与 `.build/part5-core/crypto-reference.json`。

## 仍然没过（因此 SRP 还不能算准入）

1. **独立向量互测没做**：`optional-srp/WS2SRPAdapter.swift` 只在隔离探针里编译，没有跑过固定向量的 A/B/M/K 对比。
   `srp_reference.py` 用的是 HAP 变体（username `Pair-Setup`、`k=H(N|pad(G))`、`u=H(pad(A)|pad(B))`、
   自定义 proof 布局），库的便利 API 会按自己的方式补零；第五份自己就写明“不能只改一个布尔值就宣布兼容”。
   要过这一关，需要在探针里用库的算术 + 显式 HAP 编码跑出 A/M/K，与 `srp_reference.py` 逐字节比。
2. **实例工厂与生产接线没有**：App 里没有 SRP 实例的创建路径；`WS2PairSetupServer` 目前只被测试用 KnownKeySRP 替身驱动。
3. **没有原生 Remote 互操作**：真机对端（iPhone Remote / Apple TV 方向）从未连接过；这不因依赖能编译而成立。

结论：依赖本身可用（许可干净、Mac 编译通过），但**首次配对仍是未准入能力**；在向量互测与实例工厂完成前，
隐私页与设置不显示“已支持配对”，也不把预算核或 lease 当身份证据。
