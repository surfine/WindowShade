// 刘海实时活动：纯逻辑，只依赖 Foundation，不碰 AppKit。
//
// 设计要点（有界的取舍都写在对应注释里）：
// - 不引入 actor：调用方保证在 MainActor 上串行访问，内部不做线程同步。
// - 时间一律由调用方传入单调 clock（秒），store 只比较、不读系统时钟。
// - 缓存上限 32，按“信息价值”排序：录制 > 空投 > 路线 > 音乐 > 耳机，
//   同优先级用 startedAt 升序（先开始的更靠前），再以 id 稳定 tie-break。
// - 可见列表最多 3 条；选中项在其仍可见时保持粘滞，普通内容更新不跳选、不重排。

import Foundation

/// 活动卡片上能点的动作。纯数据，放在 Core 里：刘海和负一屏都发它，单测也不用带 App 那一层。
enum NotchActivityAction: String {
    case enableMusic, playPause, previous, next, airDrop, route, voiceMemos, open, end
    /// 番茄钟：开始 / 暂停、跳过、结束。动作由宿主转给唯一的 FocusTimerHost。
    case focusStart, focusPause, focusSkip, focusEnd
}

/// 活动的种类，决定默认排序权重。
enum NotchActivityKind: String, Codable, Sendable, CaseIterable {
    case music
    case airPods
    case airDrop
    case route
    case recording
    /// 番茄钟：用户自己开的计时，排在录音之后、隔空投送之前。
    case focus

    /// 权重数字越大越显眼，排在越前。
    var priority: Int {
        switch self {
        case .recording: return 90
        case .focus: return 85
        case .airDrop: return 80
        case .route: return 60
        case .music: return 40
        case .airPods: return 20
        }
    }
}

/// 一条实时活动。时间都是调用方提供的单调秒。
struct NotchActivity: Equatable, Sendable {
    let id: String
    let generation: UInt64
    let kind: NotchActivityKind
    var title: String
    var subtitle: String
    var symbol: String
    /// 开始时间（单调秒），越小越“老”。
    var startedAt: Double
    var updatedAt: Double
    /// 到点后自动消失；nil 表示不自动过期。
    var expiresAt: Double?
    /// 只有确实是 0...1 的报告进度才有值；缺失就保持 nil，不补假数。
    var progress: Double?
    var isPaused: Bool
    var detail: String

    init(
        id: String,
        generation: UInt64 = 0,
        kind: NotchActivityKind,
        title: String,
        subtitle: String = "",
        symbol: String = "",
        startedAt: Double,
        updatedAt: Double? = nil,
        expiresAt: Double? = nil,
        progress: Double? = nil,
        isPaused: Bool = false,
        detail: String = ""
    ) {
        self.id = id
        self.generation = generation
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.startedAt = startedAt
        // 没给 updatedAt 就沿用 startedAt：创建即“刚更新”。
        self.updatedAt = updatedAt ?? startedAt
        self.expiresAt = expiresAt
        self.progress = progress
        self.isPaused = isPaused
        self.detail = detail
    }
}

/// 实时活动的小缓存。只在 MainActor 上串行使用，因此不带 actor。
struct NotchActivityStore {
    /// 缓存上限：超出时拒绝新条目，保留已有条目。取 32 是为了单屏远大于可见 3 条，同时
    /// 让崩溃/异常源也不可能无限增长。
    static let capacity = 32
    /// 可见条数上限。
    static let visibleLimit = 3
    /// 墓碑上限：只记住每个 id 见过的最大 generation，不记旧时间戳。
    static let tombstoneLimit = 64

    private var storage: [String: NotchActivity] = [:]
    /// id -> 见过的最大 generation。end 之后同代不得复活；新代显式可重开。
    private var tombstones: [String: UInt64] = [:]
    /// 墓碑插入顺序：满了按 FIFO 淘汰最旧的，保证“最近结束的仍拦同代”。
    private var tombstoneOrder: [String] = []
    private var selection: String?
    /// 全局单调水位：任何接口传进来的 now 必须 >= 水位，否则整次调用被拒绝。
    /// 同一 now 合法（同一时刻的多个事件）。水位不因 reset/prune 而丢。
    private var watermark: Double?

    init() {}

    // MARK: - 只读视图

    /// 所有活动，已按展示顺序排好。
    var activities: [NotchActivity] {
        storage.values.sorted(by: Self.order)
    }

    /// 最多 3 条可见的活动（就是排序后的前缀）。
    var visible: [NotchActivity] {
        Array(activities.prefix(Self.visibleLimit))
    }

    var selectedID: String? { selection }

    var selected: NotchActivity? {
        guard let id = selection else { return nil }
        return storage[id]
    }

    // MARK: - 变更

    /// 插入或更新一条活动。返回是否真的改变了存储。
    ///
    /// 明确的有界策略：插入受 32 上限约束，放不下就被丢弃；但绝不淘汰已有的
    /// 活动（不做 LRU/优先级驱逐）。这样避免“被 evict 后旧 updatedAt 又反弹”
    /// 的老问题——被丢弃的新条目下次可再试，而已有状态不因容量抖动。代价是极端
    /// 超量时较新但低优先的活动可能进不来，需要上游自己控量。
    @discardableResult
    mutating func upsert(_ activity: NotchActivity, now: Double) -> Bool {
        guard Self.validNow(now), now >= (watermark ?? -.infinity) else { return false }
        // 整条内容先过一遍校验，任何一项不合格都整次拒绝，避免半更新。
        guard Self.isValid(activity), activity.startedAt <= now, activity.updatedAt <= now else { return false }

        // 已经过期就不进来（此时还未推进水位：被忽略的输入不该改变时间基准）。
        if let exp = activity.expiresAt, now >= exp { return false }

        // end 过的旧 generation 不得复活；同代还要看 updatedAt 不能倒退。
        if let closed = tombstones[activity.id],
           activity.generation < closed || activity.generation == closed {
            return false
        }
        if let current = storage[activity.id] {
            if activity.generation < current.generation { return false }
            if activity.generation == current.generation, activity.updatedAt < current.updatedAt {
                return false
            }
        } else if storage.count >= Self.capacity {
            // 满了：有界丢弃，不驱逐既有条目。
            return false
        }

        watermark = max(watermark ?? -.infinity, now)
        storage[activity.id] = activity
        // 选中的条目若被同代普通更新（甚至 content 变化）保持选中；只有它不再
        // 可见时才由 select 清理。
        Self.reconcileSelection(&selection, storage: storage)
        return true
    }

    /// 结束一条活动。只有代与 id 都匹配才算数（旧代结束不了新代）。
    @discardableResult
    mutating func end(id: String, generation: UInt64, now: Double) -> Bool {
        guard Self.validNow(now), now >= (watermark ?? -.infinity) else { return false }
        guard let current = storage[id], current.generation == generation else { return false }
        watermark = max(watermark ?? -.infinity, now)
        storage.removeValue(forKey: id)
        registerTombstone(id: id, generation: generation)
        Self.reconcileSelection(&selection, storage: storage)
        return true
    }

    /// 清掉已过期的条目，并顺带清理墓碑。
    /// 注意：水位不因 prune 重置，旧 now 在 prune 之后依然会被拒。
    mutating func prune(now: Double) {
        guard Self.validNow(now), now >= (watermark ?? -.infinity) else { return }
        watermark = max(watermark ?? -.infinity, now)
        for (id, activity) in storage {
            if let exp = activity.expiresAt, now >= exp {
                storage.removeValue(forKey: id)
                registerTombstone(id: id, generation: activity.generation)
            }
        }
        Self.reconcileSelection(&selection, storage: storage)
    }

    /// 选中某个 id。只有当前可见的条目才能被选中。
    @discardableResult
    mutating func select(id: String) -> Bool {
        guard visible.contains(where: { $0.id == id }) else { return false }
        selection = id
        return true
    }

    /// 在可见项之间循环切换选中。by 为 0 且已有选中时不动。
    mutating func moveSelection(by delta: Int) {
        let vis = visible
        guard !vis.isEmpty else { selection = nil; return }
        guard let current = selection, let index = vis.firstIndex(where: { $0.id == current }) else {
            selection = vis[0].id
            return
        }
        // 用取模避免超大 step 上的整数溢出。
        let count = vis.count
        let step = ((delta % count) + count) % count
        selection = vis[(index + step) % count].id
    }

    // MARK: - 校验与排序

    private static func validNow(_ now: Double) -> Bool {
        now.isFinite && now >= 0
    }

    /// 一条活动是否整体合法。
    private static func isValid(_ activity: NotchActivity) -> Bool {
        guard activity.startedAt.isFinite, activity.startedAt >= 0 else { return false }
        guard activity.updatedAt.isFinite, activity.updatedAt >= 0 else { return false }
        guard activity.updatedAt >= activity.startedAt else { return false }
        if let exp = activity.expiresAt {
            guard exp.isFinite, exp >= 0 else { return false }
        }
        if let p = activity.progress {
            guard p.isFinite, p >= 0, p <= 1 else { return false }
        }
        return true
    }

    /// 展示顺序：优先级降序，startedAt 升序（老的在前），id 升序稳定 tie-break。
    /// 刻意不看 updatedAt，避免普通内容更新导致重排。
    private static func order(_ a: NotchActivity, _ b: NotchActivity) -> Bool {
        if a.kind.priority != b.kind.priority { return a.kind.priority > b.kind.priority }
        if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
        return a.id < b.id
    }

    /// 选中项一旦不在可见前三就清掉；仍然可见则原样保留（粘滞）。
    private static func reconcileSelection(_ selection: inout String?, storage: [String: NotchActivity]) {
        guard let current = selection else { return }
        let top = storage.values.sorted(by: order).prefix(visibleLimit).map(\.id)
        if !top.contains(current) {
            selection = nil
        }
    }

    /// 记录墓碑并做有界清理：FIFO 淘汰最旧的 id（保留最近的结束记录）。
    private mutating func registerTombstone(id: String, generation: UInt64) {
        if let existing = tombstones[id] {
            tombstones[id] = max(existing, generation)
            return
        }
        tombstones[id] = generation
        tombstoneOrder.append(id)
        while tombstoneOrder.count > Self.tombstoneLimit {
            let victim = tombstoneOrder.removeFirst()
            tombstones.removeValue(forKey: victim)
        }
    }
}
