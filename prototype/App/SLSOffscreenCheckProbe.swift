import Cocoa
import ApplicationServices

/// F7 真机取证：privateOffscreen 的收起验证要看窗口服务器的外框，不能只看 AX。
///
/// 停车走私有 SkyLight，那一次移动既不更新 AX 属性、也不落 kCGWindowIsOnscreen。
/// 只看 AX 时，刚停好的窗口会被判成「可见」，整支收起跟着回滚（silent fold completion
/// ok=false，见 round2 F7 的读数）。这个探针用探针进程自己的两扇临时窗口走真实入口，
/// 把三方读数与判定钉在一起：
///   1) privateSLSOffscreenHide 必须能把这扇窗停进停车带（返回 .privateOffscreen）；
///   2) 停车后 AX 仍报屏上坐标——只看 AX 的旧判据在这里会读出 .visible，这是 F7 的现场；
///   3) observeFoldHide(.privateOffscreen) 必须读出 .hidden；
///   4) FoldVerifier 走完一遍必须结出 hidden（旧判据会结出 visible 并回滚收起）；
///   5) 没停车的那扇窗必须仍读出 .visible，停回来的那扇也必须重新读出 .visible：
///      判据得跟着窗口服务器两头走，不能写成恒真或恒假。
/// 不碰 Finder、浏览器、未保存的窗口，也不碰每天在用的那份 WindowShade。
/// 用法：tests/run-sls-offscreen-check.sh
@MainActor
final class SLSOffscreenCheckProbe {
    private let owner = AppDelegate()
    private var parkedWindow: NSWindow?
    private var neighbourWindow: NSWindow?
    private var failures: [String] = []

    func run() {
        Task { @MainActor in await exercise() }
    }

    private func exercise() async {
        print("INFO sls-offscreen-build accessibility=\(AXIsProcessTrusted()) sls=\(PrivateSLSWindowMover.shared.isAvailable)")
        if !AXIsProcessTrusted() {
            print("INFO sls-offscreen: 这份隔离构建还没有辅助功能，打开系统设置后等待授权")
            _ = owner.ensureAccessibility()
            let trusted = await wait(120) { AXIsProcessTrusted() }
            guard trusted else {
                finish("辅助功能未授权，没有移动任何窗口")
                return
            }
            print("INFO sls-offscreen-build accessibility=true")
        }
        NotchController.probeSilence = true
        owner.ownsGlobalInput = false
        owner.duoController.persistsSettings = false
        // 和真实启动、其它探针一样先立好状态栏项：会话变化会去排一次菜单重建，
        // 没有这一项时 rebuildMenu 会强解包 nil。探针自己钉的项不留在菜单栏。
        owner.setupStatusItem()
        owner.statusItem.isVisible = false

        guard PrivateSLSWindowMover.shared.isAvailable else {
            finish("这份构建拿不到私有 SkyLight")
            return
        }

        let parked = makeWindow(x: 360, y: 320, width: 520, height: 320, title: "停车 · 探针")
        let neighbour = makeWindow(x: 900, y: 180, width: 320, height: 220, title: "对照 · 探针")
        parkedWindow = parked
        neighbourWindow = neighbour
        parked.makeKeyAndOrderFront(nil)
        neighbour.orderFront(nil)

        guard let parkedID = await serverWindowID(for: parked),
              let neighbourID = await serverWindowID(for: neighbour),
              let parkedElement = axWindowElement(pid: getpid(), id: parkedID),
              let neighbourElement = axWindowElement(pid: getpid(), id: neighbourID),
              let parkedSize = axSize(parkedElement),
              parkedSize.width > 0, parkedSize.height > 0,
              let parkedOrigin = axPosition(parkedElement) else {
            finish("探针自己的两扇窗还没进窗口服务器，或辅助功能读不到")
            return
        }
        let neighbourSize = axSize(neighbourElement) ?? CGSize(width: 320, height: 220)
        print("INFO probe-id parked=\(parkedID) neighbour=\(neighbourID)")
        print("INFO before parked \(readings(parkedID, parkedElement, fallback: parkedSize))")
        print("INFO before neighbour \(readings(neighbourID, neighbourElement, fallback: neighbourSize))")

        // 就绪判定：还没停车的窗口，privateOffscreen 必须读出「看得见」，
        // 不然下面的 hidden 分不出是判据准还是判据恒 hidden。
        let ready = owner.observeFoldHide(.privateOffscreen, win: parkedElement, pid: getpid(), id: parkedID)
        if ready == .visible {
            print("PASS sls-ready: 没停车的窗口读出 visible")
        } else {
            failures.append("sls-ready: 没停车的窗口读出 \(ready)，判据可能盯错了窗口")
        }

        // 真实入口：私有停车。
        let hide = owner.privateSLSOffscreenHide(parkedElement, id: parkedID,
                                                 originalPosition: parkedOrigin, size: parkedSize,
                                                 pid: getpid(), reason: "sls-offscreen-check")
        if hide == .privateOffscreen {
            print("PASS sls-park: privateSLSOffscreenHide → privateOffscreen id=\(parkedID)")
        } else {
            failures.append("sls-park: privateSLSOffscreenHide 返回 \(String(describing: hide))，这扇窗没停进停车带")
        }
        let parkedReading = readings(parkedID, parkedElement, fallback: parkedSize)
        print("INFO parked \(parkedReading)")

        // F7 现场：停车之后 AX 还报着屏上坐标，只看 AX 的旧判据会读出 visible。
        let parkedVisibleByAX = axPosition(parkedElement).map { windowIsVisible(pos: $0, size: parkedSize) } ?? false
        if parkedVisibleByAX {
            print("PASS sls-f7-premise: 停车后 AX 仍报屏上坐标，只看 AX 会读成 visible")
        } else {
            failures.append("sls-f7-premise: 停车后 AX 也报出屏外坐标，F7 前提变了，要重新取证 \(parkedReading)")
        }

        let observation = owner.observeFoldHide(.privateOffscreen, win: parkedElement, pid: getpid(), id: parkedID)
        if observation == .hidden {
            print("PASS sls-hidden: 停好的窗口读出 hidden")
        } else {
            failures.append("sls-hidden: 停好的窗口读出 \(observation)，收起会被回滚")
        }

        // 整支验证走一遍：结出 hidden 才算这一次收起成立。
        let concluded = await concludeFold(parkedElement, id: parkedID)
        if concluded == .hidden {
            print("PASS sls-conclude: FoldVerifier → hidden")
        } else {
            failures.append("sls-conclude: FoldVerifier → \(concluded)")
        }

        // 对照：另一扇没停车的窗口必须仍读成 visible。
        let neighbourObservation = owner.observeFoldHide(.privateOffscreen, win: neighbourElement,
                                                          pid: getpid(), id: neighbourID)
        if neighbourObservation == .visible {
            print("PASS sls-neighbour: 没停车的窗口仍读出 visible")
        } else {
            failures.append("sls-neighbour: 没停车的窗口读出 \(neighbourObservation)")
        }

        // 停回来：判据得跟着窗口服务器走回可见，不能停在 hidden。
        _ = PrivateSLSWindowMover.shared.moveWindow(id: parkedID, to: parkedOrigin)
        let restored = await wait(3) { [self] in
            owner.observeFoldHide(.privateOffscreen, win: parkedElement, pid: getpid(), id: parkedID) == .visible
        }
        if restored {
            print("PASS sls-restore: 停回来的窗口重新读出 visible")
        } else {
            failures.append("sls-restore: 停回来读不到 visible \(readings(parkedID, parkedElement, fallback: parkedSize))")
        }

        finish(nil)
    }

    /// 和 scheduleFoldVerification 一样接 FoldVerifier，只把 isCurrent 换成「这一支永远新鲜」：
    /// 这里量的是判定本身，不是再验一遍回调时效。salvage 返回 true（有后备动作可用），
    /// 于是结出来的值就是收尾时的观测值——旧判据在这条路上会结出 visible。
    private func concludeFold(_ element: AXUIElement, id: CGWindowID) async -> FoldVerifier.Observation {
        var settled: FoldVerifier.Observation?
        let verifier = FoldVerifier(
            schedule: { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) },
            isCurrent: { true },
            observation: { [self] in
                owner.observeFoldHide(.privateOffscreen, win: element, pid: getpid(), id: id)
            },
            salvage: { true },
            salvagedObservation: { [self] in
                owner.observeFoldHide(.privateOffscreen, win: element, pid: getpid(), id: id)
            },
            result: { settled = $0 })
        verifier.start()
        _ = await wait(3) { settled != nil }
        withExtendedLifetime(verifier) {}
        return settled ?? .unknown
    }

    private func makeWindow(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, title: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: x, y: y, width: width, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        return window
    }

    private func serverWindowID(for window: NSWindow) async -> CGWindowID? {
        let number = CGWindowID(window.windowNumber)
        guard number != 0 else { return nil }
        let listed = await wait(5) { cgWindowInfo(number) != nil }
        return listed ? number : nil
    }

    /// 按 CGWindowID 找那扇窗的 AX 元素：身份用 _AXUIElementGetWindow 核对，不靠标题或位置猜。
    private func axWindowElement(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return nil }
        for element in elements {
            var actual: CGWindowID = 0
            if _AXUIElementGetWindow(element, &actual) == .success, actual == id { return element }
        }
        return nil
    }

    /// 三方读数：AX 坐标、窗口服务器外框、窗口服务器的在屏标志，加判据自己看到的。
    private func readings(_ id: CGWindowID, _ element: AXUIElement, fallback: CGSize) -> String {
        let info = cgWindowInfo(id)
        let ax = axPosition(element).map { String(format: "(%.0f,%.0f)", $0.x, $0.y) } ?? "nil"
        let cg = info.flatMap { cgWindowBounds($0) }
            .map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.minX, $0.minY, $0.width, $0.height) } ?? "nil"
        let onscreen = (info?[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
        let visible = cgWindowIsVisible(id: id, fallbackSize: fallback).map(String.init) ?? "nil"
        return "ax=\(ax) cg=\(cg) cgonscreen=\(onscreen.map(String.init) ?? "nil") cgVisible=\(visible)"
    }

    private func wait(_ timeout: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return condition()
    }

    private func finish(_ error: String?) {
        parkedWindow?.close()
        neighbourWindow?.close()
        parkedWindow = nil
        neighbourWindow = nil
        if let error, !error.isEmpty {
            print("FAIL sls-offscreen-check: \(error)")
        } else if failures.isEmpty {
            print("PASS sls-offscreen-check")
        } else {
            print("FAIL sls-offscreen-check: \(failures.joined(separator: " | "))")
        }
        WindowShadeLogger.shared.flushAndClose()
        fflush(stdout)
        exit(error == nil && failures.isEmpty ? 0 : 1)
    }
}
