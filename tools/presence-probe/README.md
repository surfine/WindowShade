# 在场探针与离位策略小样

独立原生实验，不进入主 App、不锁屏、不认证本人，不使用麦克风或健康数据。
设计、论文与恢复边界见 [使用者边界](../../docs/authentication-boundaries.md)。

```sh
bash tools/presence-probe/run.sh
bash tools/presence-probe/run.sh --observe --camera-index=1
bash tests/run-presence-policy-tests.sh
```

默认只查授权及设备，不打开相机。`--observe` 只在已经获得授权时短采样 30 秒，
不调用 requestAccess；未授权退出 1。以 AVFoundation 采集、Vision 上半身矩形检测，
最多每秒两次推理，输出检出/未检出/未知计数，不保存图像、坐标或模板。
系统中断/错误停止，信号受控停止；45 秒进程硬超时兜底。仍未验证实际采集与取消时延。

设备类型名并不足以证明内置：本机 Studio Display 也报告 builtInWideAngleCamera。
当前发现 builtInWideAngleCamera 与 external；默认观察只自动选唯一内建传输 bltn 的相机，
其它相机通过 --camera-index=N 显式选择。候选须连接正常且未挂起，不自动信任名称或型号。
序号只作诊断，重新插拔后会变；生产登记与校准还未实现。设备元数据不证明可信采集。

本机复核：授权 notDetermined；列表包含 MacBook Air、Studio Display 与连续互通手机。
Studio Display 报告 USB 传输，不能只按 bltn 排除。显式选择它的 observe 请求在授权检查退出1，
未请求权限或开始采集；帮助、非法模式/序号/多参数退出码已核对。
多屏和盒盖边界见 [多屏认证](../../docs/multidisplay-authentication.md)。

人体检测报告存在不等于本人；未检出不等于离位，探针没有图像质量评估。
没有分类性别、体型、衣着、情绪；也没有判断旁人是谁或是否在偷窥。

`PresencePolicy.swift` 为独立纯状态规则，未接探针或系统锁屏：默认影子模式，
当次强认证后启用，合格相机离开 + 经核验配套设备离开 + 30 秒空闲持续至少 10 秒，
再留 5 秒取消时间。43 条检查覆盖返回、输入、未知、旧帧、断层、会话、休眠与一次请求。
这些参数尚未经过本人/攻击者实测，不是产品安全保证。

当前探针的“未检出”不得接成 noPersonInUsableFrame，BLE 广播/RSSI/断连不得接成 verifiedDeparted。
可靠图像质量、配套设备交易、系统状态与恢复适配器仍待完成；自动锁屏保持关闭。
纯策略没有解锁出口；回到座位仍用可靠系统认证，习惯或外观模型不能否决恢复。
