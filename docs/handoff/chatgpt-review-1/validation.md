# 实际验证记录

日期：2026-10-03。环境：Linux x86_64，Swift 6.2.1。所有本次Swift命令使用`-swift-version 6`；没有macOS SDK，没有运行中的WindowShade，没有真实设备或CLI账户接线。交接方报告的Mac17,4/macOS27/Swift6.4不是这次测试环境。

## 已运行

| 对象 | 运行结果 | 证据 |
|---|---|---|
| 原包Core/ConductorGesture.swift + ConductorGestureTests.swift | 编译、执行退出0；39条ok，结尾all conductor gesture tests passed | [conductor.log](validation/conductor.log) |
| 原包Core/NotchActivities.swift + NotchActivityTests.swift | 编译、执行退出0；PASS notch activity store | [notch.log](validation/notch.log) |
| 本包14份Foundation骨架 | 每份单独Swift 6类型检查退出0 | [逐文件结果](validation/example-platforms.json)及typecheck-*.log |
| 本包12份骨架组合后的原创边界检查 | 54项检查通过；不等于54个完整功能验收 | [boundary-tests.log](validation/boundary-tests.log)、[测试源码](tests/BoundaryTests.swift) |
| 本包交付结构 | 编号、JSON、Markdown本地链接、嵌入代码一致性和输入哈希检查 | [package-checks.json](validation/package-checks.json) |

14份类型检查：T1、L1、A1、D1、D2、I1、I9、T4、D4、A2、L4、I7、D5、D6。T4/D4本次只做类型检查，没有向真实UserDefaults写入测试。其余12份组合进边界测试，测的是示例展示的有限逻辑。

10份未编译：M1、S1、T2、A3、D3、L2、I2、I3、I5、I8。它们依赖Apple SDK。本包保留源码供真机编译；没有用空stub伪造编译成功。API入口仅取得JavaScript页面壳的项目，在sources.md明确列出。

## 可复现命令

原包解压目录设为`INPUT`，另选临时输出目录`WORK`。本次没有执行会写原工作区.build的原测试脚本，而是使用等价编译命令，把二进制写到外部目录。

```sh
swiftc -swift-version 6 -parse-as-library \
  "$INPUT/code/prototype/Core/ConductorGesture.swift" \
  "$INPUT/code/tests/ConductorGestureTests.swift" -o "$WORK/conductor"
"$WORK/conductor"

swiftc -swift-version 6 -parse-as-library \
  "$INPUT/code/prototype/Core/NotchActivities.swift" \
  "$INPUT/code/tests/NotchActivityTests.swift" -o "$WORK/notch"
"$WORK/notch"
```

对本审查包：

```sh
bash tests/typecheck-examples.sh
bash tests/run-boundary-tests.sh
```

在已具备SDK的Mac上可另行使用`bash tests/typecheck-examples.sh --macos`检查全部示例。这条Mac命令本次没有执行，不代表完整App构建。原App的`--check`还需要Sparkle等原有依赖；不能拿这些独立文件检查替代它。

## 修正过程与代码边界

第一版边界测试辅助函数使用不抛错的autoclosure包住了三个会抛错的调用，编译失败。已改为先正常求值的Bool参数后重新编译运行；[首轮编译诊断](validation/boundary-compile-initial.log)保留，最终编译退出0。没有调整断言来掩盖生产代码错误。

L4示例在检查中补成“取消后该轮永久取消”，避免下一次poll撤掉cancel标志后又发锁；测试53/54覆盖。D2示例字段改名effectiveEffort，明确绑定最终执行档位。修改只发生在本包原创示例，没有修改上传源码。

| 示例范围 | 尚未实现/未验证 |
|---|---|
| T1截止时间 | 完整专注/休息阶段、自然日和窗口效果；入参单调性/有效范围由共享适配器保证 |
| L1单次read | 传感器组合、实际CoreBluetooth请求关联、身份和真实锁态 |
| A1/D1/D2 | 授权账接线、完整指挥状态机、实际后端发送；UI票不能当安全grant |
| I1/I9 | 完整输入来源、矩形导航、触点生命周期、真实事件改写 |
| A2 | socket服务器、配置事务、真实hook进程；示例只编码最小回复 |
| D5 | 密码学配对、服务端角色、跨窗口300秒冷却；PIN格式检查不是随机性或协议安全证明 |
| D6 | JSON解析、EOF半帧、总队列限制、Process生命周期和实际协议状态机；示例仅分帧 |
| Apple SDK示例 | 语法/可用性、TCC、回调、签名和硬件均待Mac检查 |

本次没有跑AppKit/UI截图、完整`build.sh --check`、多触点ABI、CGEventTap、HID映射、Bluetooth、DualSense、锁屏/解锁、TCC重签、真实Codex/Claude或能耗基准；没有安装/卸载hook，没有向真实home改配置，没有发付费模型任务，没有读取或存储登录密码。

原包v4认证96个场景与v3指挥64个场景仍是原状态，未被整体升级。日志和输入清单只证明相应范围，不能把它们当全产品通过报告。交付不含测试二进制、原项目整份源码、第三方实现或凭据。
