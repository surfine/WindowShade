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

## 许可与边界（2026-10-27 Aaron 质疑后重核，修正早前过严的结论）

**Aaron 说得对：项目都是他名下的，他自己的代码当然可以借。** GPL 约束的是从别人那里拿代码的人，
不约束唯一版权持有人。逐项核清（证据：HomePlay `git log` 239/239 提交全部是 Aaron 一个署名）：

| 代码类别 | 能否进 WindowShade（MIT） | 依据 |
| --- | --- | --- |
| Aaron 原创部分（非参照 MacPlay 源码写的） | **可以**，Aaron 有权自行再许可 | 唯一版权持有人 |
| **参照 MacPlay 源码写的移植**（Session 的配对/加密半边、iAP2 细节——HomePlay 文档自述「参照 pairVerify.ts」「与 MacPlay 逐字节一致」） | **不行，或需处理** | MacPlay 是 GPL-3.0（本机 ~/MacPlay/LICENSE 核过）。移植（翻译）是衍生作品，版权里含 MacPlay 作者的份额；Aaron 无权单方面把这份份额改成 MIT 公开分发。HomePlay 自身选 GPL-3.0 正是这个链条的体现（NOTICE 致谢 LIVI/MacPlay/DiPlay） |
| MFi 身份文件（pk8/p7b，源自 DiPlay 公开发布物） | **永远不进公开仓库** | 不是 Aaron 的材料可再许可；Apple 许可源头。「用户自备、合法性自负」的既有边界不变 |

**落地办法（不需要纠结上面第二行的两条路）**：
1. **B 路线（本地问 HomePlay）零拷贝**：只读本机状态，一行代码都不用借，立即合法。
2. **A 路线的干净做法是净室**：WindowShade 已经有自己独立交叉验证过的 HAP 配对栈
   （WS2PureSRP 对 srptools＋OpenSSL），iAP2 探针也本是 WindowShade 的原创再搬去 HomePlay 长大的。
   缺的 MFiSAP/AuthSetup 按**公开协议规格＋测试向量**净室实现（协议行为与向量是事实，不受版权约束；
   测试身份用自己生成的 P-256 密钥），不读 MacPlay/HomePlay 源码。成本略高，换来 MIT 树完全干净。
3. 若 Aaron 仍想直接移植 MacPlay 衍生部分：那是他对 MacPlay 作者份额风险的显式担责决定，
   需要他明确拍板并记录，默认不这么做。

- 接 A 或 B 之前先和 Aaron 定：bond 归属（一个身份两 App 共用会不会互相踢）、HomePlay 停跑时的降级。

## 对愿景（刷脸解锁两样都对）的落点

face-unlock.md 的第二因素一直是「手机在不在」的弱信号。换成 A/B 之后，第二因素升级为
「配过对的那台 iPhone 此刻 pair-verify 通过」——脸（本人）＋密码学在场（那台手机），
两样都对了才谈代填。这也让 dynamic-lock「回来就开」的四条件里「手机重新连上」有了真凭据。
