import ApplicationServices
import ScreenCaptureKit

// 系统没给这些句柄标 Sendable，这里逐个担保，不对整个模块用 @preconcurrency import。
// 新增条目前先确认：它是不可变的引用句柄，跨线程的只有引用本身，真正的操作本身线程安全。

/// AX 元素是指向别的进程里辅助功能对象的不可变引用。AX 调用可以在任意线程发起
/// （本 App 刻意把慢 AX 放到后台队列并设超时），跨线程传的只是这个引用。
extension AXUIElement: @retroactive @unchecked Sendable {}

/// 事件 tap 的端口句柄。跨线程只用于把它交回主线程重新启用或作废
/// （CGEvent.tapEnable / CFMachPortInvalidate），不在别的线程读写端口状态。
extension CFMachPort: @retroactive @unchecked Sendable {}

/// ScreenCaptureKit 的可共享内容是某一时刻的只读快照：窗口、显示器、App 的属性都是只读的，
/// 拿到后不会再变。开流时要把它从主线程交给捕获对象的异步方法。
extension SCShareableContent: @retroactive @unchecked Sendable {}
extension SCWindow: @retroactive @unchecked Sendable {}
extension SCDisplay: @retroactive @unchecked Sendable {}
extension SCRunningApplication: @retroactive @unchecked Sendable {}

/// 流的开始、停止、改配置都是系统的异步调用；本 App 只把流的引用交给 Task 去 await 这些调用、
/// 或在锁里比对“还是不是当前这条流”，采样帧走各自的 sampleHandlerQueue。
extension SCStream: @retroactive @unchecked Sendable {}

/// 过滤器在本 App 里建好后只读不改（不设 includeMenuBar 之类的可写属性），只交给 SCStream / 截图接口使用。
extension SCContentFilter: @retroactive @unchecked Sendable {}
