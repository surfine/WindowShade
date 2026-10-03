# 05　Swift 6 与首帧等待

## 实际编译失败，不是推测

运行原 `tests/DuoCoreTests.swift`，保持 `-swift-version 6 -strict-concurrency=complete -warnings-as-errors`，原 EffectFrameAwaiter 的泛型 async 边界发生 actor 隔离报错。错误原文保留在 `validation/development/duo-swift6-original-isolation.json`。

原辅助函数需要读取调用者拥有的 frame 和闭包，逻辑上没有要把它们送到另一个隔离域。修复采用 `isolation: isolated (any Actor)? = #isolation`。Swift 的 SE-0420 定义了用可选 isolated 参数及 #isolation 继承调用者隔离的能力，并说明这可以让同一隔离域内传递非 Sendable 值。[S01](../sources/SOURCES.md#s01)

本份使用这一语言能力，不修改工程全局语言模式，也不将帧类改成 @unchecked Sendable。MainActor 调用、独立 actor 调用和非隔离调用分别有测试；每个非 Sendable frame 留在自己实际的隔离域，不把它从 Task 结果中跨域返回来伪装合法。

## 取到帧不意味着它仍可用

latest 闭包有可能在取值期间让当前捕获源失效，或让时间超过截止。因此函数在取到值后再次检查 task cancellation、isCurrent、有限时钟、不倒退以及严格小于 deadline。timeout<=0、NaN、infinity、deadline 溢出和大数相加不能推进期限都会直接拒绝。

pause 仍由调用者提供，测试使用受控暂停。这个函数不能保证一个不推进时间、也不真正让出的错误 pause 会正常结束。它也不改变实际 ScreenCaptureKit 的取帧签名和生命周期；周边 `EffectFrameSource` 仍需整应用 Mac 编译。

## 旧测试如何保留

原 Swift DuoCoreTests 没有改源码，新的候选直接通过其原有角度、弹簧、首帧、恢复时钟、超时/重试和 journal 场景。Python `duo-integration-check.py` 是文本级接线检查，其旧字面量 `completeFold(success: true)` 在增加 transaction 参数后必须更新。本份要求新的调用显式带 transaction，并增加原生等待绑定检查，没有把检查删掉或改成无条件成功。

开发时另有两项错误如实保留：完成通知弱引用的 optional.map 触发 Swift 6 闭包隔离错误，改成显式 if-let；新测试最初把非 Sendable frame 作为 Task 返回值，后来将测试改成在原域验证并只返回 Bool。这些记录不能和最终测试数量叠加。
