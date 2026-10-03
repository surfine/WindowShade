# I1f：遥控/指挥模式路由

本份是完整纯逻辑实现与可运行测试，不是请你重写的参考骨架。按给出的文件安装，原样编译、跑测，贴原始结果。遇到决定表未覆盖的情况就停止并报告输入、状态与缺口，不自行发明新行为。

## 可写文件

`prototype/Core/RemoteMode.swift`、`tests/RemoteModeTests.swift`、`tests/run-remote-mode-tests.sh`。测试支撑 `tests/support/WS2TestSupport.swift` 和共享 `prototype/Core/Contracts.swift` 由主模型只安装一次，执行本包时只读。

不修改App、构建脚本、签名、发布、权限、个人设置或其他包。若目标路径已有同名实现，先比较SHA256；仅当主模型确认它是第一轮骨架并批准替换后才覆盖。本包工具默认输出新暂存目录，不覆盖仓库。

## 前置与既有符号

规格来源：`docs/input-devices.md；docs/conductor-v2.md；docs/handoff/deepseek-input.md`。共享类型必须是本份contracts版本，不能另造Context/Token/RequestID。完整符号索引见 `../../contracts/existing-symbols.md`。

不调用既有App符号。本核只依赖Foundation、WS2契约和本文件值类型。对外副作用都是枚举，必须由后续App包调用既有接口；不要为了看到效果把Cocoa/CGEvent/AX带进本核。授权边界统一参照AuthorizationService.swift:28，纯核不直接调用它。

## 决定表

|情况|怎么做|为什么|
|---|---|---|
|初始|disabled且remote模式；开关开启后才接输入|不接管未同意的遥控器|
|遥控模式方向键|down立刻发一次focus；up不再发|焦点响应及时且无双击|
|遥控TV短按|launchpad；0.5秒held则notchShelf并消费up|长按不能再打开启动台|
|播放长按1秒|切模式；清并消费全部当时按住的键，发cancelConductorInput|旧松手不能发送草稿|
|中心确认短按|remote激活焦点；conductor原样交D1|同按钮服务当前唯一入口|
|遥控侧键长按|dictationRequested意图交系统听写适配器，不注入已有文字|不是偷偷切麦克风|
|遥控音量/静音/播放|离散动作交统一执行器|本核无硬件调用|
|遥控power|displaySleepRequest，只息屏；指挥power由D1解释为退出|纠正把息屏混成整机睡眠|
|指挥模式普通按键|保留完整pressID/beganAt/phase交D1|不把输入压成只能单击的字符串|
|被消费的尾部up|忽略，不转给新模式|避免模式切换的穿透|
|关闭|回remote并cancel；再次开启不恢复旧按键|清理确定且幂等|

## 时钟、并发和回调归属

宿主串行驱动一个实例；Swift Sendable表示可以安全传值，不表示允许多个线程同时改同一实例。用同一WS2Clock，测试注入Instant。UI/HID/后端序号统一由宿主事件入口分配，来源原始seq不能直接跨源比较。先处理环境撤销，再丢旧代次；其余保持接收顺序。same instant允许多个不同seq。关闭/暂停不重置令牌编号源。

## 常量及出处

0.5/1秒阈值由I1e提供，本层不另设计时器；模式初值remote、功能初值关闭是安全推荐与产品映射合同。方向repeat由后续来源显式设计，不凭自动HID重复暗加。

下面列出实现中含数值或静态常量的原始行，防止实施时漏掉内联边界。数学0/1、数组索引、纳秒换算和格式位数是实现常量；只有上段明确写“规格”的才来自产品规格，其余产品/安全边界均属本轮推荐，待主模型冻结。不要把它们描述成真机测量。

```swift
// L13
private struct Press: Sendable { let id: UInt64; var consumed = false }
// L16
private var lastPressID: UInt64 = 0
```

## 文案、图标、动效

切换模式只由D1/D3呈现“指挥”；remote仍用系统/既有反馈。无专用新图标和弹簧；仅入口展开用expand，退出calm。

数值取 `docs/design-system.md:332–347` 的令牌。UI示意映射只约束后续App，纯核不得为这些项额外引入动画对象。所有原始状态/动作字符串另见 `COPY.md`；动态private值不能写日志。

## 验收

在交付包根：
```sh
bash packages/I1f/tests/run-remote-mode-tests.sh
```
安装到仓库后，从仓库根：
```sh
bash tests/run-remote-mode-tests.sh
```
退出码必须0，stdout包含 `PASS I1f:`、`0 failures`，不出现 `FAIL ` 或编译error。精确用例/断言数量及完整输出见本包`VALIDATION.txt`；不要把这份历史输出贴成你的Mac实测。

本机再执行 `cd prototype && bash ./build.sh --check`，退出0并包含“==> 编译验证通过”。方法和禁止事项见BuildBaseline；Linux通过不能证明AppKit、硬件、身份、网络和能耗通过。脚本不靠SwiftPM拉依赖，不联网。

## 测试输入与结果

见 `TEST-CASES.md`。每一行对应测试代码的同名CASE，并提供原文件行范围。测试有明确输入值、状态和效果断言；不是只检查有没有字符串或文件。

## 不要做

不创建另一套快捷键执行器，不调用display sleep系统API，不在此核改音量，不越过租约执行act。

不删断言、不降Swift语言版本、不加try?吞掉编译/测试失败、不用mock结果冒充硬件支持。不得签名、安装运行App、改hooks或提交仓库；这些由主模型按授权处理。
