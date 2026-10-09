import Cocoa

/// 把输入开关接到已有的纯逻辑。关着时不创建事件 tap，也不创建 HID 监听。
@MainActor
final class WS2InputController {
    let scrollTap = ScrollTap()
    let middleTap = MiddleTitlebarTap()
    private var remote = RemoteInputRouter()
    private var routerClock = WS2.Instant(nanoseconds: 1)
    private(set) var preferences = WS2InputPreferences.Value.off
    private(set) var scrollDecision = ScrollInstallPolicy.Decision.hold(.off)
    /// iPhone 上的遥控器：遥控模式开着且宣告、监听都就绪时才是 true。
    private(set) var remoteListening = false
    /// 遥控模式第一次打开时才建；关着时不读钥匙串、不宣告、不监听。
    private var remoteHost: WS2RemoteHost?
    private var remotePresenter: WS2RemoteNotchPresenter?
    private var remoteLock: WS2RemoteLockObserver?
    private(set) var middleListening = false
    private(set) var hooksPaused = false

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
        scrollTap.apply(installing: InputFeatureGate.scrollMayInstall(decisionInstalls: decision == .install, paused: hooksPaused), mask: hooksPaused ? 0 : mask)
        scrollTap.setWatchingForeground(decision == .install && !hooksPaused)
        let middleOn = InputFeatureGate.middleDragMayInstall(switchOn: prefs.middleFold, paused: hooksPaused)
            && !middleTap.systemStopped
        middleListening = middleOn
        middleTap.apply(installing: middleOn)
        // Siri 遥控器：没有核对过的静音映射，仍不创建它的监听。
        _ = remote.setEnabled(false, at: tick())
        let conductor = WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: store)
        remoteListening = applyRemote(on: prefs.remoteMode, conductor: conductor)
        // 手柄：有哪一台打开了才监听，全关就停（R09）。
        WS2GamepadDesktopControl.shared.applyPreferences()
    }

    /// 遥控模式是总开关，指挥模式跟着它。
    private func applyRemote(on: Bool, conductor: Bool) -> Bool {
        if on, remoteHost == nil {
            let host = WS2RemoteHost.makeForApp()
            let presenter = WS2RemoteNotchPresenter()
            host.presenter = presenter
            host.onChange = { [weak self] in
                guard let self else { return }
                self.remoteListening = self.remoteHost?.isListening == true
                (NSApp.delegate as? AppDelegate)?.refreshPreferencesWindowIfOpen()
            }
            remoteHost = host; remotePresenter = presenter
        }
        guard let host = remoteHost else { return false }
        if on, remoteLock == nil { remoteLock = WS2RemoteLockObserver(host: host) }
        host.setEnabled(remote: on, conductor: conductor)
        if !on { remoteLock?.invalidate(); remoteLock = nil }
        return host.isListening
    }

    /// 设置页用：iPhone 上的遥控器现在的样子。
    var remoteHostForSettings: WS2RemoteHost? { remoteHost }

    func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        scrollTap.setWatchingForeground(false)
        scrollTap.apply(installing: false, mask: 0)
        middleListening = false
        middleTap.apply(installing: false)
        remoteListening = false
        _ = remote.setEnabled(false, at: tick())
        remoteHost?.setEnabled(remote: false, conductor: false)
        remoteLock?.invalidate(); remoteLock = nil
    }

    /// 静音「先停一下」。偏好还在，钩子先拆掉，再次 apply 也不会装上。
    func pauseHooks() {
        dispatchPrecondition(condition: .onQueue(.main))
        hooksPaused = true
        apply()
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
