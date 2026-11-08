# 首次配对的真实 SRP 服务端选型

2026-10-07。仅研究与临时原生构建；未改生产安全代码、未启用配对监听。`WS2PairSetupCrypto` 的签名／AEAD 层已有代码，但 `WS2SRPPrimitive` 仍须真实实现，`KnownKeySRP` 不能作为交付证据。

**建议优先采用 Apple HomeKitADK 的 SRP-3072/SHA-512 服务端运算与向量，封装成很小的 C 边界，接现有 Swift 协议。** 这份参考实现的 SRP 部分已在本机用 OpenSSL 3.6.4 编译并通过官方向量。不是用 PIN 的哈希冒充 SRP，也不是启动 Python 服务。是否采用、是否承担原生加密依赖的打包维护，由主模型决定。

## 固定候选与取舍

| 候选 | 固定版本／提交 | 许可与构建依赖 | 判断 |
| --- | --- | --- | --- |
| Apple HomeKitADK SRP 部分 | `fb201f98f5fdc7fef6a455054f08b59cca5d1ec8` | Apache-2.0；C + OpenSSL。保留许可、作者归属与修改说明，WindowShade 自身可继续 MIT | 优先参考：真实 HAP 服务端、完整 SHA-512／3072 向量，本机已验证。仓库于 2025-10-28 归档，采用后须自己维护这个小边界 |
| adam-fowler/swift-srp | `2.4.0` / `1345dfeff4d1bc54fc36257325371df3d1d7a813` | Apache-2.0；`big-num 2.0.3` / `9059dcab8dd001b8143bc512b4477d079e97957f`（自身 MIT，另含 BoringSSL 归属），以及 swift-crypto | Swift 原生备选；并非设置 `.N3072`、`SHA512` 就 HAP 兼容。需要独立的 HAP proof／session-key 序列化层 |
| Bouke/SRP | `3.2.1` / `c01934477cb0aa14b4da5c3cb61d447bd6393ce0` | MIT；attaswift/BigInt 与 swift-crypto；manifest 下限 Swift 5.1 / macOS 10.15 | 可作交叉参照，不选生产首发：纯 BigInt 模幂没有已核实的恒时保证，proof 比较直接使用 `Data ==`；其 Python 互通测试要显式设置 PYTHON 才运行 |
| srptools | `1.0.1` / `56916f87c6b49ff90b5e97a65e22c0c9581744d8` | BSD-3-Clause，Python | 只用作独立互通 oracle／生成测试向量；不带进 App，不替代原生实现 |
| 本机 OpenSSL | `3.6.4`（实际 `openssl version` 确认） | Apache-2.0；本机 libcrypto.a 仅 arm64 | 可用成熟 BN／EVP 后端。不能直接调用整套旧 `SRP_Calc_*` 当成 SHA-512 SRP：其 `k/u/x` 实现仍固定 SHA-1 |

已读原始来源：[ADK 许可](https://github.com/apple/HomeKitADK/blob/fb201f98f5fdc7fef6a455054f08b59cca5d1ec8/LICENSE.md)、[ADK 原生实现](https://github.com/apple/HomeKitADK/blob/fb201f98f5fdc7fef6a455054f08b59cca5d1ec8/PAL/Crypto/OpenSSL/HAPOpenSSL.c)、[swift-srp 配置](https://github.com/adam-fowler/swift-srp/blob/1345dfeff4d1bc54fc36257325371df3d1d7a813/Sources/SRP/configuration.swift)、[其服务端](https://github.com/adam-fowler/swift-srp/blob/1345dfeff4d1bc54fc36257325371df3d1d7a813/Sources/SRP/server.swift)、[其依赖清单](https://github.com/adam-fowler/swift-srp/blob/1345dfeff4d1bc54fc36257325371df3d1d7a813/Package.swift)、[Bouke 服务端](https://github.com/Bouke/SRP/blob/c01934477cb0aa14b4da5c3cb61d447bd6393ce0/Sources/Server.swift)、[srptools context](https://github.com/idlesign/srptools/blob/56916f87c6b49ff90b5e97a65e22c0c9581744d8/srptools/context.py)、[OpenSSL SRP 源码](https://github.com/openssl/openssl/blob/openssl-3.6.4/crypto/srp/srp_lib.c)。Swift 两个候选本轮只检查源码，未声称完整构建成功；其传递依赖不能使用浮动范围作为最终发布锁。

## 不能忽略的序列化差异

HAP 基础参数为 3072-bit N、g=5、SHA-512、16-byte salt。实际 Pair-Setup 用户名是 UTF-8 `Pair-Setup`，密码是原样 PIN；每次生成新的至少 256-bit 随机私有 b。RFC 5054 的 Appendix B 是 SHA-1／1024-bit 示例，不能独自证明 HAP SHA-512 正确；这里另有 Apple 收录的 3072／SHA-512 完整向量。

Apple ADK 的精确行为：

- `x = H(salt || H(username || ":" || pin))`，`v = g^x mod N`。
- `k = H(N || PAD384(g))`；`B = (k*v + g^b) mod N`。
- `u = H(PAD384(A) || PAD384(B))`；`S = (A * v^u)^b mod N`，拒绝 `A mod N == 0`。
- `K = H(S 去前导零)`，64 bytes，绝不是 S 本身或十六进制字符串。
- M1 中 `H(g)` 用单字节 `05`；A/B 也去前导零；N 固定 384 bytes。
- ADK M2 取 **384-byte A**。srptools 的整数序列化在此使用最短 A。罕见前导零情形必须做差分并确认实际 Companion 客户端规则，不能用一份普通随机互通样本掩盖差异。

swift-srp 2.4.0 新增 `padGeneratorForProof: false`，能修正 H(g)，但 `verifyClientProof` 仍将 A/B/S 填充到 N 长度：**不够**。常见没有前导零的样本可能通过，不能宣布兼容。若选该库，借其 SRP 模幂，单独按目标协议构造 K/M1/M2，并保留前导零向量。还须核 `big-num` 的秘密指数路径：当前 `power` 调普通 `BN_mod_exp`，不能只因依赖 BoringSSL 就宣布恒时。

## 本机已完成的独立证据

在 `/tmp/windowshade-srp-research/` 下载上游源码与固定版本的候选。临时 `adk_srp_vector.c` 原样抽取 ADK SRP 函数及 `HAPCryptoTest.c` 的 SRP 向量，只补独立编译需要的常量、assert 和 EVP 哈希胶水。没有改写 SRP 公式，没有链接 WindowShade，也没有网络配对。

```sh
clang -O2 -Wno-deprecated-declarations \
  -I/opt/homebrew/opt/openssl@3/include \
  /tmp/windowshade-srp-research/adk_srp_vector.c \
  -L/opt/homebrew/opt/openssl@3/lib -lcrypto \
  -o /tmp/windowshade-srp-research/adk_srp_vector
/tmp/windowshade-srp-research/adk_srp_vector
```

退出 0，输出：`Apple HAP SRP3072/SHA512: verifier, B, u, S, K, M1, M2 match official vectors; A=0 rejected`。

[官方向量](https://github.com/apple/HomeKitADK/blob/fb201f98f5fdc7fef6a455054f08b59cca5d1ec8/Tests/HAPCryptoTest.c) 使用 alice/password123，逐项比较 v、B、u、S、K、M1、M2，而不只是双方同一实现自洽。额外实际运行 A=0 的拒绝测试。

源文件 SHA-256：`HAPOpenSSL.c` = `6957fe01420a14d9170e87045ad714c4dce9dde19be190ff01aca7019855b08d`；`HAPCryptoTest.c` = `5718236dfacc521f575a4f196b20db1f3b7df65daebec915d9d22ca43fcf998c`；临时 harness = `4492dc5f2311d882d9bfdf85ab7201d4a455f5b50dd3389194d9c18c36e9bb80`。

这证明该参考原语可以在这台 Mac 上运行且匹配向量；未证明 Swift adapter、原生 Remote 的 M1–M6 互通或发布包依赖完整。`-Wno-deprecated-declarations` 只用于验证原封参考代码：OpenSSL 3 已废弃 SRP 高层 API，生产边界宜保留 N/g 常量并用公开 BN/EVP 实现，避免把弃用 API 带到下一代 OpenSSL。

## 接入现有协议的最小工作块

1. 在 `WS2SRPPrimitive` 后增加单会话 adapter。`begin(pin:)` 仅接受新状态，CSPRNG 生成 salt/b，得到 v/B，返回 16-byte salt 和最多 384-byte B；不保存 PIN。`verify(publicKey:proof:)` 只允许一次；接收现有服务器放行的 1…384-byte A，在运算边界左填充，proof 必须 64 bytes，拒绝零／N 倍数／超长。验证 M1 前不提供 K，不允许错误 proof 后复用会话。
2. C 端保管 b/v/S，清理采用 `BN_clear_free`／`OPENSSL_cleanse`；proof 比较使用 `CRYPTO_memcmp`。Swift 返回原始 64-byte K 和 64-byte M2；`clear()` 幂等，关闭、超时、错误、配对成功均销毁秘密。生产不能把分配失败留成外部输入可触发的 assert 崩溃；改成可恢复错误码，并维持秘密模幂恒时标记。
3. 不引入 ADK 的 accessory 数据库、网络、UI、认证策略；复用现有 TLV、Pair-Setup M5/M6 签名／AEAD、尝试限制和 Keychain。只替换 `KnownKeySRP` 测试替身无法覆盖的原语。测一次原生运算延迟，再决定当前同步 MainActor 协议是否须改为串行后台队列。
4. 构建先锁定 libcrypto 来源和版本，目标为 arm64+x86_64 的静态／随包依赖；当前 `/opt/homebrew/...` 只能做本机研究，**不能作为用户安装依赖**。包内归属清单保留 Apache、OpenSSL 等实际引入文件的许可。签名发布时验证无绝对 Homebrew 动态链接。

验收应包括：上述逐项官方向量；独立 srptools 客户端对真实 server adapter；固定前导零 A/B/S/salt；错 PIN、proof 任一字节篡改、A=0/A=N、重放、第二次 verify、超时清理、随机源失败；最后才把该 adapter 接到真实 M1–M6 流程。互通与原语向量是两项不同证据，不互相替代。
