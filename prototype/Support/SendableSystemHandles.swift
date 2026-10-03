import ApplicationServices

// 系统没给这两个 CF 句柄标 Sendable，这里逐个担保，不对整个模块用 @preconcurrency import。
// 新增条目前先确认：它是不可变的引用句柄，跨线程的只有引用本身，真正的操作本身线程安全。

/// AX 元素是指向别的进程里辅助功能对象的不可变引用。AX 调用可以在任意线程发起
/// （本 App 刻意把慢 AX 放到后台队列并设超时），跨线程传的只是这个引用。
extension AXUIElement: @retroactive @unchecked Sendable {}

/// 事件 tap 的端口句柄。跨线程只用于把它交回主线程重新启用或作废
/// （CGEvent.tapEnable / CFMachPortInvalidate），不在别的线程读写端口状态。
extension CFMachPort: @retroactive @unchecked Sendable {}
