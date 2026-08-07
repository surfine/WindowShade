// 折叠截图的短 TTL 缓存：同一窗口在 500ms 内反复折叠/展开时复用上次截图，
// 避免重复 ScreenCaptureKit capture。
//
// 只服务折叠路径（captureWindowWithTimeout），不缓存悬停预览的懒截图，
// 避免把隐藏窗口的错误快照复用进卷帘条。

import Cocoa

final class WindowSnapshotCache {
    static let shared = WindowSnapshotCache()

    private struct Entry {
        let image: CGImage
        let capturedAt: CFAbsoluteTime
    }

    private let lock = NSLock()
    private let ttl: TimeInterval = 0.5
    private var entries: [CGWindowID: Entry] = [:]

    func cachedImage(id: CGWindowID) -> CGImage? {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[id], now - entry.capturedAt < ttl else {
            if entries[id] != nil { entries.removeValue(forKey: id) }
            return nil
        }
        return entry.image
    }

    func store(image: CGImage, id: CGWindowID) {
        lock.lock()
        entries[id] = Entry(image: image, capturedAt: CFAbsoluteTimeGetCurrent())
        if entries.count > 64 {
            let now = CFAbsoluteTimeGetCurrent()
            entries = entries.filter { now - $0.value.capturedAt < ttl }
        }
        lock.unlock()
    }
}
