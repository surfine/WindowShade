import Cocoa

/// 把输入开关接到已有的纯逻辑。关着时不创建事件 tap，也不创建 HID 监听。
final class WS2InputController {
    let scrollTap = ScrollTap()
    let middleTap = MiddleTitlebarTap()
    private var remote = RemoteInputRouter()
    private var routerClock = WS2.Instant(nanoseconds: 1)
    private(set) var preferences = WS2InputPreferences.Value.off
    private(set) var scrollDecision = ScrollInstallPolicy.Decision.hold(.off)
    /// 监听没有创建。映射文本不在仓库里，打开开关也不会变成 true。
    private(set) var remoteListening = false
    private(set) var middleListening = false

    private func tick() -> WS2.Instant {
        routerClock = routerClock.adding(1)
        return routerClock
    }

    func apply() {
        dispatchPrecondition(condition: .onQueue(.main))
        let store = UserDefaults.standard
        let prefs = WS2InputPreferences.load(from: store)
        preferences = prefs
        // 触控板方向不在这里触发钩子：分类器不允许改写触控板事件。
        let wantsScroll = prefs.smooth != nil || prefs.mouseInvert
        let yielded = wantsScroll ? ScrollYield.name(among: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) : nil
        let decision = ScrollInstallPolicy.decide(ScrollInstallPolicy.Input(
            wantsScrollChange: wantsScroll,
            yieldedTo: yielded,
            confirmedWheel: nil,
            perEventAssociationAvailable: PerEventAssociation.available(),
            systemStopped: scrollTap.systemStopped))
        scrollDecision = decision
        var mask: CGEventMask = 0
        if decision == .install {
            mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            if prefs.sideButtons {
                mask |= CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
                mask |= CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            }
        }
        scrollTap.update(ScrollSession.Request(smooth: prefs.smooth, invertMouse: prefs.mouseInvert, fine: prefs.fine,
                                                sideButtons: prefs.sideButtons, foregroundExcluded: false),
                         excluded: Set(prefs.exceptions))
        scrollTap.apply(installing: decision == .install, mask: mask)
        scrollTap.setWatchingForeground(decision == .install)
        let middleOn = InputFeatureGate.middleDragMayInstall(switchOn: prefs.middleFold)
            && !middleTap.systemStopped
        middleListening = middleOn
        middleTap.apply(installing: middleOn)
        // 没有核对过的静音映射，打开遥控模式也不创建遥控器监听。
        remoteListening = false
        _ = remote.setEnabled(false, at: tick())
    }

    func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        scrollTap.setWatchingForeground(false)
        scrollTap.apply(installing: false, mask: 0)
        middleListening = false
        middleTap.apply(installing: false)
        remoteListening = false
        _ = remote.setEnabled(false, at: tick())
    }

    func scrollStatus(prefersChange: Bool) -> String {
        if !prefersChange {
            switch scrollDecision {
            case .hold(.off): return "关着，不改滚动"
            case .hold(let block): return InputStatusCopy.scrollHold(block)
            case .install: return "关着，不改滚动"
            }
        }
        switch scrollDecision {
        case .install: return "开着"
        case .hold(let block): return InputStatusCopy.scrollHold(block)
        }
    }

    var middleAvailable: Bool { InputFeatureGate.middleDragMayInstall(switchOn: true) }
    var touchAvailable: Bool {
        InputFeatureGate.touchMayInstall(qualification: nil, build: "", architecture: "", sourceDigest: "", switchOn: true)
    }
}
