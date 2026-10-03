import Cocoa
import CoreVideo

/// 滚动钩子。策略不允许时不创建端口；被系统停掉后拆掉，不重新打开。
final class ScrollTap: @unchecked Sendable {
    // 回调在钩子自己的线程，拆端口在主线程。NSLock 保护端口、状态机和插值器。
    private let lock = NSLock()
    private var driver = HookDriver()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?
    private var session = ScrollSession()
    private var request = ScrollSession.Request(smooth: nil, invertMouse: false, fine: false, sideButtons: false, foregroundExcluded: false)
    private var excludedBundleIDs: Set<String> = []
    private var frontmostBundleID: String?
    private var requestedMask: CGEventMask = 0
    private var installedMask: CGEventMask = 0
    private var displayLink: CVDisplayLink?
    private var framePending = false
    private var scrollPhaseBegan = false
    private var remainderX = 0.0
    private var remainderY = 0.0
    private var foregroundObserver: NSObjectProtocol?
    private let nanosPerTick: Double

    /// 合成事件的标记，避免自己发出的滚动再进一次钩子。
    private static let tag: Int64 = 0x57533253

    init() {
        var info = mach_timebase_info_data_t(numer: 1, denom: 1)
        mach_timebase_info(&info)
        nanosPerTick = Double(info.numer) / Double(info.denom)
    }

    var systemStopped: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return withLock { driver.phase == .stoppedBySystem }
    }

    func update(_ request: ScrollSession.Request, excluded: Set<String>) {
        dispatchPrecondition(condition: .onQueue(.main))
        withLock {
            self.request = request
            self.excludedBundleIDs = excluded
        }
    }

    func apply(installing: Bool, mask: CGEventMask) {
        dispatchPrecondition(condition: .onQueue(.main))
        if installing, port != nil, mask != installedMask { destroyPort() }
        requestedMask = mask
        let action = withLock { driver.plan(wanted: installing, isOpen: port != nil) }
        perform(action)
    }

    func noteSystemDisabled() {
        dispatchPrecondition(condition: .onQueue(.main))
        let action = withLock { driver.systemDisabled(isOpen: port != nil) }
        perform(action)
    }

    func setWatchingForeground(_ watch: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        if !watch {
            if let foregroundObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(foregroundObserver)
                self.foregroundObserver = nil
            }
            withLock { frontmostBundleID = nil }
            return
        }
        guard foregroundObserver == nil else { return }
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        withLock { frontmostBundleID = current }
        foregroundObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFrontmost(app?.bundleIdentifier)
        }
    }

    private func setFrontmost(_ bundleID: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
        withLock { frontmostBundleID = bundleID }
    }

    private func perform(_ action: HookAction) {
        switch action {
        case .open:
            if !createPort() { withLock { driver.openFailed() } }
        case .close:
            destroyPort()
        case .keep:
            break
        }
    }

    private func createPort() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let mask = requestedMask
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<ScrollTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type, event)
        }, userInfo: refcon) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        self.port = created
        self.source = source
        self.installedMask = mask
        let thread = Thread { [weak self] in
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
        thread.name = "WindowShade.ScrollTap"
        thread.stackSize = 512 * 1024
        self.thread = thread
        thread.start()
        return true
    }

    private func destroyPort() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopFrames()
        let created = withLock { () -> CFMachPort? in
            let current = port
            port = nil
            source = nil
            thread = nil
            session.cancel()
            remainderX = 0
            remainderY = 0
            scrollPhaseBegan = false
            return current
        }
        guard let created else { return }
        CGEvent.tapEnable(tap: created, enable: false)
        let runLoop = withLock { () -> CFRunLoop? in
            let current = threadRunLoop
            threadRunLoop = nil
            return current
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        CFMachPortInvalidate(created)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in self?.noteSystemDisabled() }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.tag { return pass }
        let sample: ScrollSession.Sample
        switch type {
        case .scrollWheel:
            let y = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            let x = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            if x == 0, y == 0 { return pass }
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
            let evidence = InputDeviceClassifier.ScrollEvidence(continuous: continuous, hasMomentum: momentum, device: nil, association: .none)
            sample = .scroll(evidence, notchesX: x, notchesY: y, option: event.flags.contains(.maskAlternate))
        case .otherMouseDown, .otherMouseUp:
            let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let evidence = InputDeviceClassifier.ScrollEvidence(continuous: false, hasMomentum: false, device: nil, association: .none)
            sample = .sideButton(evidence, number: number)
        default:
            return pass
        }
        let decision = withLock { () -> ScrollSession.Disposition in
            guard driver.onEvent(), let now = self.now() else { return .pass }
            // 不知道前台是谁时不改这条事件，也不把它记成「在例外名单里」。
            guard frontmostBundleID != nil else { return .pass }
            var current = request
            if let frontmostBundleID, excludedBundleIDs.contains(frontmostBundleID) { current.foregroundExcluded = true }
            return session.handle(sample, request: current, at: now)
        }
        switch decision {
        case .pass:
            return pass
        case .invert:
            invert(event)
            return pass
        case .line(let x, let y):
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(y))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(x))
            return pass
        case .side(let back):
            if type == .otherMouseDown { postSide(back: back) }
            return nil
        case .smooth(_, _, let finished):
            if finished || !ensureLink() {
                withLock {
                    session.cancel()
                    remainderX = 0
                    remainderY = 0
                }
                return pass
            }
            return nil
        }
    }

    private func invert(_ event: CGEvent) {
        let fields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
        ]
        for field in fields {
            let value = event.getIntegerValueField(field)
            if value != 0 { event.setIntegerValueField(field, value: -value) }
        }
    }

    private func postSide(back: Bool) {
        // 规格先用 ⌘[ / ⌘]。0x21、0x1E 是 ANSI 键盘上 [ 和 ] 的虚拟键码。
        let code: CGKeyCode = back ? 0x21 : 0x1E
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: Self.tag)
        up.setIntegerValueField(.eventSourceUserData, value: Self.tag)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func ensureLink() -> Bool {
        if withLock({ displayLink != nil }) { return true }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context -> CVReturn in
            guard let context else { return kCVReturnSuccess }
            Unmanaged<ScrollTap>.fromOpaque(context).takeUnretainedValue().frameOnDisplayLink()
            return kCVReturnSuccess
        }, context) == kCVReturnSuccess else { return false }
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else { return false }
        withLock { displayLink = link }
        return true
    }

    private func frameOnDisplayLink() {
        let schedule = withLock { () -> Bool in
            if framePending { return false }
            framePending = true
            return true
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in self?.emitFrame() }
    }

    private func emitFrame() {
        dispatchPrecondition(condition: .onQueue(.main))
        let began = Int64(NSEvent.Phase.began.rawValue)
        let changed = Int64(NSEvent.Phase.changed.rawValue)
        let ended = Int64(NSEvent.Phase.ended.rawValue)
        let posted: (x: Int32, y: Int32, phase: Int64, finished: Bool, endPhase: Bool)? = withLock {
            framePending = false
            guard let now = self.now(), case .smooth(let x, let y, let finished) = session.step(at: now) else { return nil }
            remainderX += x
            remainderY += y
            let wholeX = remainderX.rounded(.towardZero)
            let wholeY = remainderY.rounded(.towardZero)
            remainderX -= wholeX
            remainderY -= wholeY
            let pixelsX = Int32(clamping: Int(wholeX))
            let pixelsY = Int32(clamping: Int(wholeY))
            let phase = scrollPhaseBegan ? changed : began
            if pixelsX != 0 || pixelsY != 0 { scrollPhaseBegan = true }
            let endPhase = finished && scrollPhaseBegan
            if finished {
                scrollPhaseBegan = false
                remainderX = 0
                remainderY = 0
            }
            return (pixelsX, pixelsY, phase, finished, endPhase)
        }
        guard let posted else {
            stopFrames()
            return
        }
        if posted.x != 0 || posted.y != 0 { postScroll(x: posted.x, y: posted.y, phase: posted.phase) }
        if posted.endPhase { postScroll(x: 0, y: 0, phase: ended) }
        if posted.finished { stopFrames() }
    }

    private func postScroll(x: Int32, y: Int32, phase: Int64) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.tag)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.post(tap: .cgSessionEventTap)
    }

    private func stopFrames() {
        let link = withLock { () -> CVDisplayLink? in
            let current = displayLink
            displayLink = nil
            framePending = false
            return current
        }
        if let link { CVDisplayLinkStop(link) }
    }

    private func now() -> WS2.Instant? {
        let nanos = Double(mach_absolute_time()) * nanosPerTick
        guard nanos.isFinite, nanos >= 0 else { return nil }
        return WS2.Instant(seconds: nanos / 1_000_000_000)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
