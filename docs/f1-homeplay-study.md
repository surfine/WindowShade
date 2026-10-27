# F1 研究借鉴 HomePlay：Mac 配件角色是「就是那台手机」的已实证答案

2026-10-27。Aaron 指示研究 HomePlay 的双因素认证做法。结论先行：

**HomePlay 已在这台 Mac 上用真机证明：Mac 扮 iAP2 配件（MFi 身份自备），iPhone 像连车机一样
配对一次，之后每次重连都走 pair-verify（Ed25519 长期公钥双向签名）——这一步同时给出
「在场」与「密码学意义上的就是那台手机」。这正是 F1 一直缺的那一半。**

## HomePlay 做了什么（docs/wireless.md 与 Sources/Session 的实证）

| 层 | 做法 | 对 WindowShade 的意义 |
| --- | --- | --- |
| 配对一次 | PairSetup：SRP-6a（3072 位）＋固定码，M5/M6 加密交换 Ed25519 长期公钥（LTPK），控制器公钥落盘 | 与我们 WS2PairSetupServer 同族（我们多了 Touch ID 准入门，更严） |
| **每次重连** | PairVerify：临时 X25519 ＋ 双向 Ed25519 签名对 LTPK；成功才派生控制密钥 | **这就是 F1 第 2 条「身份」的答案**：重连本身即证明，不需要读 ANCS |
| 配件身份 | AuthSetup（MFiSAP 0xAA05）：用 Apple MFi 配件证书签名，iPhone 才认 | 让 iPhone **不用装任何 App** 就肯配对——正是 Aaron「不做手机 App」约束下的唯一通路 |
| 真机记录 | `0x1D00 → 0xAA05 → 交接 → 开会话`；锁屏走远回来自动恢复 | 证据已存在，不是纸面方案 |

## 三条路线怎么排（F1 更新后的次序）

1. **A（长期正解，需排期）：WindowShade 自己的 iAP2 在场配件。**
   独立实现（我们已有 WS2 HAP 栈与 `tools/carplay/iap2` 原创探针打底），iPhone 配对一次后，
   「pair-verify 通过」直接当 PresenceLock 的 connected 事件——身份与在场一步到位，
   顶替现在的明文连接状态轮询。
2. **B（最快见效）：本地问 HomePlay。** 两App 同机同用户；HomePlay 已持有已验证的 bond。
   WindowShade 经本机 IPC 读「那台 iPhone 当前 pair-verify 通过没有」。半小时级的接线，
   代价是依赖 HomePlay 在跑。适合作过渡与真机对照的参照系。
3. **C（保底）：ANCS 加密读探针**（`tools/probes/f1-identity.sh`，已备好）。
   能走通就够轻；走不通也不碍事——A、B 都在。

## 许可与边界（硬约束）

- HomePlay 是 **GPL-3.0**：只借协议事实与已实证的结论，**一行代码不拷**（与吸收 Open Island 同一纪律）。
- **MFi 身份绝不进 WindowShade 公开仓库**（Apple 许可证；这里是 MIT 公开树）。永远「用户自备、
  合法性自负」——沿用我们 `--identity-dir` 的既有边界；HomePlay 把身份放进自家仓库是他们的选择，不外溢。
- 接 A 或 B 之前先和 Aaron 定：bond 归属（一个身份两App 共用会不会互相踢）、HomePlay 停跑时的降级。

## 对愿景（刷脸解锁两样都对）的落点

face-unlock.md 的第二因素一直是「手机在不在」的弱信号。换成 A/B 之后，第二因素升级为
「配过对的那台 iPhone 此刻 pair-verify 通过」——脸（本人）＋密码学在场（那台手机），
两样都对了才谈代填。这也让 dynamic-lock「回来就开」的四条件里「手机重新连上」有了真凭据。
