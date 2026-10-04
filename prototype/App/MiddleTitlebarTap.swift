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

    var systemStopped: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return withLock { driver.phase == .stoppedBySystem }
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
        if let created { CGEvent.tapEnable(tap: created, enable: false) }
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
            case .clickTitlebar, .commit(.titlebarUp), .commit(.titlebarDown): return true
            default: return false
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
                app.foldWindowAtScreenPoint(location)
            case .commit(.titlebarDown):
                app.expandWindowAtScreenPoint(location)
            default:
                break
            }
        }
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

    /// 中键下拉：展开该点下已收起的窗口。
    func expandWindowAtScreenPoint(_ point: CGPoint) {
        guard ensureAccessibility() else { return }
        guard let win = frontmostWindowContaining(point: point, requireCompatProfile: false),
              let id = windowID(of: win) else { return }
        if shaded[id] != nil { _ = unshade(id) }
    }
}
