# 系统认证探针

独立 AppKit + LocalAuthentication 小样，编译到 `.build/companion-probe/`，不接主 App。
默认仅查询手表能力。应用认证成功不等于 macOS 会话解锁。

```sh
bash tools/companion-probe/run.sh --capabilities
bash tools/companion-probe/run.sh --biometric-capabilities
bash tools/companion-probe/run.sh --authenticate
bash tools/companion-probe/run.sh --biometric-authenticate
```

前两项只做 `canEvaluatePolicy` 查询；后两项明确发起系统认证提示，30 秒超时后取消。
手表模式在 macOS 15+ 使用 `.deviceOwnerAuthenticationWithCompanion`，旧系统使用同值旧名称
`.deviceOwnerAuthenticationWithWatch`。指纹模式使用 `.deviceOwnerAuthenticationWithBiometrics`，
新建 LAContext、Touch ID 复用时长设 0，不改用手表或密码策略记成指纹通过。

只有一种模式可被选择；无参数等于 `--capabilities`，`--help` 看帮助。
退出码：0 诊断完成/认证通过；1 参数错误/认证失败；2 认证超时。
能力查询返回 false 仍是成功诊断，不是成功认证。

2026-09-30 本机结果：

| 查询 | 实际结果 |
| --- | --- |
| macOS | 27.0.0 |
| only-companion | `available: false`，`com.apple.LocalAuthentication` / `-11` |
| 纯生物认证 | `available: true`，`biometryType: Touch ID`，无错误 |

`-11` 对应 companion 不可用；仅此结果不能确定是系统设置、配对、距离还是其他条件。
本轮未发起交互认证，也未在真锁屏测试。设备在手边不等于此策略已经可用。

构建目标 macOS 14.0，生成最小 accessory App 并 ad-hoc 签名。探针不读指纹模板、Keychain 或密码，
不访问相机、不扫描蓝牙、不改系统设置、不锁屏、不输入密码。所有认证回调与超时在 MainActor 汇合，
完成出口只执行一次；进程直接按结果退出，避免 AppKit `terminate()` 吞掉失败码。
