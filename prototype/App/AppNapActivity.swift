import Foundation

/// 进程里的防 App Nap 声明，分层管理（PERF-10）。
///
/// - **基础声明**：只要全局事件回调还装着，就有一条。被 App Nap 之后每次双击都会拖慢全系统
///   鼠标事件，直到 tap 被系统超时禁用；计时器（reconcile/watchdog/菜单刷新）也会被合并推迟
///   数十秒。这是保留一条声明、不为了空闲指标删光的证据。
///   它**不带** `.latencyCritical`：「计时器不被合并」是交互期间才要的待遇，不是进程一辈子的待遇。
/// - **交互租约**：`.latencyCritical` 按会话拿、按会话还，只在作用域里成立（关键输入回调期间）。
///   租约带一个上限，超过上限只计数并记一行证据，不强行打断正在跑的同步段落——
///   「声明释放/重取」要能观测，靠的是计数，不是让状态好看。
///
/// 全部可变状态在 `lock` 里；`ProcessInfo` 的 begin/end 在同一把锁内成对调用。
final class AppNapActivity: @unchecked Sendable {
    /// 验收要看的计数：没有泄漏时 `interactiveBegins == interactiveEnds`、`depth == 0`。
    struct Snapshot: Equatable {
        var baseHeld = false
        var baseBegins = 0
        /// 现在手上有几条租约（嵌套深度）。
        var depth = 0
        var interactiveBegins = 0
        var interactiveEnds = 0
        /// 作用域比上限还长了几次；每次都写进了日志。
        var overCap = 0
    }

    private let reason: String
    private let interactiveCap: TimeInterval
    private let lock = NSLock()
    private var base: NSObjectProtocol?
    private var lease: NSObjectProtocol?
    private var depth = 0
    private var beganAt: Double = 0
    private var state = Snapshot()

    init(reason: String, interactiveCap: TimeInterval = 1.0) {
        self.reason = reason
        self.interactiveCap = interactiveCap
    }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        var copy = state
        copy.baseHeld = base != nil
        copy.depth = depth
        return copy
    }

    /// 基础声明。重复调用是空操作；`releaseBase()` 之后可以再来（例如重装事件回调）。
    func holdBase() {
        lock.lock(); defer { lock.unlock() }
        guard base == nil else { return }
        state.baseBegins += 1
        base = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "\(reason) (base; no latencyCritical)")
        wlog("nap: base hold #\(state.baseBegins)")
    }

    func releaseBase() {
        lock.lock(); defer { lock.unlock() }
        guard let token = base else { return }
        base = nil
        ProcessInfo.processInfo.endActivity(token)
        if depth > 0 {
            wlog("nap: base released while \(depth) interactive lease(s) are still held")
        }
    }

    /// 交互作用域：里面这段时间要「计时器不被合并」。结束后一定还回去。
    @discardableResult
    func interactive<T>(_ name: String, _ body: () -> T) -> T {
        beginInteractive(name)
        defer { endInteractive(name) }
        return body()
    }

    func beginInteractive(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        depth += 1
        guard depth == 1 else { return }
        state.interactiveBegins += 1
        beganAt = MonotonicClock.now()
        lease = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "\(reason) (\(name))")
        wlog("nap: interactive \(name) #\(state.interactiveBegins)")
    }

    /// 还租约。多还一次不会把别人的租约还掉，只会记一行（成对关系坏掉要看得见）。
    func endInteractive(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        guard depth > 0 else {
            wlog("nap: interactive \(name) ended without a matching begin; ignoring")
            return
        }
        depth -= 1
        guard depth == 0 else { return }
        state.interactiveEnds += 1
        let held = MonotonicClock.now() - beganAt
        if held > interactiveCap {
            state.overCap += 1
            wlog(String(format: "nap: interactive %@ held %.0fms, over the %.0fms cap", name, held * 1000, interactiveCap * 1000))
        }
        if let token = lease {
            lease = nil
            ProcessInfo.processInfo.endActivity(token)
        }
    }

    /// 收尾：还掉手上的东西，并留下这轮的计数。退出路径调用。
    func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        if depth > 0 {
            depth = 0
            state.interactiveEnds += 1
        }
        if let token = lease {
            lease = nil
            ProcessInfo.processInfo.endActivity(token)
        }
        if let token = base {
            base = nil
            ProcessInfo.processInfo.endActivity(token)
        }
        wlog("nap: released all; base holds=\(state.baseBegins) interactive begins=\(state.interactiveBegins) ends=\(state.interactiveEnds) overCap=\(state.overCap)")
    }
}

/// 进程里的唯一宿主：事件回调（PERF-03 的准入窗口）也要拿交互租约，所以放在文件级。
let appNapActivity = AppNapActivity(
    reason: "WindowShade owns a global event tap; App Nap stalls system-wide mouse input")
