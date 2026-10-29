// 标题栏双击在事件钩子线程上的去向（增补第 15 步；拍板 10-29 第 17 条）。
//
// 以前双击要排主线程的队问「吞不吞」，主线程忙过 500 ms 就把这一下放给系统——窗口被缩放，
// 而不是收起。现在判定只问辅助功能和 WindowServer，在后台队列上跑，钩子线程等它的答案：
// 主线程卡多久，都不影响这一下吞不吞。吞下之后，收起这个动作照旧排到主线程去做。
// 截止时间还在，但它现在只防目标 App 自己不回辅助功能查询（那时放行，这一下交给它也不会多做什么）。
// 判定拿不准的情况（自己的窗口、自己补发的双击、几何回退）照旧问主线程，见 EventTapCallback.swift。

import Foundation
import Synchronization

/// 后台判定的结论。`Hit` 是命中的那扇窗（App 里是 AX 元素，测试里随便什么）。
enum TitlebarTapClass<Hit: Sendable>: Sendable {
    /// 标题栏双击：吞下，动作交给主线程。
    case titlebar(Hit)
    /// 确定不是：放行给系统和 App。
    case notTitlebar
    /// 后台拿不准：照旧问主线程。
    case undecided
}

/// 钩子线程拿到的去向。
enum TitlebarTapRoute: Equatable {
    case pass
    case swallow
    case askMain
    /// 到点没结论（目标 App 不回辅助功能查询）：放行，调用方留一行日志。
    case timedOut
}

/// 后台判定的结果槽：一个写者、一个读者。到点不再等，迟到的结论没人看；判定本身没有副作用，
/// 所以迟到也不会有动作。
final class TitlebarTapProbe<Hit: Sendable>: Sendable {
    private let slot = Mutex<TitlebarTapClass<Hit>?>(nil)
    private let ready = DispatchSemaphore(value: 0)

    func post(_ result: TitlebarTapClass<Hit>) {
        slot.withLock { $0 = result }
        ready.signal()
    }

    /// 到点还没结论返回 nil（绝无无界等待）。
    func wait(until deadline: DispatchTime) -> TitlebarTapClass<Hit>? {
        guard ready.wait(timeout: deadline) == .success else { return nil }
        return slot.withLock { $0 }
    }
}

/// 在钩子线程上调用：判定放到后台队列，钩子线程只等它，不碰主线程。
/// 命中标题栏时先把动作交给 `deliver`（App 里是排到主线程），再告诉钩子吞下。
func routeTitlebarDoubleClick<Hit: Sendable>(deadline: DispatchTime,
                                             classify: @escaping @Sendable () -> TitlebarTapClass<Hit>,
                                             deliver: (Hit) -> Void) -> TitlebarTapRoute {
    let probe = TitlebarTapProbe<Hit>()
    DispatchQueue.global(qos: .userInteractive).async { probe.post(classify()) }
    switch probe.wait(until: deadline) {
    case .titlebar(let hit)?:
        deliver(hit)
        return .swallow
    case .notTitlebar?:
        return .pass
    case .undecided?:
        return .askMain
    case nil:
        return .timedOut
    }
}
