// 标题栏双击在事件钩子线程上的去向（增补第 15 步；拍板 10-29 第 17 条）。
//
// 以前双击要排主线程的队问「吞不吞」，主线程忙过 500 ms 就把这一下放给系统——窗口被缩放，
// 而不是收起。现在判定只问辅助功能和 WindowServer，在后台队列上跑，钩子线程等它的答案：
// 主线程卡多久，都不影响这一下吞不吞。吞下之后，收起这个动作照旧排到主线程去做。
// 截止时间和以前问主线程时同一条规矩：到点判定还没开始就放行；已经开始了（目标 App 回辅助功能慢）
// 就吞下，等结论出来再做——和以前主线程闲着、慢 App 让判定跑过 500 ms 时一样，这一下不交给系统。
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

/// 双击在钩子里走哪条路（增补第 15 步）。顺序就是 eventTapCallback 的顺序：修饰键先放行，
/// 预过滤确定不在标题栏带内再放行，自己补发的双击问主线程，其余在后台判定。
enum TitlebarTapStep: Equatable {
    case passModifier
    case passPrefilter
    case offMain
    case askMain
}

/// 纯函数，供钩子和测试共用。`inBand` 只在双击、且没按修饰键时才调用（它有缓存成本）。
func titlebarTapStep(clickState: Int64, modifierHeld: Bool, inBand: () -> Bool?,
                     source: pid_t, ownPID: pid_t) -> TitlebarTapStep {
    if modifierHeld { return .passModifier }
    guard clickState == 2 else { return .askMain }   // 三击：pending 状态在主线程
    if inBand() == false { return .passPrefilter }
    return source == ownPID ? .askMain : .offMain
}

/// 钩子线程拿到的去向。
enum TitlebarTapRoute: Equatable {
    case pass
    case swallow
    case askMain
    /// 到点判定还没开始：放行，调用方留一行日志。
    case timedOut
    /// 到点判定已在跑（目标 App 回辅助功能慢）：吞下，结论出来后再做。
    case swallowLate
}

/// 后台判定的结果槽：一个写者、一个读者。和 TapDecision 一样，「开始判定」和「到点放行」互斥：
/// 放行了就不再判定；判定已开始，到点就吞下，迟到的结论由后台自己交出去。
final class TitlebarTapProbe<Hit: Sendable>: Sendable {
    fileprivate enum State {
        case pending
        case running
        case answered(TitlebarTapClass<Hit>)
        case passed
        case swallowedLate
    }
    private let state = Mutex(State.pending)
    private let ready = DispatchSemaphore(value: 0)

    /// 后台开始判定前占用。已放行返回 false：不判定、不动作。
    func begin() -> Bool {
        state.withLock {
            guard case .pending = $0 else { return false }
            $0 = .running
            return true
        }
    }

    /// 交结论。钩子已经按迟到吞下时返回 false，结论由调用方自己交出去。
    func post(_ result: TitlebarTapClass<Hit>) -> Bool {
        let onTime = state.withLock {
            guard case .running = $0 else { return false }
            $0 = .answered(result)
            return true
        }
        if onTime { ready.signal() }
        return onTime
    }

    /// 等到截止时间。准时有结论返回 `.answered`；没开始返回 `.passed`；在跑返回 `.swallowedLate`。
    /// 绝无无界等待。
    fileprivate func wait(until deadline: DispatchTime) -> State {
        _ = ready.wait(timeout: deadline)
        return state.withLock {
            switch $0 {
            case .pending: $0 = .passed
            case .running: $0 = .swallowedLate
            default: break
            }
            return $0
        }
    }
}

/// 在钩子线程上调用：判定放到后台队列，钩子线程只等它，不碰主线程。
/// 命中标题栏时先把动作交给 `deliver`（App 里是排到主线程），再告诉钩子吞下。
/// 迟到时（已吞下）由后台交出：命中给 `deliver`，拿不准给 `askMainLate`，不是标题栏就什么都不做。
func routeTitlebarDoubleClick<Hit: Sendable>(deadline: DispatchTime,
                                             queue: DispatchQueue = .global(qos: .userInteractive),
                                             classify: @escaping @Sendable () -> TitlebarTapClass<Hit>,
                                             deliver: @escaping @Sendable (Hit) -> Void,
                                             askMainLate: @escaping @Sendable () -> Void) -> TitlebarTapRoute {
    let probe = TitlebarTapProbe<Hit>()
    queue.async {
        guard probe.begin() else { return }
        let result = classify()
        guard !probe.post(result) else { return }
        switch result {
        case .titlebar(let hit): deliver(hit)
        case .undecided: askMainLate()
        case .notTitlebar: break
        }
    }
    switch probe.wait(until: deadline) {
    case .answered(.titlebar(let hit)):
        deliver(hit)
        return .swallow
    case .answered(.notTitlebar):
        return .pass
    case .answered(.undecided):
        return .askMain
    case .passed:
        return .timedOut
    case .swallowedLate, .pending, .running:
        return .swallowLate
    }
}
