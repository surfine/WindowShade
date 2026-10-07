# 隔离的原生 SRP 配对原语

本目录给 `WS2SRPPrimitive` 提供**真实的 SRP-6a 3072/SHA-512 服务端适配器**。没有监听端口、广播、Keychain 写入或 App 接线。当前 runner 动态链接本机 OpenSSL，**不可发行，也不能把这份可执行文件放进 App**。

## 接口与来源

- `WSNativeSRP.c/.h`：固定 RFC 5054 3072-bit N、g=5；只用公开 BN／EVP／RAND API，不调用已废弃的 `SRP_*`。`begin` 使用 `RAND_priv_bytes` 生成 16-byte salt 和 32-byte b；秘密模幂显式调用 `BN_mod_exp_mont_consttime`。M1 以 `CRYPTO_memcmp` 比较。所有 verify 尝试都会消耗会话，错误输出清零；清理使用 `BN_clear_free` 和 `OPENSSL_cleanse`，错误返回代码而不 assert。
- `WS2NativeSRPPrimitive.swift`：遵守主工程现有 `begin/verify/clear` 协议；不重复定义协议。返回的是原始 64-byte K。C context 不保留 PIN，也不保留完成后的 b/v/S/K。Swift/CryptoKit 的外部调用者仍须管理自己持有的返回 Data；此处不声称所有 Swift 复制都能擦除。
- `SRPProbe.swift`：必须显式 `--test-json --m2 adk-padded|srptools-minimal`。仅 stdin/stdout 测试管线，返回临时测试 K 供独立客户端比对；不要接入真实凭据或把管线内容写日志。
- 参考 [Apple HomeKitADK 原实现](https://github.com/apple/HomeKitADK/blob/fb201f98f5fdc7fef6a455054f08b59cca5d1ec8/PAL/Crypto/OpenSSL/HAPOpenSSL.c) 与 [原向量](https://github.com/apple/HomeKitADK/blob/fb201f98f5fdc7fef6a455054f08b59cca5d1ec8/Tests/HAPCryptoTest.c)，固定提交 `fb201f98f5fdc7fef6a455054f08b59cca5d1ec8`。源文件保留作者、Apache-2.0 与修改说明；许可证在 `LICENSE-HomeKitADK.txt`。没有引入 ADK 的其它网络／认证流程。

## 本机复现

仓库根目录执行，不需要打开设备：

```sh
bash tools/probes/companion-pairing/run-native-srp.sh
```

默认 OpenSSL 为 `/opt/homebrew/opt/openssl@3`，可用 `WS_SRP_OPENSSL_PREFIX` 指向另一本机 OpenSSL 3。runner 编译 C 测试，核对正常 bridge 对象不存在测试注入符号，再用 Swift 6 strict concurrency／warnings-as-errors 与主工程现有协议一起编译适配器。不会自动安装依赖或运行独立 Python 客户端。

独立客户端使用 srptools 1.0.1（上游 tag commit `56916f87c6b49ff90b5e97a65e22c0c9581744d8`）及 six 1.17.0。可以在临时环境按锁定文件安装后执行：

```sh
python3 -m venv .build/native-srp-client
.build/native-srp-client/bin/python -m pip install --require-hashes --only-binary=:all: -r tools/probes/companion-pairing/requirements-test.txt
.build/native-srp-client/bin/python tools/probes/companion-pairing/srptools-interop.py \
  --bridge .build/native-srp-probe/srp-probe \
  --report .build/native-srp-probe/interop-report.json
```

本次使用的是下载到临时目录的固定 srptools tag 原文件与校验过 SHA-256 的 six wheel，没有安装全局包。独立脚本通过实际 Swift `begin/verify`，不是直接调用 C 测试后门。报告不保存 PIN、私钥或 K。

## 2026-10-07 实际结果与未决差异

本机 OpenSSL 3.6.4 / arm64：

- C 逐项匹配上游 v、B、u、S、K、M1、M2 固定向量；拒绝 A=0/N、错 proof、空／超长 A、错误 proof 长度；验证失败、重放、clear、重复 begin 后均不能复用，错误返回 K/M2 全零。
- 相同 C 验收在 AddressSanitizer＋UndefinedBehaviorSanitizer 下通过。测试对象显式 `WS_SRP_TESTING` 才包含固定 salt/b 注入与内部值快照；正常对象 `nm` 确认没有这些函数。
- 独立 srptools 客户端：4 项成功／编码案例与 7 项拒绝案例通过，包含错 PIN、proof 篡改、重放和清理。记录见 `evidence/interop-2026-10-07.json`。

**前导零 M2 差异已经用固定输入证明，尚未为 Companion 裁决：** 测试专用 a=1 导致 A=05（补至 384 bytes 有 383 个前导零）。两种服务端模式的 M1 与 K 都和独立客户端匹配，但 ADK 模式 `H(PAD384(A)||M1||K)` 被原版 srptools 拒绝，minimal 模式 `H(minimal(A)||M1||K)` 被接受。常规 384-byte A 两种模式均通过。这个弱 a 只用于公开边界测试，原生服务端仍每次生成随机 b。

`WS2NativeSRPPrimitive(proofConvention:)` **没有默认参数**，避免默默选定兼容规则。生产是否选择 minimal，必须由主模型结合目标 Companion 客户端确定。其它计算保持 ADK 行为：K 对去前导零 S 做 SHA-512，M1 中 g 为单字节、A/B 去前导零、salt 保留完整 16 bytes。

## 外层 M1–M6 离线互通

`PairSetupProbe.swift` 把真实 `WS2CompanionFrame.Decoder → WS2CompanionPairSetupChannel → WS2PairSetupServer → WS2PairSetupCrypto → WS2NativeSRPPrimitive` 串起来。独立 Python 客户端自行编码 OPACK/TLV/帧，用 srptools 做 SRP、cryptography 做 HKDF-SHA512、Ed25519 和 ChaCha20-Poly1305。这里只显式选择 `srptools-minimal`，没有改变原语的无默认模式接口。

```sh
bash tools/probes/companion-pairing/run-pair-setup.sh
# 在上面的临时 venv 增加固定版本；本次实际使用本机已有的 cryptography 50.0.1。
.build/native-srp-client/bin/python -m pip install 'cryptography==50.0.1'
.build/native-srp-client/bin/python tools/probes/companion-pairing/pair-setup-interop.py \
  --bridge .build/native-srp-probe/pair-setup-probe \
  --report .build/native-srp-probe/pair-setup-report.json
```

2026-10-07 实测通过，报告见 `evidence/pair-setup-2026-10-07.json`：

- A=05 前导零边界和随机客户端私钥两种完整 M1–M6；帧分别跨头部／载荷分片进入真实 decoder。Python 验证 M4 SRP proof，并独立解密 M6、验证服务端 Ed25519 签名。
- 成功后重新通过真实 repository 读取临时 storage，核对登记的 identifier、公钥、enabled 和 awaitingVerification，而不仅检查内存计数。
- 客户端用 setup key 生成真实 AEAD type-8 输入帧；新建的真实 `WS2CompanionChannel` 尚未 Pair-Verify，拒绝该帧、关闭连接且 deliver 回调次数为 0；原配对 channel 也拒绝输入。
- 错 PIN、M5 AEAD 篡改、正确 AEAD 内的错误 Ed25519 签名、M4 后取消再提交 M5，均没有登记，没有发出 M6。后三种场景重试仍拒绝。

存储适配器仅保留进程内字节，重新加载验证的是 repository 序列化边界，不代表真实 Keychain 的耐久性。集成 harness 只输出协议线上帧、计数和断言状态，**不输出私钥或 SRP K**。编译包含现有 TCP transport 是为了满足原 channel 的扩展类型引用；从未实例化 transport、打开 socket 或监听端口。

本验收未运行原生 iPhone Remote、未做真实网络互通、未签名、公证或验证 Intel 发布包。完整离线 M1–M6 通过不代表 Apple Remote 可直接发现或兼容。要接入 App，仍需主模型安全复核、固定且可随包交付的加密依赖、两架构构建、真实设备互通及前导零协议裁决。
