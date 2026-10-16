import Cocoa

/// I4：中键标题栏手势钩子。默认不装；开关打开才创建端口。
/// 回调只做 O(1) 分类与投递；收起／展开在主线程执行。
final class MiddleTitlebarTap: @unchecked Sendable {
    // 钩子线程写状态，主线程拆端口；NSLock 保护。
    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var threadRunLoop: CFRunLoop?
    private var thread: Thread?
    private var driver = HookDriver()
    private var drag = MiddleDrag()
    private var clock = WS2.Instant(nanoseconds: 1)
    private var tracking = false
    /// 上一次送去画浮窗的预览（动作 + 进度档），同一档不重复送。
    private var lastPreview: (action: WS2.Action, step: Int)?

    var systemStopped: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return withLock { driver.phase == .stoppedBySystem }
    }

    /// 辅助功能晚到：因端口没创建出来而停住的解开，调用方随后再 apply 一次。返回有没有解开。
    func accessibilityGranted() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return withLock { driver.accessibilityGranted() }
    }

    func apply(installing: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        let action = withLock { driver.plan(wanted: installing, isOpen: port != nil) }
        switch action {
        case .open:
            if !createPort() { withLock { driver.openFailed() } }
        case .close:
            destroyPort()
            withLock { drag = MiddleDrag(); tracking = false }
        case .keep:
            break
        }
    }

    private func createPort() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MiddleTitlebarTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type, event)
            },
            userInfo: refcon) else { return false }
        let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        port = created
        source = loopSource
        EventTapHealth.shared.register(created, label: "middle-titlebar")
        let worker = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            let source = self.withLock { () -> CFRunLoopSource? in
                self.threadRunLoop = runLoop
                return self.source
            }
            guard let source else { return }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        worker.name = "WindowShade.MiddleTitlebarTap"
        worker.qualityOfService = .userInteractive
        worker.stackSize = 512 * 1024
        thread = worker
        worker.start()
        return true
    }

    private func destroyPort() {
        dispatchPrecondition(condition: .onQueue(.main))
        let created = withLock { () -> CFMachPort? in
            let current = port
            port = nil
            source = nil
            return current
        }
        if let created {
            EventTapHealth.shared.unregister(created)
            CGEvent.tapEnable(tap: created, enable: false)
        }
        if let loop = withLock({ threadRunLoop }) {
            CFRunLoopStop(loop)
        }
        withLock { threadRunLoop = nil; thread = nil }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let action = withLock {
                drag = MiddleDrag()
                tracking = false
                return driver.systemDisabled(isOpen: port != nil)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if action == .close { self.destroyPort() }
            }
            return Unmanaged.passUnretained(event)
        }
        // Quartz 中键是 2。
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else {
            return Unmanaged.passUnretained(event)
        }
        let location = event.location
        let point = WS2.Point(x: location.x, y: location.y)
        let now = withLock { () -> WS2.Instant in
            clock = clock.adding(1)
            return clock
        }
        let effects: [MiddleDrag.Effect]
        switch type {
        case .otherMouseDown:
            let region = Self.region(at: location)
            effects = withLock {
                tracking = true
                return drag.handle(.down(point, region), at: now)
            }
        case .otherMouseDragged:
            effects = withLock {
                guard tracking else { return [] }
                return drag.handle(.move(point), at: now)
            }
        case .otherMouseUp:
            effects = withLock {
                guard tracking else { return [] }
                tracking = false
                return drag.handle(.up(point), at: now)
            }
        default:
            return Unmanaged.passUnretained(event)
        }
        let consume = effects.contains { effect in
            switch effect {
            case .clickTitlebar, .commit(.titlebarUp), .commit(.titlebarDown),
                 .commit(.titlebarLeft), .commit(.titlebarRight): return true
            default: return false
            }
        }
        // 预览只画浮窗，不吞事件；同一档进度不重复送主线程。
        var hudEffects: [MiddleDrag.Effect] = []
        for effect in effects {
            switch effect {
            case .preview(let action, let progress):
                guard Self.hudAction(for: action) != nil else { continue }
                let step = Int((progress * 20).rounded(.down))
                let changed = withLock { () -> Bool in
                    if let last = lastPreview, last.action == action, last.step == step { return false }
                    lastPreview = (action, step)
                    return true
                }
                if changed { hudEffects.append(effect) }
            case .cancelled, .commit, .clickTitlebar:
                withLock { lastPreview = nil }
                if case .cancelled = effect { hudEffects.append(effect) }
            default:
                break
            }
        }
        if !hudEffects.isEmpty && !consume {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.perform(hudEffects, at: location) }
            }
        }
        if consume {
            _ = withLock { driver.onEvent() }
            DispatchQueue.main.async {
                // 明确从主队列进来；AppDelegate 的收起路径要求主线程。
                MainActor.assumeIsolated { Self.perform(effects, at: location) }
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private static func region(at location: CGPoint) -> MiddleDrag.Region {
        // 钩子线程不做 AX。标题栏带用窗口列表几何粗判；拿不准就 unknown，原样放行。
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return .unknown
        }
        for entry in info {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat else { continue }
            let frame = CGRect(x: x, y: y, width: w, height: h)
            guard frame.contains(location) else { continue }
            let bar = min(max(22, h * 0.12), 52)
            if location.y >= frame.minY && location.y <= frame.minY + bar { return .titlebar }
            return .other
        }
        return .unknown
    }

    @MainActor
    private static func perform(_ effects: [MiddleDrag.Effect], at location: CGPoint) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        for effect in effects {
            switch effect {
            case .clickTitlebar, .commit(.titlebarUp):
                // 拖动预览可能已画出浮窗；收起路径不经过排布，在这里收掉。
                app.gestures.hud.cancel()
                app.foldWindowAtScreenPoint(location)
            case .commit(let action) where Self.hudAction(for: action) != nil:
                guard let placement = hudAction(for: action) else { break }
                // 每次预览都以提交或取消收尾；排布成功时 keyPlace 会重新画。
                app.gestures.hud.cancel()
                app.placeWindowAtScreenPoint(location, placement)
            case .preview(let action, let progress):
                guard let shown = hudAction(for: action) else { break }
                app.gestures.hud.update(GestureFrame(action: shown, progress: CGFloat(progress)),
                                        anchor: hudAnchor(at: location), screen: nil)
            case .cancelled:
                app.gestures.hud.cancel()
            default:
                break
            }
        }
    }

    /// 标题栏中键拖的方向对应触控板标题栏手势里的同一个动作：下拉铺满，左右半屏，上推收起。
    nonisolated static func hudAction(for action: WS2.Action) -> GestureAction? {
        switch action {
        case .titlebarDown: return .fill
        case .titlebarLeft: return .leftHalf
        case .titlebarRight: return .rightHalf
        case .titlebarUp: return .shade
        default: return nil
        }
    }

    private static func hudAnchor(at location: CGPoint) -> CGPoint {
        let p = cocoaMousePoint(fromAXPoint: CGPoint(x: location.x, y: location.y + 14))
        return CGPoint(x: p.x, y: p.y - 10)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

extension AppDelegate {
    /// 中键点在标题栏：有收起就展开，否则收起该点下的窗口。
    func foldWindowAtScreenPoint(_ point: CGPoint) {
        guard ensureAccessibility() else { return }
        guard let win = frontmostWindowContaining(point: point, requireCompatProfile: false),
              let id = windowID(of: win) else { return }
        if shaded[id] != nil {
            _ = unshade(id)
        } else {
            shade(win, id)
        }
    }

    /// 中键拖在标题栏：把该点下的窗口铺满或排成左、右半屏，走触控板手势同一条排布路径（含浮窗与撤销）。
    func placeWindowAtScreenPoint(_ point: CGPoint, _ action: GestureAction) {
        guard ensureAccessibility() else { gestures.hud.cancel(); return }
        guard let win = frontmostWindowContaining(point: point, requireCompatProfile: false),
              let id = windowID(of: win) else { gestures.hud.cancel(); return }
        // 已收起的窗口：下拉照旧是展开（触控板也是这样），半屏不排卷帘条。
        if shaded[id] != nil {
            if action == .fill { _ = unshade(id) }
            gestures.hud.cancel()
            return
        }
        if let focused = focusedWindow(), windowID(of: focused) == id {
            gestures.keyPlace(action)
            return
        }
        // 点的不是当前焦点窗口：先把它带到前台，再排。
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150), tolerance: .milliseconds(30))
            guard let self else { return }
            guard let focused = focusedWindow(), windowID(of: focused) == id else {
                self.gestures.hud.cancel()
                return
            }
            self.gestures.keyPlace(action)
        }
    }

    /// 中键下拉：展开该点下已收起的窗口。
    func expandWindowAtScreenPoint(_ point: CGPoint) {
        guard ensureAccessibility() else { return }
        guard let win = frontmostWindowContaining(point: point, requireCompatProfile: false),
              let id = windowID(of: win) else { return }
        if shaded[id] != nil { _ = unshade(id) }
    }
}
