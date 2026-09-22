// SCShareableContent 短 TTL 缓存。

import Cocoa
import ScreenCaptureKit

// SCShareableContent.current 每次调用都要枚举全系统窗口，在部分机器上耗时数百
// 毫秒到数秒——它是每次折叠截图的同步前置成本，也是"双击后要等一下"的感知延迟
// 大头（超时还会把原貌卷帘降级成代理条）。短 TTL 缓存 + 标题栏点击预热之后，
// 双击的第二下落地时内容通常已就绪。缓存未命中目标窗口时强制刷新，
// 正确性不受 TTL 影响（新建窗口永远走强制刷新）。
@available(macOS 14.0, *)
@MainActor
final class ShareableContentCache {
    static let shared = ShareableContentCache()

    private var cached: SCShareableContent?
    private var fetchedAt: CFAbsoluteTime = 0
    private var inFlight: Task<SCShareableContent, Error>?
    private let ttl: TimeInterval = 1.5
    private var lastFailureAt: CFAbsoluteTime = 0
    private var lastFailureLogAt: CFAbsoluteTime = 0
    private let failureBackoff: TimeInterval = 2.0
    private let failureLogThrottle: TimeInterval = 30.0

    private func isFresh() -> Bool {
        cached != nil && CFAbsoluteTimeGetCurrent() - fetchedAt < ttl
    }

    func content(requiring windowID: CGWindowID) async -> SCShareableContent? {
        if isFresh(), let cached, cached.windows.contains(where: { $0.windowID == windowID }) {
            return cached
        }
        if let inFlight, let content = try? await inFlight.value,
           content.windows.contains(where: { $0.windowID == windowID }) {
            return content
        }
        // 等到的在途快照仍不含目标窗口（典型场景：窗口在枚举开始之后才创建）。
        // 旧任务此刻已经跑完，再 await 它只会拿到同一份过期快照；必须发起新枚举。
        // refresh() 会覆盖 inFlight 槽位，配合代数守卫避免旧任务收尾时误清掉
        // 新任务的单飞标记（见 refresh() 的 refreshGeneration）。
        return await refresh()
    }

    // 标题栏 mousedown 预热。命中新鲜缓存或已有在途请求都直接跳过；无录屏权限或
    // 处于失败退避期内也跳过，避免每次点击都触发一次注定失败的全系统枚举。
    func prefetch() async {
        guard hasScreenRecordingPermission() else { return }
        guard !isFresh(), inFlight == nil else { return }
        guard CFAbsoluteTimeGetCurrent() - lastFailureAt >= failureBackoff else { return }
        _ = await refresh()
    }

    // "决定要发起 fetch"到"inFlight 被设置"之间必须没有 await：调用方（content(requiring:)
    // 和 prefetch()）决定发起刷新时，现有 inFlight 要么为空、要么已经完成（content
    // (requiring:) 只会在 await 完旧任务之后才走进这里），进入本函数到 `inFlight = task`
    // 这行之前也没有任何 await，因此不会触发重复的全系统枚举。
    // refreshGeneration 是代数守卫：content(requiring:) 发现旧快照不含目标窗口时会
    // 立刻发起新一轮 refresh() 并覆盖 inFlight；旧一轮的 await 恢复点可能晚于这个
    // 覆盖才执行，只有「仍是当前代数」的那一轮才有权清空 inFlight 并写缓存。
    private var refreshGeneration: UInt64 = 0

    private func refresh() async -> SCShareableContent? {
        let start = CFAbsoluteTimeGetCurrent()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        // 不继承 MainActor：窗口枚举可能持续数秒，cache 状态仍在主 actor 串行化，
        // 但系统枚举及其完成回调不会占用主线程执行器。
        let task = Task.detached(priority: .userInitiated) {
            try await SCShareableContent.current
        }
        inFlight = task
        let content = try? await task.value
        guard refreshGeneration == generation else {
            // 已被更新的刷新取代：缓存状态由新代数负责，这里只把结果交还调用方。
            return content
        }
        inFlight = nil
        if let content {
            cached = content
            fetchedAt = CFAbsoluteTimeGetCurrent()
            lastFailureAt = 0
            let ms = Int((fetchedAt - start) * 1000)
            if ms >= 300 { wlog("capture: shareable-content fetch took \(ms)ms") }
        } else {
            lastFailureAt = CFAbsoluteTimeGetCurrent()
            if lastFailureAt - lastFailureLogAt >= failureLogThrottle {
                lastFailureLogAt = lastFailureAt
                wlog("capture: shareable-content fetch failed")
            }
        }
        return content
    }
}

// continuation 竞速的"只 resume 一次"守卫。两个赛跑的 Task 不在同一 actor 上，
// 需要真正的互斥而非"没有 await 就不会交错"这类单线程论证。
actor SingleResumeGuard {
    private var resumed = false
    func tryResume() -> Bool {
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
