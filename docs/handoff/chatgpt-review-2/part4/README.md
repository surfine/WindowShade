# WindowShade 2 · 第二回合第四部分

日期：2026-10-03。输入是上一份统一交接包的 `candidate-repo/`，不是 GitHub 最新分支。本次交付包括候选源码增量、已运行测试、决策说明和给执行模型的接线施工单。**没有宣称第二回合已完成，也没有发布应用。**

从 `00-交给执行模型.md` 开始。需要核查为什么这样做，读 `decisions/`；准备改实际工作区，按 `workorders/`；想看还差什么，读 `REMAINING.md`。不要重新从旧版小抄推导一套相互冲突的实现。

## 这一份真正改变了什么

|范围|本次候选源码|明确没有变成的东西|
|---|---|---|
|配对加密|有界 Companion 帧、计数 nonce、Mac 服务端 Pair-Verify、分方向 ChaChaPoly 会话；另有 Python 向量和 Mac 执行测试程序|没有首次 PIN/SRP 配对、Keychain 持久化、完整原生遥控器连接|
|允许审批|完整命令快照、精确绑定、原生审阅卡、交接到既有 Touch ID、消费既有授权账、一次性 accept 编码|没有跳过授权的 Bool 开关；没有文件改动/网络规则/整会话永久允许|
|输入设备|每次物理连接重新准入、换域取消、精确 HID usage 解码、公开 GameController 候选桥|没有 HID 设备监听/鼠标主动 tap 全接线；没有证明任何实际手柄已工作|
|界面宿主|统一使用原 NotchPanel，租约撤销、屏幕变化、原生认证交接；会话/指挥/命令卡和番茄钟|没有增加第二套浮窗；没有把会话列表的方法存在称作后端已接通|
|番茄钟|预设与当前轮分离、设置/菜单/快捷键/工具入口、圆环、同一 host、窗口所有权记录|没有擅自完成主模型负责的 T3 窗口效果；未接入时设置明确不可用|

`overlay/` 中是完整候选文件。28 个文件里，19 个替换上一份候选，9 个新增；其中 27 个 Swift 文件、1 个构建脚本。**9 个新增文件不等于 9 个完整功能，替换文件也含前几份的代码。** `manifest.json` 记录每个文件的旧、新 SHA256；`patches/part4.patch` 可供代码审查。

## 直接使用

只交给执行模型这份包，仍需要它已有的第三份 candidate-repo。也提供四份合成后的独立候选总包，避免人工拼接。

```sh
python3 tools/stage.py --base /已有交接包/candidate-repo --out /全新目录/candidate-v4
```

输出父目录须已存在，输出目录须不存在；基线多、少、改任何文件都会拒绝。它不覆盖实际开发工作区，不提交 Git，也不调用任何外部设备。**工作区已经向前走时，先对照 patch 和对应函数，保留较新的正确实现，不强行还原旧快照。**

本包布局下可直接运行：

```sh
bash tests/run-core.sh
python3 tests/crypto-reference.py
python3 tests/check-approval-schema.py
```

在 Mac 上另行运行 `bash tests/run-mac-crypto.sh`，以及合成候选的 `cd prototype && bash build.sh --check`。前者是合成密钥的 CryptoKit 测试，后者才会加载整个应用的 macOS SDK。`build.sh --check` 也会检查 Metal，不能把 Metal 错误笼统归因于新增 Swift 文件。不要运行会原地替换和签名应用的无参 build.sh。

## 读报告时使用的口径

新纯逻辑测试是 72 场景、188 断言；原 T1 的 12 场景/32 断言、第二份的 22 场景/86 断言是本次重跑的回归，分开计数。Python 加密参考是 18 个测试，不是运行 Swift。28 份 Swift 输入只做了语法解析，其中包括未执行的 MacCryptoTests。完整结果见 `VALIDATION.md`，不把这些数字相加成整应用测试数。
