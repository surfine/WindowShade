// 新窗口浏览功能的缩略图服务：有界缓存、在途请求登记、订阅取消与并发预算。
// 与折叠路径的 WindowSnapshotCache 完全分开：这里只保存新面板自己的静态图，
// 不把低分辨率缩略图交给原貌卷帘的完整标题栏捕获，也不延长折叠截图的寿命。
//
// 记账模型把四件事分开：
// - 逻辑请求键 `WindowThumbnailKey`（窗口身份 + 档位 + 失效代数）；
// - 实际运行的物理任务 `Job`（不可复用的 JobID，queued/running/finished）；
// - 消费者订阅 `WindowThumbnailSubscription`（完成、失败、取消后都进入终态）；
// - 已完成图像缓存 `entries`。
//
// 只有 `drainQueueLocked()` 能把任务从 queued 变成 running；已经真正开始的物理
// 任务即使被界面取消也继续占用并发额度，直到后端的真实完成回调用 JobID 结算。

import Cocoa

enum WindowThumbnailPurpose: String, Hashable {
    case card
    case listRow
    case selectedLarge

    var maxPixelSize: CGSize {
        switch self {
        case .card, .listRow: return CGSize(width: 512, height: 320)
        case .selectedLarge: return CGSize(width: 1024, height: 768)
        }
    }
}

struct WindowThumbnailKey: Hashable {
    let windowKey: WindowKey
    let purpose: WindowThumbnailPurpose
    /// 档位化的请求像素上限；同档位请求共享任务。
    let pixelClass: Int
    /// 权限/排除规则/应用代数变化时递增，旧结果不得重新进入缓存或 UI。
    let captureVersion: UInt64

    init(windowKey: WindowKey, purpose: WindowThumbnailPurpose,
         maxPixelSize: CGSize, captureVersion: UInt64) {
        self.windowKey = windowKey
        self.purpose = purpose
        self.pixelClass = (max(1, Int(maxPixelSize.width)) / 8) << 12
            | (max(1, Int(maxPixelSize.height)) / 8)
        self.captureVersion = captureVersion
    }
}

struct WindowThumbnailRequest {
    let key: WindowThumbnailKey
    let logicalSize: CGSize
    let maxPixelSize: CGSize
}

enum WindowThumbnailFailure: Error, Equatable {
    case invalidGeometry
    case permissionDenied
    case excluded
    case windowGone
    case captureFailed(String)
}

protocol WindowThumbnailBackend: AnyObject {
    /// 只接受明确目标的单窗捕获；不得退化为整屏截图后按坐标裁切。
    /// 已经真正开始的物理任务必须回传恰好一次终态；尚未开始的排队任务可以直接取消。
    func capture(request: WindowThumbnailRequest,
                 completion: @escaping (Result<CGImage, WindowThumbnailFailure>) -> Void)
    /// 系统调用已经开始且无法真正取消：服务仍需把它计入在途预算，直到返回。
    func cancel(request: WindowThumbnailRequest)
}

/// 不可复用的任务标识：同一窗口键的旧任务与新任务必须能区分。
struct WindowThumbnailJobID: Hashable, Comparable {
    let value: UInt64

    static func < (lhs: WindowThumbnailJobID, rhs: WindowThumbnailJobID) -> Bool {
        lhs.value < rhs.value
    }
}

enum WindowThumbnailJobState: String {
    case queued
    case running
    case finished
}

final class WindowThumbnailSubscription {
    let id: UInt64
    /// 图像投递。进入终态后一定被清空，避免闭包继续持有控制器或视图。
    fileprivate var onImage: ((CGImage) -> Void)?
    fileprivate var onFailure: ((WindowThumbnailFailure) -> Void)?
    /// 终态通知：完成、失败、取消都会调用一次，控制器据此确认订阅已经终结。
    fileprivate(set) var onFinish: (() -> Void)?
    /// 取消入口用 weak 捕获持有它的服务与订阅，因此订阅不会自持有。
    fileprivate var cancelAction: (() -> Void)?
    private(set) var isFinished = false
    fileprivate(set) var isCancelled = false
    var isActive: Bool { !isFinished }

    init(id: UInt64 = 0) {
        self.id = id
    }

    func cancel() {
        guard !isFinished else { return }
        isCancelled = true
        let action = cancelAction
        cancelAction = nil
        action?()
        // 服务侧结算时也会调用 finishTerminal；这里兜底处理服务已释放的情况。
        finishTerminal(image: nil, failure: nil)
    }

    /// 单一终态门：重复完成、重复取消、晚到回调都只生效一次。
    @discardableResult
    fileprivate func finishTerminal(image: CGImage?,
                                    failure: WindowThumbnailFailure?) -> Bool {
        guard !isFinished else { return false }
        isFinished = true
        let imageCallback = onImage
        let failureCallback = onFailure
        let finishCallback = onFinish
        onImage = nil
        onFailure = nil
        onFinish = nil
        cancelAction = nil
        if let image, let imageCallback {
            imageCallback(image)
        } else if let failure, let failureCallback {
            failureCallback(failure)
        }
        finishCallback?()
        return true
    }
}

final class WindowThumbnailService {
    private struct Entry {
        let image: CGImage
        let capturedAt: CFAbsoluteTime
        let cost: Int
        var lastUsed: UInt64
    }

    /// 一个逻辑请求键上的物理任务。只要物理调用尚未结算，服务就持有它的强引用。
    private final class Job {
        let id: WindowThumbnailJobID
        let request: WindowThumbnailRequest
        var consumers: [WindowThumbnailSubscription] = []
        var state: WindowThumbnailJobState = .queued
        /// 失效后仍保留任务对象用于额度结算，只是不再写缓存、不再投递界面。
        var publicationAllowed = true

        init(id: WindowThumbnailJobID, request: WindowThumbnailRequest) {
            self.id = id
            self.request = request
        }

        var liveConsumers: [WindowThumbnailSubscription] {
            consumers.filter { !$0.isFinished }
        }
    }

    private let lock = NSLock()
    private let backend: WindowThumbnailBackend
    private let budgetBytes: Int
    private let maxConcurrent: Int
    private let freshInterval: TimeInterval
    /// 后端长时间不回调后停止继续投放任务，界面按有界降级处理，而不是遗弃旧任务再开新任务。
    private let stallTimeout: TimeInterval
    private let now: () -> CFAbsoluteTime

    private var entries: [WindowThumbnailKey: Entry] = [:]
    private var totalCost = 0
    private var queuedJobs: [WindowThumbnailJobID: Job] = [:]
    private var queuedOrder: [WindowThumbnailJobID] = []
    private var runningJobs: [WindowThumbnailJobID: Job] = [:]
    /// 每个逻辑键当前活跃（queued/running）的任务；finished 后立刻移除。
    private var jobByKey: [WindowThumbnailKey: WindowThumbnailJobID] = [:]
    private var startedAtByJob: [WindowThumbnailJobID: CFAbsoluteTime] = [:]
    private var nextJobID: UInt64 = 1
    private var nextSubscriptionID: UInt64 = 1
    private var useCounter: UInt64 = 0
    private var captureVersion: UInt64 = 1
    private var backendStalled = false
    /// 锁内产生、必须在解锁后才投递的终态失败：订阅回调绝不能在持锁时执行，
    /// 否则回调里再调用本服务就会在不可重入的 NSLock 上死锁。
    private var pendingFailuresLocked: [(WindowThumbnailSubscription, WindowThumbnailFailure)] = []

    // MARK: 诊断计数（全部在锁内更新）

    private(set) var deliveredCount = 0
    private(set) var startedCount = 0
    private(set) var duplicateCompletionCount = 0
    private(set) var staleResultCount = 0
    private(set) var queuedCancelCount = 0
    private(set) var stallDeGradeCount = 0

    init(backend: WindowThumbnailBackend,
         budgetBytes: Int = 24 * 1024 * 1024,
         maxConcurrent: Int = 2,
         freshInterval: TimeInterval = 3.0,
         stallTimeout: TimeInterval = 15.0,
         now: @escaping () -> CFAbsoluteTime = { CFAbsoluteTimeGetCurrent() }) {
        self.backend = backend
        self.budgetBytes = max(1, budgetBytes)
        self.maxConcurrent = max(1, maxConcurrent)
        self.freshInterval = freshInterval
        self.stallTimeout = max(0.1, stallTimeout)
        self.now = now
    }

    // MARK: 只读诊断

    var cachedCostBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCost
    }

    var cachedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// 活跃逻辑请求数（排队 + 运行）。
    var inFlightCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return queuedJobs.count + runningJobs.count
    }

    var queuedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return queuedJobs.count
    }

    /// 真实占用的并发额度：从 runningJobs 派生，避免维护第二份容易不一致的真相。
    var runningCaptureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningJobs.count
    }

    var backendIsStalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return backendStalled
    }

    /// 一次性诊断快照：取消率、过期结果丢弃率与物理截图数量都在这里汇总，
    /// 供控制器在关闭面板/停止功能时写进日志（§17.1）。
    struct Diagnostics {
        let started: Int
        let delivered: Int
        let queuedCancelled: Int
        let staleResults: Int
        let duplicateCompletions: Int
        let stalledBatches: Int
        let running: Int
        let queued: Int
        let cachedBytes: Int
        let cachedCount: Int
    }

    func diagnostics() -> Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return Diagnostics(started: startedCount, delivered: deliveredCount,
                           queuedCancelled: queuedCancelCount,
                           staleResults: staleResultCount,
                           duplicateCompletions: duplicateCompletionCount,
                           stalledBatches: stallDeGradeCount,
                           running: runningJobs.count, queued: queuedJobs.count,
                           cachedBytes: totalCost, cachedCount: entries.count)
    }

    func jobState(windowKey: WindowKey, purpose: WindowThumbnailPurpose,
                  maxPixelSize: CGSize? = nil) -> WindowThumbnailJobState? {
        let limit = maxPixelSize ?? purpose.maxPixelSize
        lock.lock()
        defer { lock.unlock() }
        let key = WindowThumbnailKey(windowKey: windowKey, purpose: purpose,
                                     maxPixelSize: limit, captureVersion: captureVersion)
        guard let id = jobByKey[key] else { return nil }
        return runningJobs[id]?.state ?? queuedJobs[id]?.state
    }

    // MARK: 失效

    /// 权限撤销、排除规则修改、应用终止时调用：旧结果不能晚到后重新进入缓存。
    /// 排队任务直接取消；已经开始的物理任务保留在 runningJobs 中继续占额度，
    /// 但不再发布结果。晚到的完成仍按 JobID 归还额度。
    func invalidateAll() {
        var cancellations: [Job] = []
        var failures: [(WindowThumbnailSubscription, WindowThumbnailFailure)] = []
        lock.lock()
        captureVersion &+= 1
        entries.removeAll()
        totalCost = 0
        for job in queuedJobs.values {
            job.state = .finished
            job.publicationAllowed = false
            if jobByKey[job.request.key] == job.id {
                jobByKey.removeValue(forKey: job.request.key)
            }
            queuedCancelCount += 1
            for consumer in job.consumers where !consumer.isFinished {
                consumer.isCancelled = true
                failures.append((consumer, .excluded))
            }
            job.consumers.removeAll()
        }
        queuedJobs.removeAll()
        queuedOrder.removeAll()
        for job in runningJobs.values {
            job.publicationAllowed = false
            staleResultCount += 1
            cancellations.append(job)
            // 同一键的新请求必须得到新的 JobID，旧任务不能占着登记。
            if jobByKey[job.request.key] == job.id {
                jobByKey.removeValue(forKey: job.request.key)
            }
            for consumer in job.consumers where !consumer.isFinished {
                consumer.isCancelled = true
                failures.append((consumer, .excluded))
            }
            job.consumers.removeAll()
        }
        lock.unlock()
        for job in cancellations { backend.cancel(request: job.request) }
        for (consumer, failure) in failures {
            consumer.finishTerminal(image: nil, failure: failure)
        }
    }

    func invalidate(windowKey: WindowKey) {
        var cancellations: [Job] = []
        var failures: [(WindowThumbnailSubscription, WindowThumbnailFailure)] = []
        lock.lock()
        let keys = entries.keys.filter { $0.windowKey == windowKey }
        for key in keys {
            if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
        }
        for job in queuedJobs.values where job.request.key.windowKey == windowKey {
            job.state = .finished
            job.publicationAllowed = false
            queuedJobs.removeValue(forKey: job.id)
            queuedOrder.removeAll { $0 == job.id }
            if jobByKey[job.request.key] == job.id {
                jobByKey.removeValue(forKey: job.request.key)
            }
            queuedCancelCount += 1
            for consumer in job.consumers where !consumer.isFinished {
                consumer.isCancelled = true
                failures.append((consumer, .windowGone))
            }
            job.consumers.removeAll()
        }
        for job in runningJobs.values where job.request.key.windowKey == windowKey {
            job.publicationAllowed = false
            staleResultCount += 1
            cancellations.append(job)
            if jobByKey[job.request.key] == job.id {
                jobByKey.removeValue(forKey: job.request.key)
            }
            for consumer in job.consumers where !consumer.isFinished {
                consumer.isCancelled = true
                failures.append((consumer, .windowGone))
            }
            job.consumers.removeAll()
        }
        lock.unlock()
        for job in cancellations { backend.cancel(request: job.request) }
        for (consumer, failure) in failures {
            consumer.finishTerminal(image: nil, failure: failure)
        }
    }

    // MARK: 缓存读取

    func cachedImage(for key: WindowThumbnailKey) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key],
              now() - entry.capturedAt < freshInterval else { return nil }
        useCounter &+= 1
        entry.lastUsed = useCounter
        entries[key] = entry
        return entry.image
    }

    /// 按窗口与档位取仍然新鲜的缓存图（内部使用当前失效代数，调用方不需要拼键）。
    func freshImage(windowKey: WindowKey, purpose: WindowThumbnailPurpose) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = WindowThumbnailKey(windowKey: windowKey, purpose: purpose,
                                     maxPixelSize: purpose.maxPixelSize,
                                     captureVersion: captureVersion)
        guard var entry = entries[key], now() - entry.capturedAt < freshInterval else { return nil }
        useCounter &+= 1
        entry.lastUsed = useCounter
        entries[key] = entry
        return entry.image
    }

    /// 是否已有仍然新鲜的缓存图像（不改变最近使用顺序，供刷新决策读取）。
    func hasFreshImage(for key: WindowThumbnailKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return false }
        return now() - entry.capturedAt < freshInterval
    }

    /// 过期但合法的最后画面：用于折叠/最小化窗口的“快照”展示，不触发任何新截图，
    /// 也不改变新鲜度判定（`cachedImage` 仍会认为它过期）。
    func snapshotImage(windowKey: WindowKey, purpose: WindowThumbnailPurpose) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = WindowThumbnailKey(windowKey: windowKey, purpose: purpose,
                                     maxPixelSize: purpose.maxPixelSize,
                                     captureVersion: captureVersion)
        guard var entry = entries[key] else { return nil }
        useCounter &+= 1
        entry.lastUsed = useCounter
        entries[key] = entry
        return entry.image
    }

    // MARK: 请求

    /// 请求缩略图。缓存命中立即回调；否则登记/共享在途请求。
    @discardableResult
    func request(windowKey: WindowKey, purpose: WindowThumbnailPurpose,
                 logicalSize: CGSize,
                 maxPixelSize: CGSize? = nil,
                 priority: Bool = false,
                 onImage: @escaping (CGImage) -> Void,
                 onFailure: ((WindowThumbnailFailure) -> Void)? = nil,
                 onFinish: (() -> Void)? = nil) -> WindowThumbnailSubscription {
        lock.lock()
        nextSubscriptionID &+= 1
        let subscription = WindowThumbnailSubscription(id: nextSubscriptionID)
        let version = captureVersion
        lock.unlock()
        subscription.onImage = onImage
        subscription.onFailure = onFailure
        subscription.onFinish = onFinish

        let limit = maxPixelSize ?? purpose.maxPixelSize
        // 源窗口几何与输出分配分开校验：逻辑尺寸很大的窗口仍然可以生成很小缩略图。
        guard Self.isValidSourceSize(logicalSize), Self.isValidOutputSize(limit) else {
            subscription.finishTerminal(image: nil, failure: .invalidGeometry)
            return subscription
        }

        var immediateImage: CGImage?
        var starts: [Job] = []
        var stallFailure: WindowThumbnailFailure?

        lock.lock()
        let key = WindowThumbnailKey(windowKey: windowKey, purpose: purpose,
                                     maxPixelSize: limit, captureVersion: version)
        let request = WindowThumbnailRequest(key: key, logicalSize: logicalSize,
                                             maxPixelSize: limit)
        if var entry = entries[key], now() - entry.capturedAt < freshInterval {
            useCounter &+= 1
            entry.lastUsed = useCounter
            entries[key] = entry
            immediateImage = entry.image
        } else if let existingID = jobByKey[key],
                  let existing = runningJobs[existingID] ?? queuedJobs[existingID] {
            // 同一逻辑键共享已在途的任务；优先级提升只调整排队顺序。
            existing.consumers.append(subscription)
            if priority, existing.state == .queued {
                promoteLocked(existingID)
            }
        } else if updateBackendStallLocked() {
            stallFailure = .captureFailed("截图后端长时间无响应")
            stallDeGradeLocked()
        } else {
            let id = WindowThumbnailJobID(value: nextJobID)
            nextJobID &+= 1
            let job = Job(id: id, request: request)
            job.consumers.append(subscription)
            queuedJobs[id] = job
            jobByKey[key] = id
            if priority {
                queuedOrder.insert(id, at: 0)
            } else {
                queuedOrder.append(id)
            }
            starts = drainQueueLocked()
        }
        if immediateImage != nil { deliveredCount += 1 }
        let droppedFailures = takePendingFailuresLocked()
        lock.unlock()

        subscription.cancelAction = { [weak self, weak subscription] in
            guard let self, let subscription else { return }
            self.cancelSubscription(subscription, key: key)
        }
        deliver(droppedFailures)
        if let immediateImage {
            subscription.finishTerminal(image: immediateImage, failure: nil)
        } else if let stallFailure {
            subscription.finishTerminal(image: nil, failure: stallFailure)
        }
        startBackend(starts)
        return subscription
    }

    /// 选中项变化时提升排队优先级：已经在运行的任务不会被重新启动。
    func promote(windowKey: WindowKey, purpose: WindowThumbnailPurpose,
                 maxPixelSize: CGSize? = nil) {
        let limit = maxPixelSize ?? purpose.maxPixelSize
        lock.lock()
        defer { lock.unlock() }
        let key = WindowThumbnailKey(windowKey: windowKey, purpose: purpose,
                                     maxPixelSize: limit, captureVersion: captureVersion)
        guard let id = jobByKey[key], queuedJobs[id] != nil else { return }
        promoteLocked(id)
    }

    // MARK: 内部：排队与完成

    private func promoteLocked(_ id: WindowThumbnailJobID) {
        queuedOrder.removeAll { $0 == id }
        queuedOrder.insert(id, at: 0)
    }

    /// 唯一的 queued → running 入口。调用方必须持有锁。
    private func drainQueueLocked() -> [Job] {
        var starts: [Job] = []
        while runningJobs.count < maxConcurrent, !queuedOrder.isEmpty {
            let id = queuedOrder.removeFirst()
            guard let job = queuedJobs.removeValue(forKey: id) else { continue }
            let hasDemand = !job.liveConsumers.isEmpty
            let isCurrentKey = jobByKey[job.request.key] == job.id
            guard job.publicationAllowed, hasDemand, isCurrentKey else {
                job.state = .finished
                if isCurrentKey { jobByKey.removeValue(forKey: job.request.key) }
                for consumer in job.liveConsumers {
                    consumer.isCancelled = true
                    pendingFailuresLocked.append((consumer, .windowGone))
                }
                job.consumers.removeAll()
                continue
            }
            job.state = .running
            runningJobs[id] = job
            starts.append(job)
        }
        return starts
    }

    /// 取走锁内积累的待投递失败（调用方持锁），解锁后再逐个结算。
    private func takePendingFailuresLocked()
        -> [(WindowThumbnailSubscription, WindowThumbnailFailure)] {
        let pending = pendingFailuresLocked
        pendingFailuresLocked.removeAll()
        return pending
    }

    private func deliver(_ failures: [(WindowThumbnailSubscription, WindowThumbnailFailure)]) {
        for (consumer, failure) in failures where !consumer.isFinished {
            consumer.finishTerminal(image: nil, failure: failure)
        }
    }

    private func startBackend(_ jobs: [Job]) {
        for job in jobs {
            lock.lock()
            startedCount += 1
            startedAtByJob[job.id] = now()
            lock.unlock()
            let jobID = job.id
            backend.capture(request: job.request) { [weak self] result in
                guard let self else { return }
                self.finish(jobID: jobID, result: result)
            }
        }
    }

    private func finish(jobID: WindowThumbnailJobID,
                        result: Result<CGImage, WindowThumbnailFailure>) {
        var starts: [Job] = []
        var deliveries: [(WindowThumbnailSubscription, CGImage?, WindowThumbnailFailure?)] = []

        lock.lock()
        // 先按 JobID 找运行登记；重复完成、重入回调都不得二次减计数。
        guard let job = runningJobs.removeValue(forKey: jobID) else {
            duplicateCompletionCount += 1
            lock.unlock()
            return
        }
        job.state = .finished
        startedAtByJob.removeValue(forKey: jobID)
        // 后端恢复响应：解除停滞降级，允许后续任务继续。
        backendStalled = false
        if jobByKey[job.request.key] == jobID {
            jobByKey.removeValue(forKey: job.request.key)
        }
        let publishable = job.publicationAllowed
            && job.request.key.captureVersion == captureVersion
        let consumers = job.consumers
        job.consumers.removeAll()
        switch result {
        case .success(let image):
            if publishable {
                _ = storeLocked(image, key: job.request.key)
                deliveries = consumers.map { ($0, image, nil) }
            } else {
                staleResultCount += 1
                deliveries = consumers.map { ($0, nil, WindowThumbnailFailure.windowGone) }
            }
        case .failure(let failure):
            deliveries = consumers.map { ($0, nil, Optional(failure)) }
        }
        starts = drainQueueLocked()
        deliveredCount += deliveries.filter { $0.1 != nil && !$0.0.isFinished }.count
        let droppedFailures = takePendingFailuresLocked()
        lock.unlock()

        deliver(droppedFailures)
        for (consumer, image, failure) in deliveries {
            if consumer.isFinished { continue }
            if let image {
                consumer.finishTerminal(image: image, failure: nil)
            } else if let failure {
                consumer.finishTerminal(image: nil, failure: failure)
            }
        }
        startBackend(starts)
    }

    private func cancelSubscription(_ subscription: WindowThumbnailSubscription,
                                    key: WindowThumbnailKey) {
        var requestToCancel: WindowThumbnailRequest?
        lock.lock()
        guard let id = jobByKey[key],
              let job = runningJobs[id] ?? queuedJobs[id] else {
            lock.unlock()
            return
        }
        job.consumers.removeAll { $0 === subscription }
        let hasDemand = !job.liveConsumers.isEmpty
        switch job.state {
        case .queued:
            if !hasDemand {
                job.state = .finished
                job.publicationAllowed = false
                queuedJobs.removeValue(forKey: job.id)
                queuedOrder.removeAll { $0 == job.id }
                if jobByKey[job.request.key] == job.id {
                    jobByKey.removeValue(forKey: job.request.key)
                }
                queuedCancelCount += 1
            }
        case .running:
            if !hasDemand {
                // 系统调用已经开始：结果不再投递，但额度保留到真实完成。
                job.publicationAllowed = false
                requestToCancel = job.request
            }
        case .finished:
            break
        }
        lock.unlock()
        if let requestToCancel { backend.cancel(request: requestToCancel) }
    }

    /// 后端长期不回调：停止继续投放，并让等待中的需求得到明确的失败状态。
    private func updateBackendStallLocked() -> Bool {
        guard !backendStalled else { return true }
        let current = now()
        for job in runningJobs.values {
            let started = startedAtByJob[job.id] ?? current
            if current - started > stallTimeout {
                backendStalled = true
                return true
            }
        }
        return false
    }

    private func stallDeGradeLocked() {
        guard !queuedOrder.isEmpty else { return }
        stallDeGradeCount += 1
        let pending = queuedOrder
        queuedOrder.removeAll()
        for id in pending {
            guard let job = queuedJobs.removeValue(forKey: id) else { continue }
            job.state = .finished
            job.publicationAllowed = false
            if jobByKey[job.request.key] == job.id {
                jobByKey.removeValue(forKey: job.request.key)
            }
            for consumer in job.consumers where !consumer.isFinished {
                pendingFailuresLocked.append(
                    (consumer, .captureFailed("截图后端长时间无响应")))
            }
            job.consumers.removeAll()
        }
    }

    private func storeLocked(_ image: CGImage, key: WindowThumbnailKey) -> Bool {
        let rowBytes = Int64(image.bytesPerRow)
        let height = Int64(image.height)
        guard rowBytes > 0, height > 0 else { return false }
        let raw = rowBytes * height
        guard raw > 0, raw < Int64(Int.max / 2) else { return false }
        let cost = Int(raw) + Int(raw) / 10
        useCounter &+= 1
        if let old = entries[key] { totalCost -= old.cost }
        entries[key] = Entry(image: image, capturedAt: now(), cost: cost, lastUsed: useCounter)
        totalCost += cost
        evictIfNeededLocked()
        return true
    }

    private func evictIfNeededLocked() {
        while totalCost > budgetBytes,
              let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }

    /// 源窗口逻辑尺寸：只要求有限且为正；超过 4096 的源窗口仍可生成小缩略图。
    static func isValidSourceSize(_ size: CGSize) -> Bool {
        guard size.width.isFinite, size.height.isFinite else { return false }
        return size.width > 0 && size.height > 0
    }

    /// 输出分配预算：防止无穷值、负数、溢出与异常超大分配。
    static func isValidOutputSize(_ size: CGSize) -> Bool {
        guard size.width.isFinite, size.height.isFinite else { return false }
        guard size.width > 0, size.height > 0 else { return false }
        guard size.width <= 8192, size.height <= 8192 else { return false }
        let pixels = (size.width * size.height).rounded(.up)
        guard pixels.isFinite, pixels <= 33_554_432 else { return false }
        return true
    }

    private static func isValid(size: CGSize) -> Bool {
        isValidSourceSize(size) && isValidOutputSize(size)
    }
}
