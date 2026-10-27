# F1 蓝牙身份实验·运行手册（Mac 侧已备好，等 iPhone 到场）

> 2026-10-27 路线更新（研究结论见 [f1-homeplay-study.md](f1-homeplay-study.md)）：
> HomePlay 已真机实证 Mac 扮 iAP2 配件（MFi 身份自备）可与 iPhone 建立密码学 bond，
> 重连即 pair-verify 即身份。F1 首选改为 **A：自己的 iAP2 在场配件**（排期独立实现）；
> **B：本地问 HomePlay**（过渡最快）。本手册的 ANCS 探针降为 **C：保底**，工具保留。

目标：补 dynamic-lock.md「F1 实验现在怎么做」第 2 条——**证明连上的就是你那台手机**，
不是任何一台手机。做法：读一个需要加密的特性（ANCS，iPhone 只对配过对的配件开放），
迫使系统用配对时的长期密钥加密连接。只有当初配过对的那台做得到。

工具：`tools/probes/f1-identity.sh`（已编译自检通过，不开蓝牙）。
证据是逐行输出：`connecting / connected / services / attempting-encrypted-subscribe /
read-requires-encryption / encrypted-subscribe-ok / finished,identity_proven`。

## 你要做的（约 15 分钟）

1. **配对一次**（第一次才需要）：iPhone 设置 → 蓝牙 → 找到这台 Mac 配对。
   若 Mac 端弹配对请求，核对 iPhone 上显示的数字一致后确认。
2. **拿到这台 iPhone 的 identifier**：跑 `bash tools/probes/f1-identity.sh --list`。
   - 注意：公开 API 只回显「本进程知道的」外设，第一次可能为空。空的话直接走第 3 步，
     用系统设置里刚配对后的回显，或先用一次 `--bond` 试连看 `unknown-identifier` 提示。
3. **跑身份证明**：`bash tools/probes/f1-identity.sh --bond <identifier> --seconds 45 | tee f1-run-$(date +%Y%m%d-%H%M%S).txt`
   - iPhone 上若弹「配对请求」，确认（这一步就是在用长期密钥）。
   - 看到 `encrypted-subscribe-ok` 和 `finished,…,identity_proven` 即第 2 条成立。
   - 只看到 `read-requires-encryption` 没走到 ok：如实记录 `encryption_required_but_not_completed`，
     我们再定替代办法（规格硬要求 3：做不成就停下来说明，不悄悄降级）。
4. **稳定性（第 1 条，顺手做）**：手机揣兜里、握在手里、锁屏各走一两分钟，
   同时开着 `bash tools/probes/PairedRSSIProbe.swift` 那条线（离开就锁开着就有日志），
   看连接会不会自己断。
5. **手表（第 3 条）**：同一台探针对 Apple Watch 重复第 1–3 步；记录它是连得上还是只广播。

## 判定怎么用

- `identity_proven` + 稳定性记录 → F1 关闭，「离开就锁」的在场信号升级为身份因素，
  刷脸解锁的多因素路线打通前置。
- 做不到 → 蓝牙只算「在场」，FacePresenceNote 的注记照旧，不改口径。

## 隐私口径

探针不写设备名、不写地址全文、不记录 ANCS 通知内容（订阅成功即证据，内容一律丢弃）。
证据文件只含时间戳、阶段名和 identifier（本机随机标识，不是蓝牙地址）。
