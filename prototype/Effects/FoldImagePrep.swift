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
/// PERF-12：可选字节预算（budgetBytes > 0 时生效）——整幅静图的共享 buffer 可以到几十 MB，
/// 只按条数封顶的话 4 条 5K 图就 ~200MB；超预算时同样按最久未用逐出，但永不逐出刚存进来的那条。
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
    private let budgetBytes: Int
    private let sizeOf: (Value) -> Int
    private var entries: [Key: Value] = [:]
    private var order: [Key] = []
    private var totalBytes = 0
    private var hitCount = 0
    private var storeCount = 0
    private var evictionCount = 0

    init(capacity: Int = 4, budgetBytes: Int = 0, sizeOf: @escaping (Value) -> Int = { _ in 0 }) {
        self.capacity = max(1, capacity)
        self.budgetBytes = max(0, budgetBytes)
        self.sizeOf = sizeOf
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
        if let old = entries.updateValue(value, forKey: key) { totalBytes -= sizeOf(old) }
        touch(key)
        totalBytes += sizeOf(value)
        while order.count > capacity, let oldest = order.first {
            drop(oldest)
        }
        while budgetBytes > 0, totalBytes > budgetBytes, order.count > 1, let oldest = order.first {
            drop(oldest)
        }
    }

    private func drop(_ key: Key) {
        order.removeFirst()
        if let removed = entries.removeValue(forKey: key) { totalBytes -= sizeOf(removed) }
        evictionCount &+= 1
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
        totalBytes = 0
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
