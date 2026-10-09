// R17 探针：iPad 来的三条习惯规则（调度中心瞥一眼 i2、🌐H i5、主屏幕开了又关再往上滚 i18）要的信号拿不拿得到。
// 只读、不发任何键和点按、不开调度中心。默认跑本机无交互能确认的部分；需要人手操作的用 --live 看现场。
//
//   bash tools/probes/run-probe.sh HabitSignalProbe              无交互部分，约 6 秒
//   bash tools/probes/run-probe.sh HabitSignalProbe --live 60    60 秒内逐条打印现场事件，Aaron 照下面的清单操作
//   --seconds N                                                   无交互部分的旁听秒数（默认 6）
//
// --live 时 Aaron 依次做（每步之间停 2 秒）：
//   1. 三指上滑打开调度中心，不到一秒又三指下滑关掉，重复两次；再打开，点一个别的窗口。
//   2. 按 🌐H，3 秒内再按一次 🌐H；然后点一下 Dock 上的 App 图标。
//   3. 在访达或浏览器里往上大幅滑动页面（两指，一次 400 点以上）。
//   4. 点一下刘海（回到主屏幕）再点一下关掉（WindowShade 要开着）：这一步只用来对时间，主屏幕开合是 WindowShade 自己的事，不是系统信号。
// 键盘只打印键码是 4（H）、63（fn）、126（↑）、115（Home）这几个，别的键只写 key=other，不记按了什么。
//
// 输出是一行一条的 SIGNAL / EVENT。能确认的写 available，被系统挡住的写 unavailable（附原因），
// 要人手操作才能确认的写 pending-device。不把预期当结果。
import Cocoa
import ApplicationServices

private func uptime() -> Double { ProcessInfo.processInfo.systemUptime }
private func stamp() -> String { String(format: "%.3f", uptime()) }

private func signal(_ name: String, _ status: String, _ detail: String) {
    print("SIGNAL \(name): \(status) — \(detail)")
}

private let notableNames = ["com.apple.expose.awake", "com.apple.expose.sleep",
                            "com.apple.expose.front.awake", "com.apple.expose.front.sleep"]
private let interestingPattern = try! NSRegularExpression(pattern: "expose|mission|dock|launchpad|showdesktop|spaces|desktop",
                                                          options: [.caseInsensitive])

private func looksInteresting(_ name: String) -> Bool {
    interestingPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
}

/// 系统窗口表里有没有这几个名字的窗口（只读名字和层，不读标题内容、不截图）。
private func windowNames() -> [String: Int] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var names: [String: Int] = [:]
    for info in list {
        guard let owner = info[kCGWindowOwnerName as String] as? String else { continue }
        let name = info[kCGWindowName as String] as? String ?? ""
        if name == "ExposeShieldWindow" { names["ExposeShieldWindow", default: 0] += 1 }
        if owner == "Dock", ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0) != 0 {
            names["Dock layer>0 window", default: 0] += 1
        }
    }
    return names
}

private var seenNotifications: [String: Int] = [:]
private var liveMode = false

private func installNotificationListener() -> NSObjectProtocol {
    // 名字留空是通配：只记名字，不记内容。
    DistributedNotificationCenter.default().addObserver(forName: nil, object: nil, queue: .main) { note in
        let name = note.name.rawValue
        guard looksInteresting(name) else { return }
        seenNotifications[name, default: 0] += 1
        if liveMode { print("EVENT \(stamp()) notification \(name)") }
    }
}

private func axReport() {
    let trusted = AXIsProcessTrusted()
    signal("accessibility-trust", trusted ? "available" : "unavailable",
           trusted ? "this process may use the AX API" : "this process is not trusted; AX observers cannot be installed (grant the terminal in Privacy & Security)")
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        signal("dock-ax-observer", "unavailable", "Dock process not found")
        return
    }
    var observer: AXObserver?
    let created = AXObserverCreate(dock.processIdentifier, { _, _, _, _ in }, &observer)
    guard created == .success, let observer else {
        signal("dock-ax-observer", "unavailable", "AXObserverCreate returned \(created.rawValue)")
        return
    }
    let element = AXUIElementCreateApplication(dock.processIdentifier)
    // 这些名字是社区文档里 Dock 发过的辅助功能通知；是否真发要在 --live 里看，这里只看能不能登记上。
    var results: [String] = []
    for name in ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit",
                 "AXFocusedUIElementChanged", "AXWindowShadeBogusControl"] {
        let code = AXObserverAddNotification(observer, element, name as CFString, nil)
        results.append("\(name)=\(code.rawValue)")
    }
    // 最后一个是对照：编的名字被拒（-25207 notificationUnsupported）说明登记上的几条是 Dock 真声明了的；
    // 编的名字也登记得上，则“登记成功”不能当作 Dock 会发这条通知。声明了不等于三指手势时真会发，那要 --live。
    let bogusAccepted = results.last?.hasSuffix("=0") == true
    let installed = results.filter { $0.hasSuffix("=0") }.count
    signal("dock-ax-observer", installed > 0 ? "available" : "unavailable",
           "AXObserverAddNotification codes (0 is success): \(results.joined(separator: ", ")); "
           + (bogusAccepted ? "the made-up control name was accepted too, so registering proves nothing about the Dock firing it; "
                            : "the made-up control name is refused (-25207), so the accepted names are ones the Dock declares; ")
           + "whether Dock fires them on a three-finger swipe is pending-device")
}

private func tapReport() {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
    let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                 eventsOfInterest: mask, callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                                 userInfo: nil)
    signal("session-listen-tap", port != nil ? "available" : "unavailable",
           port != nil ? "a listen-only session tap can be created (keyDown, flagsChanged, leftMouseDown, scrollWheel)"
                       : "tapCreate returned nil; Input Monitoring is not granted to this process")
    if let port { CFMachPortInvalidate(port) }
}

/// --live：listen-only 会话 tap。只打印 H(4)、fn(63)、↑(126)、Home(115)的键码和修饰位；鼠标只打印落点是不是 Dock。
private final class LiveTap {
    var port: CFMachPort?
    var source: CFRunLoopSource?
    let dockPID: pid_t = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier ?? 0
    var scrollTotal: Double = 0
    var scrolling = false

    func install() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: { _, type, event, refcon in
            if let refcon { Unmanaged<LiveTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard [4, 63, 126, 115].contains(code) else { print("EVENT \(stamp()) key=other"); return }
            print("EVENT \(stamp()) keyDown code=\(code) flags=0x\(String(event.flags.rawValue, radix: 16)) autorepeat=\(event.getIntegerValueField(.keyboardEventAutorepeat))")
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 63 { print("EVENT \(stamp()) flagsChanged fn flags=0x\(String(event.flags.rawValue, radix: 16))") }
        case .leftMouseDown:
            let target = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventTargetUnixProcessID))
            print("EVENT \(stamp()) mouseDown onDock=\(dockPID != 0 && target == dockPID)")
        case .scrollWheel:
            guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return }
            switch event.getIntegerValueField(.scrollWheelEventScrollPhase) {
            case 1: scrolling = true; scrollTotal = 0
            case 2: if scrolling { scrollTotal += event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) }
            case 4:
                if scrolling { print("EVENT \(stamp()) scrollEnded totalPointDeltaY=\(Int(scrollTotal))") }
                scrolling = false
            default: break
            }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        default: break
        }
    }
}

@main
struct HabitSignalProbe {
    static func main() {
        let args = CommandLine.arguments
        func value(_ flag: String) -> Double? {
            guard let index = args.firstIndex(of: flag), args.count > index + 1 else { return nil }
            return Double(args[index + 1])
        }
        let live = value("--live")
        let seconds = live ?? value("--seconds") ?? 6
        liveMode = live != nil
        print("# HabitSignalProbe \(ProcessInfo.processInfo.operatingSystemVersionString) mode=\(liveMode ? "live" : "unattended") seconds=\(Int(seconds))")

        let before = windowNames()
        axReport()
        tapReport()
        let listener = installNotificationListener()
        let tap = LiveTap()
        if liveMode {
            if tap.install() { print("# live tap installed; act now") } else { signal("live-tap", "unavailable", "Input Monitoring is not granted") }
        }
        var shieldLast = before["ExposeShieldWindow", default: 0]
        var timer: Timer?
        if liveMode {
            // 只在 --live 的几十秒里每 0.1 秒看一眼窗口表，为了对上调度中心真正开合的时刻；探针结束就没了。
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let now = windowNames()["ExposeShieldWindow", default: 0]
                if now != shieldLast { print("EVENT \(stamp()) ExposeShieldWindow count=\(now)") }
                shieldLast = now
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        timer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(listener)

        // 汇总。
        let heardNotable = notableNames.filter { seenNotifications[$0] != nil }
        let others = seenNotifications.keys.filter { !notableNames.contains($0) }.sorted()
        print("SUMMARY notifications heard: \(seenNotifications.isEmpty ? "none" : seenNotifications.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", "))")
        signal("mission-control-notification",
               heardNotable.isEmpty ? "pending-device" : "available",
               heardNotable.isEmpty
                   ? "no expose.awake/sleep during the \(Int(seconds)) s listen (nobody opened Mission Control); run --live and swipe three fingers to know if the Dock posts them for the gesture"
                   : "heard \(heardNotable.joined(separator: ", ")); in --live check the times against the swipe")
        if !others.isEmpty { print("SUMMARY other dock-ish notifications: \(others.joined(separator: ", "))") }
        signal("expose-shield-window", "available",
               "baseline ExposeShieldWindow count \(before["ExposeShieldWindow", default: 0]) (0 when Mission Control is closed); opening it is pending-device")
        signal("globe-h-key", "pending-device", "whether the session tap sees fn+H (system may swallow it) needs a real keyboard; use --live and press 🌐H")
        signal("dock-app-click", "pending-device", "mouseDown target == Dock pid is what HabitContext already uses for dock drags; confirm in --live")
        signal("home-open-close", "pending-device", "WindowShade's own home screen: the rule needs HabitCenter.noteHome from LaunchpadController show/hide, not a system signal")
        signal("page-scroll-up", "pending-device", "phase-delimited trackpad scroll total comes from the same tap as desktop search; confirm the sign in --live")
        print("DONE")
    }
}
