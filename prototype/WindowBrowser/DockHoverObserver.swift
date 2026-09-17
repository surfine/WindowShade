// Dock 悬停目标检测。
//
// 只输出“已确认的应用实例、图标矩形、目标屏幕和观察器代数”，不截图、不折叠、
// 不操作窗口。Dock 的内部 AX 树结构不是稳定公开协议，因此这里的所有访问都是
// 有界、只读的：限定深度和节点数，找不到合适的列表/应用项就不产出目标。
//
// AX 通知不可用时退化为轻量鼠标检测：鼠标回调只做缓存几何判断，只在鼠标接近
// 已知 Dock 区域或可能出现 Dock 的屏幕边缘时才发起节流后的 AX 命中检测
// （初始上限每秒 10 次），离开即停止，不做全桌面定时扫描。

import Cocoa
import ApplicationServices

struct DockHoverTarget: Equatable {
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    /// AX / WindowServer 坐标（主屏左上原点、y 向下）。
    let iconFrameAX: CGRect
    let displayID: CGDirectDisplayID?
    let generation: UInt64
}

final class DockHoverObserver {
    typealias TargetHandler = (DockHoverTarget) -> Void
    typealias ClearHandler = (_ generation: UInt64) -> Void

    private enum Limits {
        static let maxDepth = 5
        static let maxNodes = 90
        static let hitTestInterval: TimeInterval = 0.1
        static let edgeActivationBand: CGFloat = 10
        static let knownAreaTolerance: CGFloat = 24
        static let iconHitTolerance: CGFloat = 8
    }

    private let onTarget: TargetHandler
    private let onClear: ClearHandler
    private let onUnavailable: ((String) -> Void)?
    private let workQueue = DispatchQueue(label: "WindowShade.dock-hover", qos: .userInitiated)

    private var observer: AXObserver?
    private var dockPID: pid_t = 0
    private var dockElement: AXUIElement?
    private var dockListElements: [AXUIElement] = []
    /// 每个 Dock 列表元素的实际矩形（逐块判断，不合成一个覆盖中间空白的大框）。
    private var dockAreas: [NSRect] = []
    /// 所有检测入口共用的排队器：最多一个在途 + 一个最新待处理。
    private var detection = WindowBrowserDetectionCoordinator()
    private var topologyVersion: UInt64 = 1
    private var screensToken: NSObjectProtocol?
    /// 诊断：检测请求次数、真实 AX 命中调用次数、被丢弃的过期结果。
    private(set) var detectionCount = 0
    private(set) var hitTestCount = 0
    private(set) var droppedStaleResultCount = 0
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var scheduleWorkItem: DispatchWorkItem?
    private var lastHitTestAt: CFAbsoluteTime = 0
    private var lastResolvedAt: CFAbsoluteTime = 0
    private var lastPointerCocoa: NSPoint?
    private var staleCheckWork: DispatchWorkItem?
    private var target: DockHoverTarget?
    private var generation: UInt64 = 1
    private var running = false
    private var notificationReliable = false
    private var retainedSelf: Unmanaged<DockHoverObserver>?

    init(onTarget: @escaping TargetHandler, onClear: @escaping ClearHandler,
         onUnavailable: ((String) -> Void)? = nil) {
        self.onTarget = onTarget
        self.onClear = onClear
        self.onUnavailable = onUnavailable
    }

    var currentTarget: DockHoverTarget? { target }
    var observerGeneration: UInt64 { generation }
    var usesNotifications: Bool { notificationReliable }
    /// 诊断：当前排队器里的请求数量（≤ 2：一个在途 + 一个最新待处理）。
    var pendingDetectionCount: Int { detection.pendingCount }

    // MARK: 生命周期

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !running else { return }
        running = true
        installWorkspaceObservers()
        installScreenObserver()
        rebuildObserver(reason: "start")
        installMouseFallback()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running || observer != nil || globalMouseMonitor != nil else { return }
        running = false
        scheduleWorkItem?.cancel()
        scheduleWorkItem = nil
        staleCheckWork?.cancel()
        staleCheckWork = nil
        removeObserver()
        removeMouseFallback()
        removeWorkspaceObservers()
        removeScreenObserver()
        target = nil
        dockListElements = []
        dockElement = nil
        dockPID = 0
        dockAreas = []
        detection.reset()
    }

    /// Dock 重启/实例变化/观察对象失效时：递增代数、撤销旧订阅、有界重建。
    func invalidate(reason: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running else { return }
        generation &+= 1
        // 旧观察器实例的在途检测与待处理位置一并失效，新实例的结果才生效。
        detection.reset()
        let previous = target
        target = nil
        if previous != nil { onClear(generation) }
        removeObserver()
        rebuildObserver(reason: reason)
    }

    // MARK: Dock 观察

    private func rebuildObserver(reason: String) {
        guard running else { return }
        removeObserver()
        guard let dockApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            wlog("dock-hover: dock not running reason=\(reason)")
            onUnavailable?("dock-not-running")
            return
        }
        let pid = dockApp.processIdentifier
        let generation = self.generation
        // Dock 树遍历是同步 AX 读取：放到 workQueue，主线程只接收结果并建立订阅。
        workQueue.async { [weak self] in
            guard let self else { return }
            let app = AXUIElementCreateApplication(pid)
            let lists = self.discoverDockLists(in: app)
            let listFramesAX = lists.compactMap { self.axFrame(of: $0) }
            DispatchQueue.main.async {
                guard self.running, self.generation == generation else { return }
                self.dockPID = pid
                self.dockElement = app
                self.dockListElements = lists
                self.dockAreas = listFramesAX.map { self.cocoaRect(fromAXFrame: $0) }
                self.notificationReliable = false
                self.createObserver(pid: pid, app: app, lists: lists, reason: reason)
            }
        }
    }

    private func createObserver(pid: pid_t, app: AXUIElement, lists: [AXUIElement],
                                reason: String) {
        dockPID = pid
        dockElement = app
        dockListElements = lists
        var newObserver: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<DockHoverObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handleAXNotification(element: element, notification: notification as String)
        }, &newObserver) == .success, let newObserver else {
            wlog("dock-hover: AXObserverCreate unavailable pid=\(pid) reason=\(reason)")
            onUnavailable?("observer-create-failed")
            return
        }
        observer = newObserver
        retainedSelf?.release()
        retainedSelf = Unmanaged.passRetained(self)
        if let refcon = retainedSelf?.toOpaque() {
            let source = AXObserverGetRunLoopSource(newObserver)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            for list in lists {
                AXObserverAddNotification(newObserver, list,
                                          kAXSelectedChildrenChangedNotification as CFString,
                                          refcon)
            }
            AXObserverAddNotification(newObserver, app,
                                      kAXUIElementDestroyedNotification as CFString, refcon)
        }
        wlog("dock-hover: observer rebuilt pid=\(pid) lists=\(lists.count) reason=\(reason)")
        // 通知式检测在没有实际悬停前无法证明可靠；先按选中项尝试一次，失败则
        // 依赖鼠标回退路径（notificationReliable 保持 false）。
        refreshFromSelection(reason: "rebuild")
    }

    private func removeObserver() {
        if let observer {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            if let dockElement {
                AXObserverRemoveNotification(observer, dockElement,
                    kAXUIElementDestroyedNotification as CFString)
            }
            for list in dockListElements {
                AXObserverRemoveNotification(observer, list,
                    kAXSelectedChildrenChangedNotification as CFString)
            }
            self.observer = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
    }

    private func handleAXNotification(element: AXUIElement, notification: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            if notification == kAXUIElementDestroyedNotification as String {
                self.invalidate(reason: "dock-element-destroyed")
            } else {
                self.scheduleSelectionRefresh(reason: "ax-notification")
            }
        }
    }

    private func scheduleSelectionRefresh(reason: String) {
        scheduleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scheduleWorkItem = nil
            self?.refreshFromSelection(reason: reason)
        }
        scheduleWorkItem = work
        // 悬停通知可能连续到达；100ms 合并窗口与目录刷新一致。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// 通知过期或不可用时的入口：与鼠标回退、失效复检共用同一个排队器。
    private func refreshFromSelection(reason: String) {
        guard running else { return }
        let point = lastPointerCocoa ?? NSEvent.mouseLocation
        requestDetection(at: point, source: reason, pointerDriven: false)
    }

    /// 所有检测入口的唯一入口：最多一个在途 + 一个最新待处理位置。
    private func requestDetection(at point: NSPoint, source: String,
                                  pointerDriven: Bool) {
        guard running, dockElement != nil else { return }
        guard let request = detection.begin(point: point, generation: generation,
                                            topologyVersion: topologyVersion,
                                            source: source,
                                            isPointerDriven: pointerDriven) else {
            // 已有在途检测：最新位置已经记入待处理位置，等这一轮结束后执行。
            return
        }
        runDetection(request)
    }

    /// 在后台队列执行一次有界 AX 命中 + 解析。主线程不做同步 IPC。
    private func runDetection(_ request: WindowBrowserDetectionRequest) {
        detectionCount += 1
        hitTestCount += 1
        let pid = dockPID
        let lists = dockListElements
        let axPoint = CGPoint(x: request.point.x,
                              y: coordinateBaselineY() - request.point.y)
        workQueue.async { [weak self] in
            guard let self else { return }
            var resolved = self.hitTestResolvedItem(pid: pid, axPoint: axPoint)
            if resolved == nil {
                resolved = self.selectedChildResolvedItem(lists: lists)
            }
            let usedNotificationPath = resolved != nil
            DispatchQueue.main.async {
                self.completeDetection(request, resolved: resolved,
                                       usedNotificationPath: usedNotificationPath)
            }
        }
    }

    private func completeDetection(_ request: WindowBrowserDetectionRequest,
                                   resolved: ResolvedDockItem?,
                                   usedNotificationPath: Bool) {
        let next = detection.finish(requestID: request.requestID)
        defer { if let next { runDetection(next) } }
        guard running else { return }
        // 结果核对：观察器代数、屏幕拓扑、指针请求 ID 都必须是当前的。
        guard detection.accepts(request, generation: generation,
                                topologyVersion: topologyVersion) else {
            droppedStaleResultCount += 1
            return
        }
        // 再用“现在”的鼠标位置验证命中，不能拿请求开始时的旧坐标证明仍然悬停。
        let currentMouse = NSEvent.mouseLocation
        let currentAX = CGPoint(x: currentMouse.x,
                                y: coordinateBaselineY() - currentMouse.y)
        if let resolved,
           let target = validatedTarget(resolved, reason: request.source,
                                        mouseAX: currentAX) {
            if usedNotificationPath { notificationReliable = true }
            emit(target)
            return
        }
        staleCheckOrClear(reason: resolved == nil ? "no-app-item" : "pointer-moved")
    }

    /// 用 AX 命中测试找到指针下的 Dock 图标（限定深度与节点数）。
    private func hitTestResolvedItem(pid: pid_t, axPoint: CGPoint) -> ResolvedDockItem? {
        let app = AXUIElementCreateApplication(pid)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(axPoint.x), Float(axPoint.y),
                                               &hit) == .success, let hitElement = hit else {
            return nil
        }
        var node: AXUIElement? = hitElement
        var depth = 0
        while let current = node, depth < Limits.maxDepth {
            if let candidate = resolve(item: current) { return candidate }
            node = parent(of: current)
            depth += 1
        }
        return nil
    }

    /// Dock 列表的选中子项（通知路径）：仍然要求指针在该图标区域内才产出目标。
    private func selectedChildResolvedItem(lists: [AXUIElement]) -> ResolvedDockItem? {
        for list in lists {
            guard let selected = selectedChildren(of: list),
                  let item = selected.first,
                  let candidate = resolve(item: item) else { continue }
            return candidate
        }
        return nil
    }

    private struct ResolvedDockItem {
        let pid: pid_t
        let bundleIdentifier: String
        let appName: String
        let frameAX: CGRect
    }

    private func selectedChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedChildrenAttribute as CFString,
                                            &value) == .success,
              let array = value as? [AXUIElement],
              !array.isEmpty else { return nil }
        return array
    }

    private func resolve(item: AXUIElement) -> ResolvedDockItem? {
        guard let url = urlFromAXAttribute(item, kAXURLAttribute as String)
            ?? urlFromAXAttribute(item, kAXDocumentAttribute as String) else { return nil }
        let path = url.path
        guard path.hasSuffix(".app") || path.contains(".app/") else { return nil }
        guard !path.contains("/.Trash/") else { return nil }
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              !bundleIdentifier.isEmpty else { return nil }
        let instances = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }
        guard !instances.isEmpty else { return nil }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let instance = instances.first(where: { $0.processIdentifier == frontmost })
            ?? instances.first(where: { $0.isActive })
            ?? instances.first
        guard let instance, let frame = axFrame(of: item) else { return nil }
        return ResolvedDockItem(pid: instance.processIdentifier,
                                bundleIdentifier: bundleIdentifier,
                                appName: instance.localizedName ?? bundleIdentifier,
                                frameAX: frame)
    }

    private func validatedTarget(_ item: ResolvedDockItem, reason: String,
                                 mouseAX: CGPoint) -> DockHoverTarget? {
        let expanded = item.frameAX.insetBy(dx: -Limits.iconHitTolerance,
                                            dy: -Limits.iconHitTolerance)
        guard expanded.contains(mouseAX) else { return nil }
        let cocoa = cocoaRect(fromAXFrame: item.frameAX)
        let display = displayID(for: screenForCocoaFrame(cocoa))
        return DockHoverTarget(pid: item.pid,
                               bundleIdentifier: item.bundleIdentifier,
                               appName: item.appName,
                               iconFrameAX: item.frameAX,
                               displayID: display,
                               generation: generation)
    }

    private func emit(_ newTarget: DockHoverTarget) {
        if let target, target == newTarget { return }
        staleCheckWork?.cancel()
        staleCheckWork = nil
        target = newTarget
        lastResolvedAt = CFAbsoluteTimeGetCurrent()
        wlog("dock-hover: target pid=\(newTarget.pid) bundle=\(newTarget.bundleIdentifier) generation=\(newTarget.generation)")
        onTarget(newTarget)
    }

    private func clear(reason: String) {
        staleCheckWork?.cancel()
        staleCheckWork = nil
        guard target != nil else { return }
        target = nil
        wlog("dock-hover: target cleared reason=\(reason)")
        onClear(generation)
    }

    // MARK: 鼠标回退检测

    private func installMouseFallback() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.mouseMoved()
        }
        // 面板内的事件本地 monitor 由控制器负责；这里只处理全局移动。
    }

    private func removeMouseFallback() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func mouseMoved() {
        handlePointerMove(at: NSEvent.mouseLocation)
    }

    /// 测试/探针接缝：用给定 Cocoa 指针位置驱动真正的回退命中路径，
    /// 不移动系统指针。生产路径始终传入 `NSEvent.mouseLocation`。
    func simulatePointer(at cocoaPoint: NSPoint) {
        dispatchPrecondition(condition: .onQueue(.main))
        handlePointerMove(at: cocoaPoint)
    }

    private func handlePointerMove(at mouse: NSPoint) {
        guard running else { return }
        lastPointerCocoa = mouse
        // 只在候选区域（Dock 条带或该屏的真实边缘带）做命中检测。
        // 不在这里清除目标：鼠标位于图标与面板之间的过渡区域时，面板是否隐藏
        // 由控制器结合面板矩形判断，观察器不能把中间区域误判成离开。
        guard mouseIsNearDock(mouse) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastHitTestAt >= Limits.hitTestInterval else { return }
        lastHitTestAt = now
        requestDetection(at: mouse, source: "mouse-fallback", pointerDriven: true)
    }

    /// 指针停在 Dock 上但不在任何应用图标上时，不能因为“不再移动”就保留旧目标。
    /// 超过宽限期立即清除；否则安排一次延迟复检（使用最后一次指针位置）。
    private func staleCheckOrClear(reason: String) {
        guard target != nil else {
            staleCheckWork?.cancel()
            staleCheckWork = nil
            return
        }
        if CFAbsoluteTimeGetCurrent() - lastResolvedAt > 0.4 {
            clear(reason: reason)
            return
        }
        scheduleStaleCheck(after: 0.45)
    }

    private func scheduleStaleCheck(after delay: TimeInterval) {
        staleCheckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running, self.target != nil else { return }
            let point = self.lastPointerCocoa ?? NSEvent.mouseLocation
            guard self.mouseIsNearDock(point) else { return }
            self.lastHitTestAt = 0        // 延迟复检不受正常节流限制
            self.requestDetection(at: point, source: "stale-check", pointerDriven: true)
        }
        staleCheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func mouseIsNearDock(_ mouse: NSPoint) -> Bool {
        // 先找真正包含指针的屏幕，再判断该屏自己的边缘带与已知 Dock 区域。
        // 逐屏的单轴比较会把别的屏幕的边缘条件当成整块桌面都命中，这里不再那样做。
        let screens = NSScreen.screens.map {
            WindowBrowserDockRegion.ScreenSnapshot(frame: $0.frame,
                                                   displayID: displayID(for: $0))
        }
        return WindowBrowserDockRegion.isNearDock(
            mouse, screens: screens, dockAreas: dockAreas,
            edgeBand: Limits.edgeActivationBand,
            tolerance: Limits.knownAreaTolerance)
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString,
                                            &value) == .success,
              let parent = value, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
            return nil
        }
        return (parent as! AXUIElement)
    }

    // MARK: Dock 树遍历

    private func discoverDockLists(in root: AXUIElement) -> [AXUIElement] {
        var lists: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < Limits.maxNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = axRole(element)
            let children = axChildren(element)
            if role == "AXList", children.contains(where: { isDockAppItem($0) }) {
                lists.append(element)
                continue
            }
            if depth >= Limits.maxDepth { continue }
            for child in children where children.count <= 64 {
                queue.append((child, depth + 1))
            }
        }
        return lists
    }

    private func isDockAppItem(_ element: AXUIElement) -> Bool {
        guard let url = urlFromAXAttribute(element, kAXURLAttribute as String) else { return false }
        return url.path.hasSuffix(".app")
    }

    /// AX 矩形（左上原点）转 Cocoa 全局坐标；逐块保留，不合成大框。
    private func cocoaRect(fromAXFrame frame: CGRect) -> NSRect {
        cocoaFrame(fromAXPosition: frame.origin, size: frame.size)
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        guard let position = axPosition(element), let size = axSize(element),
              size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: position, size: size)
    }

    // MARK: NSWorkspace 生命周期

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                if app.processIdentifier == self.dockPID {
                    self.invalidate(reason: "dock-terminated")
                }
            })
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                if app.bundleIdentifier == "com.apple.dock", self.running {
                    self.invalidate(reason: "dock-launched")
                }
            })
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach { center.removeObserver($0) }
        workspaceTokens.removeAll()
    }

    /// 显示器拓扑变化：递增拓扑版本，旧坐标与旧结果全部失效，
    /// 由控制器在明确交互时重新计算面板归属。
    private func installScreenObserver() {
        guard screensToken == nil else { return }
        screensToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, self.running else { return }
                self.topologyVersion &+= 1
                self.detection.reset()
                self.rebuildObserver(reason: "screens-changed")
            }
    }

    private func removeScreenObserver() {
        if let screensToken {
            NotificationCenter.default.removeObserver(screensToken)
            self.screensToken = nil
        }
    }
}
