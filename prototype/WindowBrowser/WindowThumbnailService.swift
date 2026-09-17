// 新窗口浏览功能的缩略图服务：有界缓存、在途请求登记、订阅取消与并发预算。
// 与折叠路径的 WindowSnapshotCache 完全分开：这里只保存新面板自己的静态图，
// 不把低分辨率缩略图交给原貌卷帘的完整标题栏捕获，也不延长折叠截图的寿命。

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
    /// completion 可能被调用零次（被取消/过期）或一次，服务都会正确处理。
    func capture(request: WindowThumbnailRequest,
                 completion: @escaping (Result<CGImage, WindowThumbnailFailure>) -> Void)
    /// 系统调用已经开始且无法真正取消：服务仍需把它计入在途预算，直到返回。
    func cancel(request: WindowThumbnailRequest)
}

final class WindowThumbnailSubscription {
    fileprivate var onImage: ((CGImage) -> Void)?
    fileprivate var onFailure: ((WindowThumbnailFailure) -> Void)?
    fileprivate var cancelAction: (() -> Void)?
    private var cancelled = false

    fileprivate init() {}

    var isCancelled: Bool { cancelled }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        let action = cancelAction
        cancelAction = nil
        action?()
    }

    fileprivate func deliver(_ image: CGImage) {
        guard !cancelled else { return }
        onImage?(image)
    }

    fileprivate func fail(_ failure: WindowThumbnailFailure) {
        guard !cancelled else { return }
        onFailure?(failure)
    }
}

final class WindowThumbnailService {
    private struct Entry {
        let image: CGImage
        let capturedAt: CFAbsoluteTime
        let cost: Int
        var lastUsed: UInt64
    }

    private final class InFlight {
        let request: WindowThumbnailRequest
        var consumers: [WindowThumbnailSubscription] = []
        var started = false
        var cancelled = false

        init(request: WindowThumbnailRequest) {
            self.request = request
        }
    }

    private let lock = NSLock()
    private let backend: WindowThumbnailBackend
    private let budgetBytes: Int
    private let maxConcurrent: Int
    private let freshInterval: TimeInterval
    private let now: () -> CFAbsoluteTime

    private var entries: [WindowThumbnailKey: Entry] = [:]
    private var totalCost = 0
    private var inFlight: [WindowThumbnailKey: InFlight] = [:]
    private var pending: [InFlight] = []
    private var runningCount = 0
    private var useCounter: UInt64 = 0
    private var captureVersion: UInt64 = 1

    private(set) var deliveredCount = 0
    private(set) var startedCount = 0

    init(backend: WindowThumbnailBackend,
         budgetBytes: Int = 24 * 1024 * 1024,
         maxConcurrent: Int = 2,
         freshInterval: TimeInterval = 3.0,
         now: @escaping () -> CFAbsoluteTime = { CFAbsoluteTimeGetCurrent() }) {
        self.backend = backend
        self.budgetBytes = max(1, budgetBytes)
        self.maxConcurrent = max(1, maxConcurrent)
        self.freshInterval = freshInterval
        self.now = now
    }

    var cachedCostBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCost
    }

    var inFlightCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight.count
    }

    var runningCaptureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningCount
    }

    /// 权限撤销、排除规则修改、应用终止时调用：旧结果不能晚到后重新进入缓存。
    func invalidateAll() {
        lock.lock()
        captureVersion &+= 1
        entries.removeAll()
        totalCost = 0
        let cancelled = inFlight.values
        inFlight.removeAll()
        pending.removeAll()
        for item in cancelled { item.cancelled = true }
        lock.unlock()
        for item in cancelled {
            backend.cancel(request: item.request)
            item.consumers.forEach { $0.fail(.excluded) }
        }
    }

    func invalidate(windowKey: WindowKey) {
        lock.lock()
        let keys = entries.keys.filter { $0.windowKey == windowKey }
        for key in keys {
            if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
        }
        let cancelled = inFlight.values.filter { $0.request.key.windowKey == windowKey }
        for item in cancelled {
            item.cancelled = true
            inFlight.removeValue(forKey: item.request.key)
            pending.removeAll { $0 === item }
        }
        lock.unlock()
        for item in cancelled {
            backend.cancel(request: item.request)
            item.consumers.forEach { $0.fail(.windowGone) }
        }
    }

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

    /// 请求缩略图。缓存命中立即回调；否则登记/共享在途请求。
    @discardableResult
    func request(windowKey: WindowKey, purpose: WindowThumbnailPurpose,
                 logicalSize: CGSize,
                 maxPixelSize: CGSize? = nil,
                 priority: Bool = false,
                 onImage: @escaping (CGImage) -> Void,
                 onFailure: ((WindowThumbnailFailure) -> Void)? = nil) -> WindowThumbnailSubscription {
        let subscription = WindowThumbnailSubscription()
        subscription.onImage = onImage
        subscription.onFailure = onFailure

        let limit = maxPixelSize ?? purpose.maxPixelSize
        guard Self.isValid(size: logicalSize), Self.isValid(size: limit) else {
            subscription.fail(.invalidGeometry)
            return subscription
        }

        var immediateImage: CGImage?
        var itemToStart: InFlight?

        lock.lock()
        let key = WindowThumbnailKey(windowKey: windowKey, purpose: purpose,
                                     maxPixelSize: limit, captureVersion: captureVersion)
        let request = WindowThumbnailRequest(key: key, logicalSize: logicalSize,
                                             maxPixelSize: limit)
        if var entry = entries[key], now() - entry.capturedAt < freshInterval {
            useCounter &+= 1
            entry.lastUsed = useCounter
            entries[key] = entry
            immediateImage = entry.image
        } else if let existing = inFlight[key], !existing.cancelled {
            existing.consumers.append(subscription)
        } else {
            let item = InFlight(request: request)
            item.consumers.append(subscription)
            inFlight[key] = item
            if priority {
                pending.insert(item, at: 0)
            } else {
                pending.append(item)
            }
            if runningCount < maxConcurrent {
                runningCount += 1
                item.started = true
                itemToStart = item
            }
        }
        lock.unlock()

        subscription.cancelAction = { [weak self] in
            self?.cancelSubscription(subscription, key: key)
        }
        if let immediateImage {
            subscription.deliver(immediateImage)
        } else if let itemToStart {
            start(itemToStart)
        }
        return subscription
    }

    // MARK: 内部

    private func cancelSubscription(_ subscription: WindowThumbnailSubscription,
                                    key: WindowThumbnailKey) {
        var requestToCancel: WindowThumbnailRequest?
        var alsoStop: InFlight?
        lock.lock()
        if let item = inFlight[key] {
            item.consumers.removeAll { $0 === subscription }
            if item.consumers.isEmpty, !item.started {
                item.cancelled = true
                inFlight.removeValue(forKey: key)
                pending.removeAll { $0 === item }
            } else if item.consumers.isEmpty, item.started {
                // 系统调用已经开始：仍然占用额度，但结果不再投递 UI。
                requestToCancel = item.request
                alsoStop = item
            }
        }
        lock.unlock()
        if let requestToCancel { backend.cancel(request: requestToCancel) }
        _ = alsoStop
    }

    private func start(_ item: InFlight) {
        startedCount += 1
        let key = item.request.key
        backend.capture(request: item.request) { [weak self, weak item] result in
            guard let self, let item else { return }
            self.finish(item, key: key, result: result)
        }
    }

    private func finish(_ item: InFlight, key: WindowThumbnailKey,
                        result: Result<CGImage, WindowThumbnailFailure>) {
        var nextToStart: InFlight?
        var delivery: (image: CGImage?, failure: WindowThumbnailFailure?,
                       consumers: [WindowThumbnailSubscription])?
        var cancelledRequest: WindowThumbnailRequest?

        lock.lock()
        let stillRegistered = inFlight[key] === item
        if stillRegistered { inFlight.removeValue(forKey: key) }
        runningCount = max(0, runningCount - 1)
        if item.cancelled || !stillRegistered {
            cancelledRequest = item.request
        } else {
            switch result {
            case .success(let image):
                _ = store(image, key: key)
                delivery = (image, nil, item.consumers)
            case .failure(let failure):
                delivery = (nil, failure, item.consumers)
            }
        }
        while runningCount < maxConcurrent, !pending.isEmpty {
            let next = pending.removeFirst()
            if next.cancelled || inFlight[next.request.key] !== next { continue }
            runningCount += 1
            next.started = true
            nextToStart = next
            break
        }
        lock.unlock()

        if let cancelledRequest { backend.cancel(request: cancelledRequest) }
        if let delivery {
            for consumer in delivery.consumers {
                if let image = delivery.image {
                    deliveredCount += 1
                    consumer.deliver(image)
                } else if let failure = delivery.failure {
                    consumer.fail(failure)
                }
            }
        }
        if let nextToStart { start(nextToStart) }
    }

    private func store(_ image: CGImage, key: WindowThumbnailKey) -> Bool {
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

    private static func isValid(size: CGSize) -> Bool {
        guard size.width.isFinite, size.height.isFinite else { return false }
        guard size.width > 0, size.height > 0 else { return false }
        guard size.width <= 4096, size.height <= 4096 else { return false }
        return true
    }
}
