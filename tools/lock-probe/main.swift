// 阶段 1B：真锁屏小窗口实验（人在场）。**不是 App 的一部分**，单独编译、单独运行，
// 只为了回答一个问题：这台机器、这个系统构建上，私有空间配方到底能不能让一个普通窗口
// 出现在**真正的锁屏**上，而且不影响系统认证、解锁后自己消失。
//
// 用法（都经 tests/run-lock-probe.sh）：
//   run-lock-probe.sh                       只查符号在不在（不建空间、不动窗口、不锁屏）
//   run-lock-probe.sh --space               真锁屏实验：委托一个 240×48 的小窗口到锁屏空间
//   run-lock-probe.sh --level-only          对照：同样的窗口，只提高窗口层级，不调空间 API
//   --pre-create / --post-create            锁屏前就把窗口建好 / 确认锁上之后再建
//   --seconds 90                            在锁屏上最多待多久（到点自己撤）
//
// 安全规矩（照 Glance 那份调研定下的）：
// - 非 key、非 main、整窗鼠标穿透，绝不挡认证；位置放屏幕右上角，不进认证区域正中；
// - 自己到期撤场（Timer 判断，不依赖 display link），外面还有一层父进程硬超时；
// - **绝不尝试解锁**；真锁屏由你按 ⌃⌘Q 锁、用系统认证解。
// - ABI 未核定：这里照上游配方用 Int32 声明，只记录原始返回值，不当成契约。

import Cocoa

// MARK: - 私有 SkyLight 的六个符号（只在这个探针里用）

private typealias F_SLSMainConnectionID = @convention(c) () -> Int32
private typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
private typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
private typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
private typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

private struct SkyLightSymbols {
    let mainConnection: F_SLSMainConnectionID
    let spaceCreate: F_SLSSpaceCreate
    let setAbsoluteLevel: F_SLSSpaceSetAbsoluteLevel
    let showSpaces: F_SLSShowSpaces
    let addWindows: F_SLSSpaceAddWindowsAndRemoveFromSpaces
    let removeWindows: F_SLSRemoveWindowsFromSpaces

    static let names = [
        "SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel",
        "SLSShowSpaces", "SLSSpaceAddWindowsAndRemoveFromSpaces", "SLSRemoveWindowsFromSpaces"
    ]

    static func load() -> (symbols: SkyLightSymbols?, handle: UnsafeMutableRawPointer?, present: [String: Bool]) {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        ]
        var handle: UnsafeMutableRawPointer?
        for path in paths {
            handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if handle != nil { log("symbols: loaded \(path)"); break }
            log("symbols: load failed \(path): \(String(cString: dlerror()))")
        }
        guard let handle else { return (nil, nil, [:]) }
        var present: [String: Bool] = [:]
        var found: [UnsafeMutableRawPointer] = []
        for name in names {
            _ = dlerror()
            let address = dlsym(handle, name)
            let ok = address != nil && dlerror() == nil
            present[name] = ok
            if let address { found.append(address) }
        }
        guard found.count == names.count else { return (nil, handle, present) }
        return (SkyLightSymbols(
            mainConnection: unsafeBitCast(found[0], to: F_SLSMainConnectionID.self),
            spaceCreate: unsafeBitCast(found[1], to: F_SLSSpaceCreate.self),
            setAbsoluteLevel: unsafeBitCast(found[2], to: F_SLSSpaceSetAbsoluteLevel.self),
            showSpaces: unsafeBitCast(found[3], to: F_SLSShowSpaces.self),
            addWindows: unsafeBitCast(found[4], to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self),
            removeWindows: unsafeBitCast(found[5], to: F_SLSRemoveWindowsFromSpaces.self)
        ), handle, present)
    }
}

// MARK: - 日志与状态

private let started = Date()
private func log(_ message: String) {
    let t = String(format: "%7.3f", Date().timeIntervalSince(started))
    print("[\(t)s] \(message)")
    fflush(stdout)
}

/// 权威锁屏状态：唯一可信来源，通知在这里不用（探针不接通知，直接轮询这一个查询）。
private func screenIsLocked() -> Bool {
    let state = CGSessionCopyCurrentDictionary() as? [String: Any]
    return state?["CGSSessionScreenIsLocked"] as? Bool == true
}

// MARK: - 探针

private final class LockProbe: NSObject, NSApplicationDelegate {
    private let useSpace: Bool
    private let levelOnly: Bool
    private let preCreate: Bool
    private let seconds: Double
    private let waitForLock: Double

    private var window: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var tick = 0
    private var lockedAt: Date?
    private var space: Int32?
    private var connection: Int32?
    private var delegated = false
    private var expired = false
    private var wasLocked = false

    init(useSpace: Bool, levelOnly: Bool, preCreate: Bool, seconds: Double, waitForLock: Double) {
        self.useSpace = useSpace
        self.levelOnly = levelOnly
        self.preCreate = preCreate
        self.seconds = seconds
        self.waitForLock = waitForLock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        log("probe: os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        log("probe: arch=arm64")
        #else
        log("probe: arch=x86_64")
        #endif
        log("probe: mode=\(levelOnly ? "level-only" : (useSpace ? "space" : "inert")) create=\(preCreate ? "pre" : "post") seconds=\(Int(seconds))")
        if preCreate { makeWindow() }
        log("probe: 请把屏幕锁上（⌃⌘Q）。最多等 \(Int(waitForLock)) 秒；看到右上角的小标记在数数就说明成功，之后用系统认证解锁即可。")
        pollForLock()
    }

    /// 每 0.2 秒看一次权威状态：等到真锁上再动手（不靠通知，也不猜）。
    private func pollForLock() {
        let deadline = Date().addingTimeInterval(waitForLock)
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.wasLocked {
                if !screenIsLocked() {
                    timer.invalidate()
                    self.retreat(reason: "unlocked")
                } else if self.expired {
                    timer.invalidate()
                    self.retreat(reason: "expired")
                }
                return
            }
            if screenIsLocked() {
                self.wasLocked = true
                self.lockedAt = Date()
                log("probe: locked (t=0)")
                self.enterLockScreen()
            } else if Date() > deadline {
                timer.invalidate()
                log("probe: 一直没锁上，退出（什么都没做）")
                self.finish(code: 3)
            }
        }
    }

    private func makeWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: 240, height: 48)
        // 右上角，离屏幕边 24 点：不进认证区域正中，也不压住时间那一行。
        let origin = NSPoint(x: screen.frame.maxX - size.width - 24, y: screen.frame.maxY - size.height - 24)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true               // 整窗鼠标穿透：绝不挡住认证
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // 和 Glance 一样用「shielding + 1」：这是公开接口能给到的最高层，也是 --level-only 对照组的层。
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        let text = NSTextField(labelWithString: "WindowShade lock probe 0")
        text.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        text.textColor = .white
        text.frame = NSRect(x: 12, y: 14, width: size.width - 24, height: 20)
        panel.contentView?.addSubview(text)
        label = text
        window = panel
        log("probe: window created number=\(panel.windowNumber) level=\(Int(panel.level.rawValue)) frame=\(panel.frame)")
    }

    private func enterLockScreen() {
        if useSpace, let loaded = SkyLightSymbols.load().symbols {
            let conn = loaded.mainConnection()
            // 上游配方：第二个参数 1（其它值 Finder 会把桌面图标画进这个空间），层级 400。
            let newSpace = loaded.spaceCreate(conn, 1, 0)
            let level = loaded.setAbsoluteLevel(conn, newSpace, 400)
            let shown = loaded.showSpaces(conn, [newSpace] as CFArray)
            connection = conn
            space = newSpace
            log("probe: space create=\(newSpace) setLevel(400)=\(level) showSpaces=\(shown) conn=\(conn)")
        } else if useSpace {
            log("probe: 六个符号没齐，放弃（什么都不做）")
            finish(code: 2)
            return
        } else {
            log("probe: level-only 对照：不动空间，只靠窗口层级")
        }
        if window == nil { makeWindow() }
        window?.orderFrontRegardless()
        if useSpace, let loaded = SkyLightSymbols.load().symbols, let conn = connection, let space {
            let result = loaded.addWindows(conn, space, [window?.windowNumber ?? 0] as CFArray, 7)
            delegated = true
            log("probe: delegate window=\(window?.windowNumber ?? 0) -> space \(space) result=\(result)")
        }
        startCountUp()
    }

    /// 数数：能看见它在涨，才说明这个窗口真的在锁屏上被合成、而且在刷新。
    /// 用 Timer 而不是 display link——显示器睡了以后渲染回调不一定还会来。
    private func startCountUp() {
        let expiry = Date().addingTimeInterval(seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.tick += 1
            self.label?.stringValue = "WindowShade lock probe \(self.tick)"
            if self.tick % 20 == 0 {
                let onLock = self.lockedAt.map { Date().timeIntervalSince($0) } ?? 0
                log("probe: tick=\(self.tick) visible=\(self.window?.isVisible == true) alpha=\(String(format: "%.2f", self.window?.alphaValue ?? 0)) onLockFor=\(String(format: "%.0f", onLock))s screenLocked=\(screenIsLocked())")
            }
            if Date() > expiry {
                self.expired = true
                timer.invalidate()
                self.retreat(reason: "expired")
            }
        }
    }

    /// 撤场：先隐藏，再 undelegate，最后收窗口。不等动画、不重试到天荒地老。
    private func retreat(reason: String) {
        log("probe: retreat (\(reason)) tick=\(tick)")
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        if delegated, let loaded = SkyLightSymbols.load().symbols, let conn = connection, let space {
            let number = window?.windowNumber ?? 0
            let result = loaded.removeWindows(conn, [number] as CFArray, [space] as CFArray)
            log("probe: undelegate window=\(number) result=\(result)")
        }
        delegated = false
        finish(code: 0)
    }

    private func finish(code: Int32) {
        log("probe: done code=\(code)")
        exit(code)
    }
}

// MARK: - 入口

private func value(after name: String) -> Double? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), arguments.count > index + 1 else { return nil }
    return Double(arguments[index + 1])
}

let arguments = CommandLine.arguments
if arguments.contains("--help") {
    print("用法见 tools/lock-probe/main.swift 顶部注释。")
    exit(0)
}

// 只查符号：不建窗口、不建空间、不锁屏。
private let loaded = SkyLightSymbols.load()
log("probe: symbols")
for name in SkyLightSymbols.names {
    log("  \(name): \(loaded.present[name] == true ? "YES" : "NO")")
}
let missing = SkyLightSymbols.names.filter { loaded.present[$0] != true }
if !arguments.contains("--space") && !arguments.contains("--level-only") {
    if loaded.handle == nil { log("probe: 框架没加载起来"); exit(2) }
    if !missing.isEmpty { log("probe: 少了 \(missing.joined(separator: ", "))"); exit(1) }
    log("probe: 六个符号都在（只证明存在性，不证明锁屏可见）")
    exit(0)
}
if arguments.contains("--space") && !missing.isEmpty {
    log("probe: 少了 \(missing.joined(separator: ", "))，拒绝做空间实验")
    exit(2)
}

private let probe = LockProbe(useSpace: arguments.contains("--space"),
                      levelOnly: arguments.contains("--level-only"),
                      preCreate: arguments.contains("--pre-create"),
                      seconds: value(after: "--seconds") ?? 90,
                      waitForLock: value(after: "--wait") ?? 180)
private let app = NSApplication.shared
private let delegate = probe
app.delegate = delegate
app.run()
