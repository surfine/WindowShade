import Foundation

/// 规格 R25：触控板上的手指数按物理设备分开记。内置触控板和外接妙控板同时有手指时，
/// 一块板上的手指变化不能覆盖、也不能结束另一块板上正在进行的手势。
/// 只有一块板时，产出的变化和以前「只数一个总数」完全一样（同一串帧，同样的 count / previous）。
///
/// 在监听线程上用（`PinchEventTap`）：每个手势事件按设备喂一帧，只在那块板的手指数变了时产出变化。
struct TouchOwnership: Sendable {
    /// 某块板的手指数变了。
    struct Change: Equatable, Sendable {
        var device: UInt64
        var count: Int
        var previous: Int
        /// 过期恢复补出来的「手指都离开了」：那块板最后一帧（离手帧）没收到，又很久没有新帧。
        /// 只用来更新计数，不能据此判定手势在这一刻结束（时间点是猜的）。
        var recovered: Bool
    }

    /// 一块板有手指却这么久没有新帧，而别的板来了帧：当作它的离手帧丢了，按全部离开处理，
    /// 免得它一直占着「有手指」，挡住之后的手势归属。手指在板上动着时每秒约 60 帧（实测），一秒很宽裕。
    static let staleGap: TimeInterval = 1.0

    private struct Entry: Sendable {
        var count: Int
        var lastSeen: TimeInterval
    }

    private var entries: [UInt64: Entry] = [:]
    /// 最近来帧的那块板。事件里一个触点都没有（看不出设备）时，算在它头上。
    private(set) var lastDevice: UInt64?

    init() {}

    /// 看不出设备的帧（没有触点、或系统没给设备）归到最近那块板；一块都没见过时归到 0。
    func key(for device: UInt64?) -> UInt64 {
        device ?? lastDevice ?? 0
    }

    /// 喂一帧：`device` 这块板此刻接触着 `count` 根手指。返回这一帧产出的变化（可能为空）：
    /// 先是别的板的过期恢复（按设备号排序），最后是这块板自己的变化。
    mutating func frame(device: UInt64?, count: Int, time: TimeInterval) -> [Change] {
        let key = key(for: device)
        var changes: [Change] = []
        // 只有这一块板（最常见）时不必扫别的板：每帧不多分配。
        let others = entries.count > 1 || (entries.count == 1 && entries[key] == nil)
        for (other, entry) in (others ? entries.sorted(by: { $0.key < $1.key }) : []) where other != key {
            if entry.count > 0, time - entry.lastSeen >= Self.staleGap {
                changes.append(Change(device: other, count: 0, previous: entry.count, recovered: true))
                entries[other] = nil
            } else if entry.count == 0 {
                entries[other] = nil
            }
        }
        let previous = entries[key]?.count ?? 0
        entries[key] = Entry(count: count, lastSeen: time)
        lastDevice = key
        if count != previous {
            changes.append(Change(device: key, count: count, previous: previous, recovered: false))
        }
        return changes
    }

    /// 测试用：这块板此刻记着几根手指。
    func count(of device: UInt64) -> Int { entries[device]?.count ?? 0 }
}

/// 主线程这一侧：每块板的手指数，以及「此刻是哪块板在用」（最近一块从没手指变成有手指、且还有手指的）。
/// 只有一块板时，`activeCount` 就是那块板最新的手指数，和以前直接取最新一次变化的 count 一样。
struct TouchRoster: Sendable {
    private var counts: [UInt64: Int] = [:]
    /// 有手指的板，按最近一次变化排序（最后一个最新）。
    private var order: [UInt64] = []

    init() {}

    mutating func apply(_ change: TouchOwnership.Change) {
        order.removeAll { $0 == change.device }
        if change.count > 0 {
            counts[change.device] = change.count
            order.append(change.device)
        } else {
            counts[change.device] = nil
        }
    }

    /// 此刻在用的板：最近一次变化后仍有手指的那块；都没手指时为 nil。
    var active: UInt64? { order.last }
    var activeCount: Int { active.map { counts[$0] ?? 0 } ?? 0 }
    /// 此刻有手指的板有几块。
    var touchingDevices: Int { order.count }
    func count(of device: UInt64) -> Int { counts[device] ?? 0 }
}
