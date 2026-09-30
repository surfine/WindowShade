// 锁屏 / 电源 / 显示这三样状态放在一处，给合盖与倾斜效果用。
//
// 为什么要有这一层：**CGSessionCopyCurrentDictionary 是一次同步的 WindowServer 往返**（机器忙时单次
// 约 0.2 ms CPU，主线程还要等几毫秒）。桌面效果每帧都要问“现在锁没锁”，一帧一次就是每秒 60 次；
// 传感器 62 次/秒的读数路径上也问。这一层把“问”收敛成：**通知只触发重读，重读之后大家读缓存**；
// 效果真在跑的时候，渲染循环每帧只读缓存，另按最长 1 秒复查一次（通知丢了、或者通知到了但状态还没
// 跟上，最多错一秒）——从每秒 60 次降到每秒最多 1 次。
//
// 规矩（照 Glance 那份调研里定下的）：
// - 通知可被同用户进程伪造、也可能在挂起时丢掉，所以它只用来触发重读，不直接授权显示；
// - 读不到、字段语义不明时一律当成 **unknown**，而 unknown **不许**当成“解锁了”；
// - 新增的锁屏相关能力遇到 unknown 就不显示，不猜。
import Cocoa

/// 不是 @MainActor：调用方（DuoController 及其通知回调）不都在主线程隔离域里。
/// 状态很小，用一把锁护住，和 AppleSPUAccelerometer 里 published 的做法一致；
/// 拿锁的时候绝不调用 WindowServer（IPC 放在锁外面）。
enum EffectEnvironment {
    typealias LockState = SessionLockState

    private struct State {
        var lock: LockState = .unknown
        var asleep = false
        var displayAwake = true
        var generation: UInt64 = 0
        var queries = 0
        var lastQuery: CFTimeInterval = 0
    }

    private static let mutex = NSLock()
    private static var state = State()

    private static func read<T>(_ body: (State) -> T) -> T { mutex.withLock { body(state) } }
    private static func write(_ body: (inout State) -> Void) { mutex.withLock { body(&state) } }

    /// 能不能在屏幕上画效果。锁着、不知道锁没锁、正在睡、显示器睡了——都不行。
    static var allowsDisplay: Bool {
        read { $0.lock == .unlocked && !$0.asleep && $0.displayAwake }
    }

    static var lockState: LockState { read(\.lock) }
    static var asleep: Bool { read(\.asleep) }
    static var displayAwake: Bool { read(\.displayAwake) }
    /// 每次重读 +1：调用方拿它判断“我读到的是不是新一轮状态”。
    static var generation: UInt64 { read(\.generation) }
    /// 同步查询累计次数（探针和性能记录读它）。
    static var queries: Int { read(\.queries) }

    /// 重读权威状态。只在启动、状态转换和按需复查时调用，不在渲染 tick 里同步问。
    static func refresh() {
        // IPC 放在锁外面：不能一边拿着锁一边等 WindowServer。
        let locked = EffectSecurityBoundary.lockState
        let now = CACurrentMediaTime()
        write {
            $0.queries += 1
            $0.lastQuery = now
            $0.lock = locked
            $0.generation &+= 1
        }
    }

    /// 效果正在跑的时候按秒复查：通知丢了最多错一秒，不再一帧问一次。
    static func recheckIfStale(interval: CFTimeInterval = 1) {
        guard CACurrentMediaTime() - read(\.lastQuery) >= interval else { return }
        refresh()
    }

    static func willSleep() {
        write {
            $0.asleep = true
            $0.generation &+= 1
        }
    }

    static func didWake() {
        write {
            $0.asleep = false
            $0.displayAwake = true
        }
        refresh()
    }

    static func displaySlept() {
        write {
            $0.displayAwake = false
            $0.generation &+= 1
        }
    }

    static func displayWoke() {
        write { $0.displayAwake = true }
        refresh()
    }

    /// 探针与单测用：把状态摆到指定值（不写用户的任何设置）。
    static func resetForProbe(lock: LockState = .unknown, asleep: Bool = false, displayAwake: Bool = true) {
        let now = CACurrentMediaTime()
        write {
            $0.lock = lock
            $0.asleep = asleep
            $0.displayAwake = displayAwake
            $0.lastQuery = now
            $0.generation &+= 1
        }
    }
}
