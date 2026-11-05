// 置顶预览的会话层：镜像租约、外部快照、单个置顶会话的状态（面板、捕获流、交接与挂起态）。
// 控制器（PinnedPreview.swift）持有多份；这里只放状态与失效清理，不动窗口。

import Cocoa
import ScreenCaptureKit

final class PinnedMirrorLease {
    private let lock = NSLock()
    private var releaseAction: (() -> Void)?

    init(release: @escaping () -> Void) {
        releaseAction = release
    }

    func release() {
        lock.lock()
        let action = releaseAction
        releaseAction = nil
        lock.unlock()
        action?()
    }

    deinit {
        // deinit 只作为兜底；主要释放在面板关闭与目标切换时执行。
        release()
    }
}

struct PinnedPreviewSessionSnapshot {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let title: String
    let lastKnownFrame: NSRect
    let isSuspended: Bool
}

@MainActor
final class PinnedPreviewSession {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let title: String
    let axWindow: AXUIElement
    let panel: PinnedPreviewPanel
    let contentView: PinnedPreviewContentView
    let capture: WindowStreamCapture

    var scWindow: SCWindow
    var display: SCDisplay?
    var lastKnownFrame: NSRect
    var isInteracting = false
    var isDucked = false
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var pendingExit: DispatchWorkItem?
    // 交互代数：每次进入交接自增；跨线程管线的每一跳都校验，过期即中止。
    var interactionEpoch: UInt64 = 0
    // 稳定门：上一次采到的源窗口 frame；隔 150ms 再采一次仍一致才应用到面板。
    var pendingFrame: NSRect?
    // 稳定门的计时：每来一次挪动/改大小就重新计 150ms，到点再采样比对。
    var settleTimer: Timer?
    // 共享窗口状态来源（WindowStateHub）上的订阅；挂起时退订，恢复时重新订阅。
    var watch: WindowWatch?
    // Mission Control/genie/全屏过渡期间 WindowServer 呈现坐标会"稳定但错误"
    // （比如 MC 缩略图排布），两拍稳定门本身挡不住。AX 确认后被判定为动画产物的
    // 候选帧记在这里，避免同一个错误候选帧每来一次事件都重新发一次 AX 查询。
    var rejectedFrame: NSRect?
    var isConfirmingFrame = false
    // 交接管线完成前到达的点击：暂存，待面板真正透明+穿透后补发到真实窗口。
    var pendingClick: (point: CGPoint, count: Int)?
    // co-Space 不变量判定的短 TTL 缓存：源窗口事件可能一秒来很多次，不必每次都查 WindowServer。
    // 换桌面事件（1325/1326）到达时清零，立刻核对。
    var spaceCheckAt: CFAbsoluteTime = 0
    // 面板当前应处的 Space（源窗口所在 Space）。nil 表示 SLS 符号不可用/尚未解析，
    // 此时面板留在创建时的 Space，不追随源窗口跨 Space 移动。
    var sourceSpaceID: UInt64?
    // 挂起态（暂时取消全部置顶）：面板已 orderOut、capture 已停，会话保留，
    // 再按一次按原来的前后顺序放回。
    var isSuspended = false
    // 锁屏/熄屏/会话切走时的自动暂停：只停流，面板与菜单状态不变（和 isSuspended 无关）。
    var isEnvPaused = false

    init(windowID: CGWindowID, pid: pid_t, bundleIdentifier: String, appName: String,
         title: String, axWindow: AXUIElement, scWindow: SCWindow, display: SCDisplay?,
         panel: PinnedPreviewPanel, contentView: PinnedPreviewContentView,
         capture: WindowStreamCapture, lastKnownFrame: NSRect) {
        self.windowID = windowID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.axWindow = axWindow
        self.scWindow = scWindow
        self.display = display
        self.panel = panel
        self.contentView = contentView
        self.capture = capture
        self.lastKnownFrame = lastKnownFrame
    }

    /// 不再盯源窗口（挂起或结束）：退订、停掉稳定门计时。
    func stopWatching() {
        watch?.cancel()
        watch = nil
        settleTimer?.invalidate()
        settleTimer = nil
        pendingFrame = nil
    }

    func invalidate() {
        stopWatching()
        pendingExit?.cancel()
        pendingExit = nil
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}
