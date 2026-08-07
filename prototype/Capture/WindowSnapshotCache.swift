// 折叠截图的短 TTL 缓存：同一窗口在 500ms 内反复折叠/展开时复用上次截图，
// 避免重复 ScreenCaptureKit capture。
//
// 缓存 key = 窗口 ID + capture variant + 请求像素档位：
// 预览路径（maxPixelSize 720×480）与原貌卷帘（完整 Retina）分辨率差很多，
// 不能互相复用——否则小图会在 TTL 内被完整截图请求错误复用，或完整 Retina
// 大图被小预览路径复用、白占内存。
//
// 内存上限按 bytesPerRow × height 估算总成本，避免快速折叠多个大窗口时
// 产生瞬时内存尖峰。TTL 保持 500ms 短寿命。
//
// 只服务折叠路径（captureWindowWithTimeout），不缓存悬停预览的懒截图，
// 避免把隐藏窗口的错误快照复用进卷帘条。

import Cocoa
import CoreGraphics

enum WindowSnapshotVariant: String, Hashable {
    case preview        // 预览/悬停路径：请求带 maxPixelSize 上限
    case nativeChrome   // 原貌卷帘：完整 Retina 截图
}

struct WindowSnapshotKey: Hashable {
    let windowID: CGWindowID
    let variant: WindowSnapshotVariant
    let pixelSizeClass: Int

    init(windowID: CGWindowID, variant: WindowSnapshotVariant, maxPixelSize: CGSize?) {
        self.windowID = windowID
        self.variant = variant
        if variant == .preview, let maxPixelSize {
            let w = max(1, Int(maxPixelSize.width))
            let h = max(1, Int(maxPixelSize.height))
            // 档位化：请求像素上限 ±8pt 内视为同一档，保持复用率。
            self.pixelSizeClass = ((w / 8) << 12) | (h / 8)
        } else {
            self.pixelSizeClass = 0
        }
    }
}

// 在途 capture 注册槽：任务完成时按身份清理，避免并发 join 方互相误删
// 后到的同 key 新任务。
final class WindowSnapshotInFlightSlot {
    let key: WindowSnapshotKey
    var task: Task<CGImage?, Never>?
    private let completionLock = NSLock()
    private var completed = false

    init(key: WindowSnapshotKey) {
        self.key = key
    }

    func markCompleted() {
        completionLock.lock()
        completed = true
        completionLock.unlock()
    }

    var isCompleted: Bool {
        completionLock.lock()
        defer { completionLock.unlock() }
        return completed
    }
}

final class WindowSnapshotCache {
    static let shared = WindowSnapshotCache()

    private struct Entry {
        let image: CGImage
        let capturedAt: CFAbsoluteTime
        let cost: Int
    }

    private let lock = NSLock()
    private let ttl: TimeInterval = 0.5
    // 总内存上限：完整 Retina 窗口图每张可达 10~30MB，96MB 预算能覆盖
    // 快速连续折叠几个大窗口，同时封住瞬时尖峰。
    private let maxTotalCost: Int = 96 * 1024 * 1024
    private var entries: [WindowSnapshotKey: Entry] = [:]
    private var totalCost: Int = 0

    // 在途 capture 注册表：同一 key 只允许一个进行中的截图任务。
    private let inFlightLock = NSLock()
    private var inFlight: [WindowSnapshotKey: WindowSnapshotInFlightSlot] = [:]

    private func cost(of image: CGImage) -> Int {
        let rowBytes = Int(image.bytesPerRow)
        let height = image.height
        guard rowBytes > 0, height > 0 else { return 0 }
        let raw = rowBytes * height
        // bytesPerRow × height 是最接近真实分配的估算；加 10% 覆盖 padding。
        return min(Int.max / 2, raw + raw / 10)
    }

    func cachedImage(key: WindowSnapshotKey) -> CGImage? {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], now - entry.capturedAt < ttl else {
            if let old = entries.removeValue(forKey: key) {
                totalCost -= old.cost
            }
            return nil
        }
        return entry.image
    }

    func store(image: CGImage, key: WindowSnapshotKey) {
        let cost = cost(of: image)
        lock.lock()
        if let old = entries[key] {
            totalCost -= old.cost
        }
        entries[key] = Entry(image: image, capturedAt: CFAbsoluteTimeGetCurrent(), cost: cost)
        totalCost += cost
        evictIfNeeded(now: CFAbsoluteTimeGetCurrent())
        lock.unlock()
    }

    private func evictIfNeeded(now: CFAbsoluteTime) {
        var expiredCost = 0
        entries = entries.filter { entry in
            let fresh = now - entry.value.capturedAt < ttl
            if !fresh { expiredCost += entry.value.cost }
            return fresh
        }
        totalCost -= expiredCost
        // 仍超预算：从最旧开始淘汰，直到回到预算内。
        while totalCost > maxTotalCost,
              let oldest = entries.min(by: { $0.value.capturedAt < $1.value.capturedAt }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }

    // 返回 nil 表示该 key 没有在途 capture，调用方可以注册新任务。
    func inFlightTask(for key: WindowSnapshotKey) -> Task<CGImage?, Never>? {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        return inFlight[key]?.task
    }

    // 发布在途任务；若期间已有同 key 任务被发布，保持已有任务并返回 false。
    // 发布成功与否都必须在任务完成时调用 completeInFlight(slot:) 清理。
    @discardableResult
    func registerInFlight(slot: WindowSnapshotInFlightSlot) -> Bool {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        guard inFlight[slot.key] == nil else { return false }
        inFlight[slot.key] = slot
        return true
    }

    // 任务完成（isCompleted）后按槽身份清理，避免误删后到的同 key 新任务；
    // 若任务在注册前就已完成，等待方在 await 结束后也会补一次清理。
    func completeInFlight(_ slot: WindowSnapshotInFlightSlot) {
        inFlightLock.lock()
        if inFlight[slot.key] === slot, slot.isCompleted {
            inFlight.removeValue(forKey: slot.key)
        }
        inFlightLock.unlock()
    }
}
