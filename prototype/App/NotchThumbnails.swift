// 刘海那一排格子上的画面（docs/direction.md「回到窗口」第 2 步）：最小化、隐藏、别的桌面、侧拉的窗口，
// 原来格子上只有放大的 App 图标；现在指针停到刘海、一排展开时，在后台给它们各截一张小图，截到一张换上一张。
//
// 规矩（Core/NotchThumbnailPolicy）：只在展开时按需截，不建任何定时器；同时最多 2 张在途；10 秒内截过的不重截；
// 先用 WindowSnapshot（最小化、隐藏的也拿得到），拿不到再用 FastCapture；缩到最长边 320 再交出去。
// 截不到就保留上一张，再没有就还是 App 图标。没有屏幕录制权限时一张都不截。

import Cocoa

@MainActor
final class NotchThumbnails {
    /// 截一张格子用的小图（后台线程调用）。探针、测试可以换掉。
    var capture: @Sendable (CGWindowID) -> CGImage? = { id in
        let picture = WindowSnapshot.image(id, quality: .thumbnail) ?? FastCapture.window(id)
        return picture.flatMap { WindowSnapshot.downscaled($0, maxPixel: NotchThumbnailPolicy.tileMaxPixel) }
    }
    /// 截一张看一眼用的大图（后台线程调用）。
    var captureStill: @Sendable (CGWindowID, NotchThumbnailPolicy.StillQuality) -> CGImage? = { id, quality in
        WindowSnapshot.image(id, quality: quality == .full ? .full : .thumbnail) ?? FastCapture.window(id)
    }
    var now: () -> CFAbsoluteTime = { CFAbsoluteTimeGetCurrent() }
    var permitted: () -> Bool = { hasScreenRecordingPermission() }
    /// 一张格子图到了（主线程）。
    var onImage: ((CGWindowID, CGImage) -> Void)?

    private var cache: [CGWindowID: (image: CGImage, at: CFAbsoluteTime)] = [:]
    private var inFlight = Set<CGWindowID>()
    /// 作废一次加一：还在路上的结果回来时代数不对就丢掉。
    private var generation = 0
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "WindowShade.notch-thumbnails"
        queue.maxConcurrentOperationCount = NotchThumbnailPolicy.maxInFlight
        queue.qualityOfService = .utility
        return queue
    }()

    func image(_ id: CGWindowID) -> CGImage? { cache[id]?.image }

    /// 给这几格要画面：缺图的、或者图已经超过 10 秒的才截。
    func request(_ ids: [CGWindowID]) {
        guard permitted() else { return }
        let moment = now()
        for id in ids where !inFlight.contains(id) {
            if let cached = cache[id], NotchThumbnailPolicy.isFresh(capturedAt: cached.at, now: moment) { continue }
            inFlight.insert(id)
            let started = generation
            let capture = self.capture
            queue.addOperation { [weak self] in
                let picture = capture(id)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finish(id, picture, started) }
                }
            }
        }
    }

    private func finish(_ id: CGWindowID, _ picture: CGImage?, _ started: Int) {
        guard started == generation else { return }
        inFlight.remove(id)
        // 截不到（窗口没了、受保护、动画中间）：保留上一张。
        guard let picture else { return }
        cache[id] = (picture, now())
        onImage?(id, picture)
    }

    /// 看一眼要的那一张大图：排在格子图前面，和它们共用“同时最多 2 张”。结果在主线程交回（拿不到是 nil）。
    func still(_ id: CGWindowID, quality: NotchThumbnailPolicy.StillQuality, completion: @escaping @MainActor (CGImage?) -> Void) {
        guard permitted() else {
            completion(nil)
            return
        }
        let captureStill = self.captureStill
        let operation = BlockOperation {
            let picture = captureStill(id, quality)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(picture) } }
        }
        operation.queuePriority = .veryHigh
        queue.addOperation(operation)
    }

    /// 只留这一排里还在的格子的图。
    func prune(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    /// 全部作废（换了桌面、关掉刘海）：在路上的结果回来也丢掉。
    func invalidate() {
        generation += 1
        inFlight.removeAll()
        cache.removeAll()
    }
}
