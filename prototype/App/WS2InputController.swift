import Cocoa

/// 把输入开关接到已有的纯逻辑。关着时不创建事件 tap，也不创建 HID 监听。
@MainActor
final class WS2InputController {
    let scrollTap = ScrollTap()
    let middleTap = MiddleTitlebarTap()
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

    func apply() {
        dispatchPrecondition(condition: .onQueue(.main))
        let inputOn = FeatureCatalog.isEnabled(.inputEnhancements)
        let store = UserDefaults.standard
        let prefs = WS2InputPreferences.load(from: store)
        preferences = inputOn ? prefs : .off
        // 输入模块关掉时滚动/中键/手柄都按“全关”处理；遥控属于另一个模块，照常读。
        let scrollPrefs = inputOn ? prefs : .off
        // 触控板方向不在这里触发钩子：分类器不允许改写触控板事件。
        let wantsScroll = scrollPrefs.smooth != nil || scrollPrefs.mouseInvert
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
            if scrollPrefs.sideButtons {
                mask |= CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
                mask |= CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            }
        }
        scrollTap.update(ScrollSession.Request(smooth: scrollPrefs.smooth, invertMouse: scrollPrefs.mouseInvert, fine: scrollPrefs.fine,
                                                sideButtons: scrollPrefs.sideButtons, foregroundExcluded: false),
                         excluded: Set(scrollPrefs.exceptions))
        scrollTap.apply(installing: InputFeatureGate.scrollMayInstall(decisionInstalls: decision == .install, paused: hooksPaused), mask: hooksPaused ? 0 : mask)
        scrollTap.setWatchingForeground(decision == .install && !hooksPaused)
        let middleOn = InputFeatureGate.middleDragMayInstall(switchOn: scrollPrefs.middleFold, paused: hooksPaused)
            && !middleTap.systemStopped
        middleListening = middleOn
        middleTap.apply(installing: middleOn)
        let conductor = WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: store)
        remoteListening = applyRemote(on: prefs.remoteMode, conductor: conductor)
        // 手柄：有哪一台打开了才监听，全关就停（R09）。
        WS2GamepadDesktopControl.shared.applyPreferences()
    }

    /// 辅助功能晚于启动才给：滚动与中键钩子若因没有权限而创建失败，这里解开并补装一次（规格 R26 后续）。
    /// 没有这种停住的钩子时什么都不做。
    func accessibilityGranted() {
        dispatchPrecondition(condition: .onQueue(.main))
        let scrollReset = scrollTap.accessibilityGranted()
        let middleReset = middleTap.accessibilityGranted()
        if scrollReset || middleReset { apply() }
    }

    /// 遥控模式是总开关，指挥模式跟着它。
    private func applyRemote(on: Bool, conductor: Bool) -> Bool {
        if on, remoteHost == nil {
            let host = WS2RemoteHost.makeForApp()
            let presenter = WS2RemoteNotchPresenter()
            host.presenter = presenter
            host.pageAction = { [weak delegate = NSApp.delegate as? AppDelegate] button in
                delegate?.ws2Runtime.remoteConductorAction(button) ?? false
            }
            host.onConductorConfig = { [weak delegate = NSApp.delegate as? AppDelegate] config in
                _ = delegate?.ws2Runtime.remoteConductorConfig(config)
            }
            host.onConductorNotch = { [weak delegate = NSApp.delegate as? AppDelegate] notch in
                delegate?.ws2Runtime.remoteConductorNotch(notch)
            }
            host.onChange = { [weak self] in
                guard let self else { return }
                self.remoteListening = self.remoteHost?.isListening == true
                (NSApp.delegate as? AppDelegate)?.refreshPreferencesWindowIfOpen()
            }
            remoteHost = host; remotePresenter = presenter
        }
        guard let host = remoteHost else { return false }
        if on, remoteLock == nil { remoteLock = WS2RemoteLockObserver(host: host) }
        let companionOn = FeatureCatalog.isEnabled(.companion)
        host.setEnabled(remote: on && companionOn, conductor: conductor && companionOn)
        if !on { remoteLock?.invalidate(); remoteLock = nil }
        return host.isListening
    }

    /// 设置页用：iPhone 上的遥控器现在的样子。
    var remoteHostForSettings: WS2RemoteHost? { remoteHost }

    /// 指挥页打开/切换会话时，把真实 Codex 目标交给遥控会话；nil 表示页面关了。
    func setRemoteConductor(_ handshake: WS2OwnedLaunchController.RemoteHandshake?) {
        remoteHost?.setConductor(handshake)
    }

    func shutdown() {
        dispatchPrecondition(condition: .onQueue(.main))
        scrollTap.setWatchingForeground(false)
        scrollTap.apply(installing: false, mask: 0)
        middleListening = false
        middleTap.apply(installing: false)
        remoteListening = false
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

    var touchAvailable: Bool {
        InputFeatureGate.touchMayInstall(qualification: nil, build: "", architecture: "", sourceDigest: "", switchOn: true)
    }
}
