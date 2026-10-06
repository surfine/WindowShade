import Foundation

/// 图像准备的代际策略（PERF-05）：每个目标各有一条代际线。
/// 新请求一进来就作废旧请求，worker 完成时用它判断结果是否还该换入。
struct FoldPrepPolicy {
    enum Target: String, CaseIterable {
        case primary
        case background
    }

    private var generations: [Target: UInt64] = [:]

    /// 作废该目标的旧请求，并给新请求一个号。
    mutating func supersede(_ target: Target) -> UInt64 {
        let next = (generations[target] ?? 0) &+ 1
        generations[target] = next
        return next
    }

    /// 结果是否仍属于该目标的当前代际。
    func isCurrent(_ target: Target, _ token: UInt64) -> Bool {
        generations[target] == token
    }

    mutating func reset() { generations.removeAll() }
}

/// 有界图像纹理缓存：键含来源身分、色彩空间与像素尺寸。
/// 超过容量按最久未用淘汰；来源、颜色或尺寸一变就是新键，旧项自然失效（也会被淘汰）。
/// 只缓存不随帧变化的静态图（首帧/背景/材质），实时帧不走这里。
final class FoldImageCache<Value>: @unchecked Sendable {
    struct Key: Hashable {
        let source: ObjectIdentifier
        let colorSpace: String
        let width: Int
        let height: Int
    }

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [Key: Value] = [:]
    private var order: [Key] = []
    private var hitCount = 0
    private var storeCount = 0
    private var evictionCount = 0

    init(capacity: Int = 4) {
        self.capacity = max(1, capacity)
    }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = entries[key] else { return nil }
        hitCount &+= 1
        touch(key)
        return value
    }

    func store(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        storeCount &+= 1
        entries[key] = value
        touch(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
            evictionCount &+= 1
        }
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        order.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    var hits: Int {
        lock.lock()
        defer { lock.unlock() }
        return hitCount
    }

    var stores: Int {
        lock.lock()
        defer { lock.unlock() }
        return storeCount
    }

    var evictions: Int {
        lock.lock()
        defer { lock.unlock() }
        return evictionCount
    }
}
