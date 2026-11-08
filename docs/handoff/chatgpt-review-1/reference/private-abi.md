# I2 私有多触点 ABI：候选表，不是已验证绑定

来源为 [S07](../sources.md#s07) 的历史头文件。该来源不是 Apple 承诺。本轮没有 macOS 27 动态库、设备或 Apple SDK。下面记录已看到的声明事实和按自然 C 对齐推导的布局；没有复制第三方实现。

## 符号与候选签名

候选库路径：`/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`。先 `dlopen(RTLD_NOW | RTLD_LOCAL)`，再逐个 `dlsym`。缺符号只关闭相关功能，不 force unwrap，不退回未知地址。

| 符号 | 历史候选 C 签名 | 当前可信度 |
|---|---|---|
| MTDeviceCreateList | `CFArrayRef (void)` | 低；需核元素类型和所有权 |
| MTDeviceGetFamilyID | `OSStatus (MTDeviceRef, int *)` | 低；family 数值含义须记录 |
| MTDeviceIsBuiltIn | `bool (MTDeviceRef)` | 低；历史声明本就有弱链接说明 |
| MTDeviceGetSensorSurfaceDimensions | `OSStatus (MTDeviceRef, int *, int *)` | 低；单位/方向待测 |
| MTDeviceStart | `OSStatus (MTDeviceRef, int)` | 低；第二参数不能随意命名为已知模式 |
| MTDeviceStop | `OSStatus (MTDeviceRef)` | 低；返回不证明所有回调已经退出 |
| MTRegisterContactFrameCallback | `void (MTDeviceRef, MTFrameCallbackFunction)` | 低；见下方冲突 |
| MTUnregisterContactFrameCallback | 历史头文件使用六参 refcon callback 类型 | **有冲突，禁止照抄强转** |

该来源将 `MTDeviceRef` 视为 CF 类型。普通 frame callback 声明为 `void (MTDeviceRef, MTTouch *, size_t, double, size_t)`，不是未经核实的 `Int32` 返回值，也不是把两个 size_t 随手换成 Int32。其注销声明却采用带 refcon 的另一种 callback 类型。必须独立证实成对的注册/注销签名与实际用法，否则只做符号探测，不能注册生产回调。

## 64 位候选接触记录

这是对历史字段按自然 C 对齐的计算，**不是 macOS 27 实测结果**。候选总大小 96、对齐 8。

| 偏移 | 候选字段 | 类型/字节 |
|---:|---|---|
| 0 | frame | int32 / 4 |
| 4 | 对齐填充 | 4 |
| 8 | timestamp | double / 8 |
| 16 | pathIndex | int32 / 4 |
| 20 | state | uint32 / 4 |
| 24 | fingerID | int32 / 4 |
| 28 | handID | int32 / 4 |
| 32 | normalizedVector | 4 个 float / 16，位置和速度 |
| 48 | zTotal | float / 4 |
| 52 | field9 | int32 / 4，含义未知 |
| 56 | angle | float / 4 |
| 60 | majorAxis | float / 4 |
| 64 | minorAxis | float / 4 |
| 68 | absoluteVector | 4 个 float / 16 |
| 84 | field14 | int32 / 4，含义未知 |
| 88 | field15 | int32 / 4，含义未知 |
| 92 | zDensity | float / 4 |

即使自行写的 C shim 满足 `_Static_assert(sizeof(...) == 96)` 和 `offsetof`，也只证明自己声明的布局，不能证明系统库同意。Swift struct 的布局不能自动当作 C ABI 使用；禁止直接将任意回调指针按 Swift 值类型绑定。

## 只做一次、由主模型负责的探针

第一关只报告 OS/build/架构、库能否打开、符号存在情况。第二关在隔离实验进程检查候选声明，严格限制接触数、字节长度与输出频率；默认不改写事件。第三关用同一设备分别记录一指到四指、左右手、内置与外置、休眠重连、启动停止和退出。所有未经解释字段仍叫 unknown，不从一次轨迹推导固定语义。

callback 内只做有界复制到预分配缓冲区；不访问 AppKit、不打印、不建每帧 Task，不持原始指针穿越并发边界。后端串行消费不可变快照。解绑要先拒绝新输入、递增 epoch、注销/停止，再确认在途 callback 结束，最后释放 context 和 dlclose。需要证明不会有迟到 callback，不能用“等 100ms 应该够”代替所有权协议。

单测只能覆盖自己写的解码/手势模型。实际 ABI、线程、callback 停止时刻和硬件族参数必须 Aaron 在场实测；未通过时产品透传输入，I2 保持关闭。探针源码要原创且列出声明来源。不得为了通过测试而把来源许可限制或未知字段删掉。
