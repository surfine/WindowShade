# WindowShade 2：规格审查与施工小抄

2026-10-03。按上传包`00-先读我-给 ChatGPT.md`的委托交付。审查对象是上传快照，不是GitHub最新代码；没有修改原项目或发布1.0.16。

先看[review.md](review.md)，再应用[prompt-patches.md](prompt-patches.md)。报告有53条问题，7条阻断相关危险接线、36条高、9条中、1条低。阻断不意味着所有工作都停；调整后的顺序允许无关纯逻辑和有限UI继续。

给执行模型派工时，每次附修正后的总则、一个工作包以及对应小抄。24份小抄包含目标、API、原创骨架、陷阱、测试、边界和未知项。它们是施工参考，不是已经完成的24个功能。

| 纯逻辑起步 | 有限UI | 系统适配与探针 |
|---|---|---|
| [T1](cheatsheets/T1.md) 番茄钟 | [M1](cheatsheets/M1.md) 菜单 | [A2](cheatsheets/A2.md) hooks/socket |
| [L1](cheatsheets/L1.md) 在场状态 | [S1](cheatsheets/S1.md) 符号 | [L2](cheatsheets/L2.md) 蓝牙 |
| [A1](cheatsheets/A1.md) 会话/待批 | [T2](cheatsheets/T2.md) 计时活动 | [L4](cheatsheets/L4.md) 锁定效果 |
| [D1](cheatsheets/D1.md) 指挥边界 | [T4](cheatsheets/T4.md) 计时设置 | [I2](cheatsheets/I2.md) 多触点ABI |
| [D2](cheatsheets/D2.md) 能力票据 | [A3](cheatsheets/A3.md) 会话活动 | [I3](cheatsheets/I3.md) 滚动tap |
| [I1](cheatsheets/I1.md) 输入模型 | [D3](cheatsheets/D3.md) 指挥活动 | [I5](cheatsheets/I5.md) Siri Remote |
| [I9](cheatsheets/I9.md) 焦点 | [D4](cheatsheets/D4.md) 指挥设置 | [I8](cheatsheets/I8.md) DualSense |
| | | [I7](cheatsheets/I7.md) 输入同意 |
| | | [D5](cheatsheets/D5.md) 遥控协议 |
| | | [D6](cheatsheets/D6.md) App Server |

精确协议见[hooks与App Server](reference/hooks-and-app-server.md)；私有ABI候选见[多触点附录](reference/private-abi.md)；共享身份、线程和输入边界见[合同](reference/contracts.md)。[sources.md](sources.md)标明来源取得状态和适用范围。`fixtures/`全为合成测试材料，不要直接装入真实CLI配置。

[validation.md](validation.md)记录实际测试：原包两组Foundation测试通过；本包14份Foundation示例类型检查通过，54项原创有限边界检查通过。另10份Apple SDK示例没在这里编译。真机、签名、输入、Bluetooth和锁屏等未测，不能写成通过。

本包未复制第三方实现。`examples/`是独立写的最小边界片段；密码学、身份验证和系统解锁没有用几行样例冒充完成。所有真实权限变更和危险接线仍按Aaron的授权边界进行。
