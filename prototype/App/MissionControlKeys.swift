// 调度中心里按 ⌘W 关掉指针指着的那个窗口、按 ⌘Q 退出它的 App。
//
// 为什么要有这个：调度中心打开时，系统并没有把 ⌘W 交给谁，它会落到"最前面那个 App"
// （还在原处响应的那一个）身上，于是你以为在关指针指着的那扇窗，实际关掉的是别的一扇。
// Wins 补过这个洞（它的"调度中心 Pro"），我们的刘海两下也进调度中心，理应对得上。
//
// 只在确认调度中心开着时才动手，判断依据是 WindowManager 铺的那层 ExposeShieldWindow；
// 不在调度中心、指针底下不是普通窗口、按的不是 ⌘W / ⌘Q（或带了别的修饰键），一律原样放行。
//
// 编译单元：prototype/App/MissionControlKeys.swift

import Cocoa

/// 按 Ctrl+W 之后真正动手的那一层（主线程）。
@MainActor
enum MissionControlActions {
    enum Kind {
        case closeWindow
        case quitApp
    }

    static func perform(_ kind: Kind, target: MissionControlTarget) {
        switch kind {
        case .closeWindow:
            closeWindow(target)
        case .quitApp:
            quitApp(target)
        }
    }

    private static func closeWindow(_ target: MissionControlTarget) {
        guard let element = axElement(pid: target.pid, windowID: target.windowID) else {
            wlog("mc-keys: no AX window for id=\(target.windowID) pid=\(target.pid)")
            return
        }
        // 按钮关着的窗口（有些面板、系统窗口）不假装关掉了。
        guard isAXButtonEnabled(element, kAXCloseButtonAttribute as String) else {
            wlog("mc-keys: close button unavailable id=\(target.windowID) pid=\(target.pid)")
            return
        }
        _ = pressAXButton(element, kAXCloseButtonAttribute as String)
        wlog("mc-keys: closed id=\(target.windowID) pid=\(target.pid)")
    }

    private static func quitApp(_ target: MissionControlTarget) {
        guard target.pid != getpid() else { return }
        guard let app = NSRunningApplication(processIdentifier: target.pid) else { return }
        if app.terminate() {
            wlog("mc-keys: quit pid=\(target.pid)")
        } else {
            wlog("mc-keys: cannot quit pid=\(target.pid)")
        }
    }

    /// 按 CGWindowID 找那扇窗的 AX 元素：身份用 _AXUIElementGetWindow 核对，不靠标题或位置猜。
    /// 拿不到窗口号的 App 就当作找不到——宁可不做，也不能关错一扇。
    private static func axElement(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return nil }
        for element in elements {
            var actual: CGWindowID = 0
            if _AXUIElementGetWindow(element, &actual) == .success, actual == windowID {
                return element
            }
        }
        return nil
    }
}

/// 键盘事件钩子：只关心 ⌘W / ⌘Q，平时一律放行。
final class MissionControlKeys {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    /// 钩子线程自己的 run loop：拆掉钩子时要停它那一个，不能停主线程的。
    private var threadRunLoop: CFRunLoop?

    private(set) var installed = false

    /// 开关放在设置里，默认开。关掉时拆掉钩子，一个键都不看。
    static let defaultsKey = "MissionControl.keys"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: defaultsKey) == nil { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    func applySetting() {
        if Self.isEnabled { install() } else { uninstall() }
    }

    private func install() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !installed else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<MissionControlKeys>.fromOpaque(refcon).takeUnretainedValue()
            return keys.handle(type, event)
        }, userInfo: refcon) else {
            wlog("mc-keys: keyboard tap not available")
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
            self.threadRunLoop = nil
        }
        thread.name = "WindowShade.MissionControlKeys"
        thread.stackSize = 512 * 1024
        self.thread = thread
        installed = true
        thread.start()
        wlog("mc-keys: keyboard tap installed")
    }

    private func uninstall() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard installed else { return }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        // 停的是钩子线程的 run loop；它退出时自己把 source 摘掉。
        if let threadRunLoop { CFRunLoopStop(threadRunLoop) }
        if let port { CFMachPortInvalidate(port) }
        port = nil
        source = nil
        thread = nil
        installed = false
        wlog("mc-keys: keyboard tap removed")
    }

    /// tap 回调（自己的线程）。不是该管的一律 passUnretained，绝不动它。
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        // tap 被系统关掉（超时、用户改权限）时重新打开，否则从此瞎掉。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return nil
        }
        guard type == .keyDown else { return pass }
        let flags = event.flags
        guard flags.contains(.maskCommand) else { return pass }
        guard flags.intersection([.maskShift, .maskAlternate, .maskControl]).isEmpty else { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // 13 = W，12 = Q（虚拟键码，与键盘布局无关）。
        guard code == 13 || code == 12 else { return pass }

        let windows = WindowListCache.shared.onScreenWindows()
        guard MissionControlPick.isActive(in: windows) else { return pass }
        // 调度中心开着时这一下一定要吃掉：放行的话它会落到"最前面那个 App"身上，
        // 关掉一扇你没在看的窗——指针底下恰好没有窗口时尤其危险。
        guard let target = MissionControlPick.target(at: event.location, in: windows) else {
            wlog("mc-keys: nothing under the pointer; the key is swallowed anyway")
            return nil
        }

        let kind: MissionControlActions.Kind = code == 13 ? .closeWindow : .quitApp
        DispatchQueue.main.async {
            MainActor.assumeIsolated { MissionControlActions.perform(kind, target: target) }
        }
        return nil
    }
}
