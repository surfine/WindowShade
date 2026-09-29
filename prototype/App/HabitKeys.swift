// 卡住时刘海开口：只听、不吞的钩子（规则见 Core/HabitRules.swift，docs/stuck-habits.md 第一部分 §4.1）。
//
// 放在会话钩子的最后（tail）：被 WindowShade 自己吞掉的键和点按（默认的 ⌥Tab、调度中心里的 ⌘W/⌘Q、双击标题栏的那一下）
// 根本到不了这里。回调永远原样放行，只做 O(1) 的事：按键码和四个修饰键查表、跳过自动重复、记下时间，
// 要判断的交给 HabitContext 的队列。在自己的线程上跑（写法照 MissionControlKeys）。
// 用 .defaultTap 而不是 .listenOnly：后者要另外申请“输入监控”；而且事件在回调返回前不会交给 App，
// 回调里读的剪贴板 changeCount 一定是“按下之前”的值（P 的前后比较要靠它）。
//
// 听什么由开着的规则定：键盘规则开着才听 keyDown（单按 delete、Del 只在访达在前台时进表）；
// Home/End、⌥ 加小键盘、单按 ⇧ 开着才听 flagsChanged；iPad 那几条开着才听鼠标按下、松开；桌面两指下滑开着才听滚动。一条都没开（来处是“一直用 Mac”、刘海或教学关着、
// 每条都会了）时整个钩子拆掉，一个事件都不看。
// 隐私：不记字符、不读 AXValue；日志只写规则名、bundle id 和判定结果。

import Cocoa

final class HabitKeys: @unchecked Sendable {
    /// 开着的规则对应的听法（主线程算好整体换上，回调里只读）。
    struct Config: Equatable {
        var table = HabitTable()
        var keys = false
        var flags = false
        var mouse = false
        var scroll = false
        /// ⌥ 加小键盘（Windows 的 Alt 码）。
        var altDigits = false
        /// 单按 ⇧（要先上真机确认，默认不开）。
        var shiftTaps = false
        /// 这个时刻之前，所有 keyDown 和鼠标按下都报上去（⌘H 之后等他找回 App、🌐M 之后看他点没点菜单栏）。
        var watchUntil: TimeInterval = 0
        /// 探针用：自己进程发的事件也听（平时只听别人的，WindowShade 自己转发、补发的键不算他按的）。
        var acceptsOwnEvents = false

        var mask: CGEventMask {
            var mask: CGEventMask = 0
            if keys { mask |= 1 << CGEventType.keyDown.rawValue }
            if flags { mask |= 1 << CGEventType.flagsChanged.rawValue }
            if mouse { mask |= 1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue }
            if scroll { mask |= 1 << CGEventType.scrollWheel.rawValue }
            return mask
        }
    }

    /// 报给队列的一件事。时间都是开机后的秒数（ProcessInfo.systemUptime）。
    enum Observation {
        /// 规则表里的一下按键。pasteboard：和剪贴板有关的键，在交给 App 之前读的 changeCount。
        /// sinceLetter：离上一次单按字母多久（访达里按名字选文件）；sinceFn：离上一次按下 fn 多久（Apple 键盘的 fn←）。
        case key(signals: [HabitSignal], combo: HabitCombo, at: TimeInterval, target: pid_t, pasteboard: Int?,
                 sinceLetter: TimeInterval, sinceFn: TimeInterval)
        /// 按住 ⌥ 按下第一个小键盘数字（去读按之前的字数）。
        case altDigitsBegan(at: TimeInterval, target: pid_t)
        /// 松开 ⌥：一共按了几个小键盘数字。
        case altDigitsEnded(count: Int, at: TimeInterval, target: pid_t)
        /// 单按了一下 ⇧：按下到松开之间没有别的键、点按、滚动。
        case shiftTap(at: TimeInterval)
        /// 盯着的时候，任何一下 keyDown 或鼠标按下（只要 App 和时间）。
        case activity(at: TimeInterval, target: pid_t)
        case mouseDown(at: TimeInterval, location: CGPoint, target: pid_t, clicks: Int)
        /// down：这一次按下的位置和时间（算往哪儿甩了多远）。
        case mouseUp(at: TimeInterval, location: CGPoint, target: pid_t, clicks: Int, down: CGPoint?, downAt: TimeInterval?)
        /// 一次两指滚动（began 到 ended，不算惯性）：开始时指针在哪，一共滚了多少。
        case scrollBegan(at: TimeInterval, location: CGPoint)
        case scrollEnded(at: TimeInterval, deltaY: CGFloat)
    }

    /// 回调线程上调用：要快，一般就是把事情排到队列上。
    var onObservation: (@Sendable (Observation) -> Void)?

    /// WindowShade 自己补发的按键（点提示时替他按的那一下）打上这个记号，钩子不当成他按的。
    static let ownEventTag: Int64 = 0x5753_4842

    private let lock = NSLock()
    private var config = Config()
    private let ownPID = getpid()

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?
    private var installedMask: CGEventMask = 0
    private(set) var installed = false

    // 只在回调线程上读写。
    private var lastLetter: TimeInterval = -.infinity
    private var lastFn: TimeInterval = -.infinity
    private var altDigitCount = 0
    private var altTarget: pid_t = 0
    private var shiftDownAt: TimeInterval?
    private var keyDownsSinceShift = 0
    private var shiftCounters: (clicks: UInt32, scrolls: UInt32)?
    private var downAt: (point: CGPoint, at: TimeInterval)?
    private var scrollTotal: CGFloat = 0
    private var scrolling = false

    /// 换上新的听法：要听的事件种类变了就重装钩子，只是表变了就原地换。主线程调用。
    func apply(_ next: Config) {
        dispatchPrecondition(condition: .onQueue(.main))
        lock.lock()
        // 正在盯着的（⌘H 之后等他找回 App）不因为重算一遍规则就断掉。
        let watching = config.watchUntil
        config = next
        config.watchUntil = max(watching, next.watchUntil)
        lock.unlock()
        let mask = next.mask
        if mask == 0 {
            uninstall()
        } else if !installed || mask != installedMask {
            uninstall()
            install(mask)
        }
    }

    /// 只换表（访达进出前台时）：听的事件种类不变，钩子不重装，别的设置（盯到什么时候）也不动。哪个线程都行。
    func setTable(_ table: HabitTable) {
        lock.lock()
        config.table = table
        lock.unlock()
    }

    /// 只改“盯到什么时候”（哪个线程都行）。
    func watch(until time: TimeInterval) {
        lock.lock()
        config.watchUntil = max(config.watchUntil, time)
        lock.unlock()
    }

    private func install(_ mask: CGEventMask) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<HabitKeys>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
        }, userInfo: refcon) else {
            wlog("habits: event tap not available")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.port = port
        self.source = source
        let thread = Thread { [weak self] in
            guard let self, let source = self.source else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.threadRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "WindowShade.HabitKeys"
        // 每一下按键都要等回调返回才交给 App：和按窗口切换的钩子一样用最高的优先级，CPU 忙时也不拖慢打字。
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        self.thread = thread
        installedMask = mask
        installed = true
        thread.start()
        wlog("habits: tap installed (mask \(String(mask, radix: 16)))")
    }

    func uninstall() {
        guard installed else { return }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let threadRunLoop { CFRunLoopStop(threadRunLoop) }
        if let port { CFMachPortInvalidate(port) }
        port = nil
        source = nil
        thread = nil
        threadRunLoop = nil
        installed = false
        installedMask = 0
        wlog("habits: tap removed")
    }

    /// 回调（自己的线程）。永远原样放行。
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventTag { return pass }
        lock.lock()
        let config = self.config
        lock.unlock()
        if !config.acceptsOwnEvents, pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)) == ownPID {
            return pass
        }
        let now = ProcessInfo.processInfo.systemUptime
        let target = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
        switch type {
        case .keyDown: keyDown(event, config: config, now: now, target: target)
        case .flagsChanged: flagsChanged(event, config: config, now: now)
        case .leftMouseDown, .leftMouseUp: mouse(type, event, config: config, now: now, target: target)
        case .scrollWheel: scroll(event, now: now)
        default: break
        }
        return pass
    }

    private func keyDown(_ event: CGEvent, config: Config, now: TimeInterval, target: pid_t) {
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        let modifiers = HabitCombo.modifiers(flags: flags)
        keyDownsSinceShift += 1
        // 盯着的时候（⌘H 之后等他找回 App）：别处的按键算“在做别的事”；带 ⌘ 的（⌘Tab 切回去）不算。
        if now < config.watchUntil, !modifiers.contains(.command) { onObservation?(.activity(at: now, target: target)) }
        // 单按字母（打名字、打字）：只记时间，不记是哪个字母。
        if HabitKey.letters[code] != nil, modifiers.isDisjoint(with: [.command, .control, .option]) { lastLetter = now }
        if config.altDigits, modifiers == .option, HabitKey.keypadDigits.contains(code),
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            if altDigitCount == 0 {
                altTarget = target
                onObservation?(.altDigitsBegan(at: now, target: target))
            }
            altDigitCount += 1
            return
        }
        let signals = config.table.classify(keyCode: code, flags: flags,
                                            autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        guard !signals.isEmpty else { return }
        let combo = HabitCombo(keyCode: code, flags: flags)
        let clipboard = signals.contains { signal in
            switch signal {
            case .foreign(let rule), .mac(let rule): return rule.watchesPasteboard
            case .emacs: return false
            }
        }
        onObservation?(.key(signals: signals, combo: combo, at: now, target: target,
                            pasteboard: clipboard ? NSPasteboard.general.changeCount : nil,
                            sinceLetter: now - lastLetter, sinceFn: now - lastFn))
    }

    private func flagsChanged(_ event: CGEvent, config: Config, now: TimeInterval) {
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        if code == HabitKey.function, flags & HabitCombo.fnBit != 0 { lastFn = now }
        let modifiers = HabitCombo.modifiers(flags: flags)
        if altDigitCount > 0, !modifiers.contains(.option) {
            onObservation?(.altDigitsEnded(count: altDigitCount, at: now, target: altTarget))
            altDigitCount = 0
        }
        guard config.shiftTaps else { return }
        // 单按 ⇧：按下时只有 ⇧，松开前没有别的键、点按、滚动，0.5 秒内松开。
        if modifiers == .shift, shiftDownAt == nil {
            shiftDownAt = now
            keyDownsSinceShift = 0
            shiftCounters = Self.counters()
        } else if modifiers.isEmpty, let down = shiftDownAt {
            shiftDownAt = nil
            let quiet = keyDownsSinceShift == 0 && shiftCounters.map { $0 == Self.counters() } == true
            if quiet, now - down < 0.5 { onObservation?(.shiftTap(at: now)) }
        } else {
            shiftDownAt = nil
        }
    }

    /// 点按、滚动的累计次数（系统的计数，不用自己听这些事件）。
    private static func counters() -> (clicks: UInt32, scrolls: UInt32) {
        (CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown)
            &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: .rightMouseDown),
         CGEventSource.counterForEventType(.combinedSessionState, eventType: .scrollWheel))
    }

    private func mouse(_ type: CGEventType, _ event: CGEvent, config: Config, now: TimeInterval, target: pid_t) {
        let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
        let location = event.location
        if type == .leftMouseDown {
            downAt = (location, now)
            if now < config.watchUntil { onObservation?(.activity(at: now, target: target)) }
            onObservation?(.mouseDown(at: now, location: location, target: target, clicks: clicks))
        } else {
            let down = downAt
            downAt = nil
            onObservation?(.mouseUp(at: now, location: location, target: target, clicks: clicks,
                                    down: down?.point, downAt: down?.at))
        }
    }

    /// 两指滚动：只看有阶段的那种（触控板），began 报一次位置，ended 报一次总量；惯性阶段不算。
    private func scroll(_ event: CGEvent, now: TimeInterval) {
        guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return }
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        switch phase {
        case 1:   // began
            scrolling = true
            scrollTotal = 0
            onObservation?(.scrollBegan(at: now, location: event.location))
        case 2:   // changed
            if scrolling { scrollTotal += CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)) }
        case 4:   // ended
            guard scrolling else { return }
            scrolling = false
            onObservation?(.scrollEnded(at: now, deltaY: scrollTotal))
        case 8:   // cancelled
            scrolling = false
        default:
            break
        }
    }
}
