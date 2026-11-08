# 来源与适用范围

核对日期：2026-10-03。代码事实以本包 base-sources、overlay、manifest 和实际测试日志为准，不以公开仓库 HEAD 覆盖上传快照。没有将别的项目源码拷入新增 Swift。以下外部资料只支持明确列出的语言与运行循环概念，不能证明本产品完成。

## S01

Swift 官方 SE-0420，Inheritance of actor isolation。
https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md

本轮读到完整提案正文；其标明 Swift 6.0 implemented。使用范围为可选 isolated 参数和 #isolation 继承调用者隔离。这帮助解释本次 helper 的修复选择；具体成功依据仍是本地 Swift 6.2.1 的真实编译与测试。没有将其视为 ScreenCaptureKit 导入类型已经可用的证据。页面 main 不是本产品固定依赖。

## S02

Apple 官方归档 Threading Programming Guide，Run Loops。
https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html

本轮读到正文。使用范围为运行循环可能嵌套、timer 投递不保证实时、运行循环对象使用有线程边界。它是归档概念资料，不是当前 macOS AX observer 或私有 WindowServer 的完整协议。

## SDK 正文可用性限制

本轮尝试官方 AXObserverCallback、AXUIElementCopyAttributeValue 等符号页面时，部分只返回 JavaScript 页面壳。未把这些壳当作已经读到函数的完整线程、所有权或错误契约。实际 SDK 头文件与类型检查、Mac observer 安装/撤销行为仍在验收单中。候选能 frontend parse 不等于 SDK 签名正确。

## 产品内事实

原 v8 `REMAINING.md` 明确保留旧宽松 Bool 消费者、完整 T3 恢复、Mac 编译等缺口。本份对照这些实际路径逐一修改；没有因未再涉及其他目标就删除它们。`sources/code-map.json` 给出实际路径、源码 SHA256 和当前符号行号；版本变化后先核对 hash，不盲贴行号。

外部资料的说明均为短摘要，本包不附整篇提案或指南。未下载或分发字体、SDK、商业媒体或任何用户身份凭据。
