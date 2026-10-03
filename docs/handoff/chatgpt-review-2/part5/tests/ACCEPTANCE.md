# 第五份测试目录与事实边界

`run-core.sh`：本次 40 场景，覆盖输出队列、持久快照、配对顺序/失败预算、窗口计划、语义票据。MemoryStore 与 FakePairCrypto 只在测试中；没有实际 Keychain、SRP、AX 或输入设备。

`run-process.sh`：本次 8 场景，真实创建 Python 子进程和非阻塞管道；覆盖拆包、同时读写、stderr 大输出、背压截止、半截 EOF、EPIPE、粘包、超长输入、旧连接/范围失效与每批 binding。测试不运行真实助手、不调用 shell、不读取 home。

`crypto-reference.py`：14 个 Python unittest，使用 cryptography 和测试用 Python 大整数，包含部分 RFC 附录算式、候选 SRP 编码、K/派生方向、AEAD 篡改和签名身份绑定。它不执行 Swift adapter。固定密钥全是人工测试字节。

`run-mac-crypto.sh`：真实 CryptoKit M5/M6 分层向量；SRP 被 KnownKeySRP 替代。仅允许在 Mac 上执行；Linux 返回 78 明确未运行。测试应对 M5 identity、公钥和 M6 完整字节、重放、合法 AEAD 内错误签名及坏 tag 进行检查。

`tools/prepare-srp-probe.py`：准备隔离 SwiftPM 目录，不访问网络、不安装库、不改工程。运行成功只证明探针目录生成，不证明依赖可解析或编译。随后真实 resolve/build 输出和 Package.resolved 必须保留。

主应用验收还需要：Mac SDK/Metal 编译；真实 Keychain 签名域；真实 Touch ID；owned CLI；网络协议互操作；GameController；窗口隐藏恢复；原有 EventTap/WindowBrowser 回归；锁/睡眠与权限矩阵；能耗。不能把某个层通过向上外推。

## 应补的竞态测试

持久写成功后、M6 返回前杀进程；M6 发出一半断线；第三次密码失败前后杀进程；老 Keychain 记录被外部改变；撤销写失败再重启；AppRuntime 尚未持有 session 就同步退出；授权 consume 后立刻切项目；队列中第二条被撤销而第一条刚写完；新岛占用后旧 onEnd；AX 完成但 UI 计时已结束；用户手动移动与自动恢复同时到达。每项断言写最终状态和不能发生的副作用，不只断言没有 crash。

测试出错保留命令、编译输出和输入。不要给失败用例改名为“预期失败”后计入通过。负向验收成功是程序正确拒绝错误输入；SDK 未运行是另一个状态。
