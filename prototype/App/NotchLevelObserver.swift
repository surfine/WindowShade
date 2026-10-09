// 输出音量、屏幕亮度 → 同一颗岛上的提示。只在真的按了音量、亮度键时开口（判定在 Core/NotchLevelGate.swift）。
// 不拦系统键：媒体键只旁听（NSEvent 全局监视器，拿不到也改不了别人的事件），系统自己的提示照常。
// 读取点已登记：音量读 Core Audio 公开标量；亮度经 DisplayServices 读当前屏，只在按了亮度键后的一小会儿去读
//（仓库里其它硬件形状读取同一类私有桥，失败就静默）。监视器装不上时退回原来的做法：数值一变就开口。
//
// 拦键（《音量与亮度》稿工作包 LV2）：允许了辅助功能、且这个 macOS 版本核对过（NotchLevelControl 的版本表，
// 或 defaults 开关 Notch.levelSuppression.trustThisOS），才换成主动的 CGEvent 监听：掩码只有系统按键这一类
// （NX_SYSDEFINED，子类型 8），打字的键收不到；先挂 HID 层，挂不上退会话层，排在最前，能吞键。
// 回调里只解析、查缓存（锁屏、对方 App、能不能调都事先缓存好，靠通知更新，不轮询）；要拦的键派给
// NotchLevelControl 写值，不拦的照旧走下面的旁听画法。被系统暂停（tapDisabledBy…）立刻重开；辅助功能被撤销就拆掉，
// 回到只旁听。版本没核对过时什么都不换：和以前一样只旁听，系统的提示照出。不向任何系统进程发信号。
//
// 全屏（LV4）：老门闸不再因为“这块屏是全屏桌面”一概不出声；全屏的判定走 NotchLevelScreen / NotchLevelSuppression：
// 全屏而且面板在这张桌面上确认过看得见才出两耳、才可能拦（两耳出不出、看得见不看得见由 Notch.presentLevel 核对）。
// 调度中心、锁屏仍然不出声。设置里“音量和亮度”关了：不出两耳、也不拦。

import AudioToolbox
import Cocoa
import CoreAudio
import Darwin

@MainActor
final class NotchLevelObserver {
    var onVolume: ((Double) -> Void)?
    var onBrightness: ((Double) -> Void)?
    /// 带上静音、声音从哪出、到头没有的完整一下（刘海的 presentLevel(muted:output:edge:)）。接上之后优先走它，
    /// 上面两个只是没接它时的退路。
    var onPresent: ((NotchLevelKind, _ value: Double, _ muted: Bool, _ output: NotchLevelEars.Output,
                     _ edge: NotchLevelStep.Edge?) -> Void)?
    /// 拦下的键松开了（按住时顶在头上的条要弹回）。
    var onKeyReleased: (() -> Void)?
    /// 某块屏的面板在它当前的全屏桌面上有没有确认过看得见（由刘海控制器接上；没接按看不见）。
    var panelVisibility: ((CGDirectDisplayID) -> NotchLevelSuppression.FullScreen)?
    /// 由刘海控制器接上；没接（或读不到）时不按全屏、调度中心拦。
    var spaceGate: NotchSpaceGate?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: Float = -1
    private var lastBrightness: Float = -1
    private var started = false
    private var brightnessTimer: Timer?
    private var muteRead: DispatchWorkItem?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var gate = NotchLevelGate(keysAvailable: false)
    /// 默认输出设备是什么（换设备时读一次）。
    private var output: NotchLevelEars.Output = .speaker
    /// 设置里“音量和亮度”开着没有（默认开）；通知更新，回调里只读这个值。
    private var settingEnabled = true
    private var settingToken: NSObjectProtocol?
    private var accessibilityToken: NSObjectProtocol?
    private var accessibilityRecheck: DispatchWorkItem?
    private let getBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?

    // 拦键（LV2）：只在 tap 装上时用到。
    private lazy var systemPort = NotchLevelSystemPort()
    private lazy var control = NotchLevelControl(port: systemPort)
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var versionVerified = false
    /// 锁没锁（读不准当锁着）、对方的提示在不在：靠通知更新，回调里只读这两个值。
    private var cachedLocked = true
    private var cachedForeignHUD = false
    private var tapObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var lockRecheck: DispatchWorkItem?
    /// 键盘灯的画面（LV3 接上）。没接时键盘灯键一律交给系统：拦了没处画就等于按了没反应。
    var onKeyboardLight: ((Double) -> Void)?

    private lazy var onDefaultDevice: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated {
            guard let self else { return }
            self.detachVolume()
            self.refreshDevice()
            self.attachVolume()
            self.pollVolume(initial: true)
            if self.tap != nil { self.control.refreshCapabilities() }
        }
    }

    private lazy var onVolumeChange: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.pollVolume(initial: false) }
    }

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(
                symbol, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
        } else {
            getBrightness = nil
        }
    }

    func start() {
        guard !started else { return }
        started = true
        settingEnabled = NotchLevelSetting.isEnabled()
        settingToken = NotificationCenter.default.addObserver(
            forName: NotchLevelSetting.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingEnabled = NotchLevelSetting.isEnabled() }
        }
        // 辅助功能被允许或撤销时系统会发这条；只在它来的时候重看，不轮询。
        accessibilityToken = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityMayHaveChanged() }
        }
        refreshDevice()
        var defaultAddress = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, DispatchQueue.main, onDefaultDevice)
        attachVolume()
        pollVolume(initial: true)
        pollBrightness(initial: true)
        // 媒体键：别的 App 在前台时走全局监视器，自己的窗口在前台时走本地监视器（本地的原样放行）。
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            MainActor.assumeIsolated { self?.monitorKey(event) }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            MainActor.assumeIsolated { self?.monitorKey(event) }
            return event
        }
        gate.keysAvailable = globalKeys != nil
        if !gate.keysAvailable {
            // 听不到按键：照旧每 0.2 秒看一眼亮度，变了就说。
            startBrightnessPolling(until: nil)
            wlog("notch level: media-key monitor unavailable; falling back to value changes")
        }
        installTapIfAllowed()
    }

    func stop() {
        guard started else { return }
        detachVolume()
        var defaultAddress = Self.defaultDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, DispatchQueue.main, onDefaultDevice)
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        globalKeys = nil; localKeys = nil
        removeTap()
        if let settingToken { NotificationCenter.default.removeObserver(settingToken) }
        if let accessibilityToken { DistributedNotificationCenter.default().removeObserver(accessibilityToken) }
        settingToken = nil; accessibilityToken = nil
        accessibilityRecheck?.cancel(); accessibilityRecheck = nil
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        muteRead?.cancel(); muteRead = nil
        started = false
    }

    // MARK: 按键

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 旁听到的键。主动监听装着时由它统一处理（不拦的也从它那里走旁听画法），这里不重复。
    private func monitorKey(_ event: NSEvent) {
        guard tap == nil,
              let key = NotchLevelKey.parse(subtype: Int(event.subtype.rawValue), data1: event.data1) else { return }
        handleKey(key)
    }

    private func handleKey(_ key: NotchLevelKey) {
        let decision = gate.keyPressed(key, at: now, context: context())
        switch key.kind {
        case .volume:
            if key == .mute {
                // 静音键：等系统切完再读，静音了就显示 0。
                muteRead?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, decision == .show, let value = Self.readVolume(self.device) else { return }
                        self.lastVolume = value
                        let muted = Self.readMuted(self.device) == true
                        self.emit(.volume, value: muted ? 0 : Double(value), muted: muted)
                    }
                }
                muteRead = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                return
            }
            // 到头了数值不会变：按下就用现在的值开口；真变了，监听会再更新一次。
            guard decision == .show, let value = Self.readVolume(device) else { return }
            lastVolume = value
            let muted = Self.readMuted(device) == true
            emit(.volume, value: muted ? 0 : Double(value), muted: muted)
        case .brightness:
            guard decision == .show, let value = readBrightness() else { return }
            lastBrightness = value
            emit(.brightness, value: Double(value))
            // 系统调亮度有一点延迟：按键后的一小会儿里每 50 毫秒读一次，平时不读。
            startBrightnessPolling(until: now + NotchLevelGate.window)
        case .keyboardLight:
            return  // NotchLevelKey.parse 不会给出键盘灯键；键盘灯的接入在后面的包里。
        }
    }

    /// 锁着（确定锁着才算；读不准不拦）、调度中心开着时不开口。全屏不在这里挡（NotchLevelScreen.gateContext）：
    /// 全屏里出不出两耳，由 Notch.presentLevel 核对面板在这张桌面上是不是真的看得见。
    /// 调度中心的判断归 NotchSpaceGate（读不到当没有）。
    private func context() -> NotchLevelGate.Context {
        NotchLevelScreen.gateContext(
            locked: EffectSecurityBoundary.lockState == .locked,
            missionControl: spaceGate?.missionControlFact() == .yes)
    }

    /// 发给刘海的一下。设置里关了就不出声；没接 onPresent 时退回只带数值的老出口。
    private func emit(_ kind: NotchLevelKind, value: Double, muted: Bool = false, edge: NotchLevelStep.Edge? = nil) {
        guard settingEnabled else { return }
        if let onPresent {
            onPresent(kind, value, muted, output, edge)
            return
        }
        switch kind {
        case .volume: onVolume?(value)
        case .brightness: onBrightness?(value)
        case .keyboardLight: onKeyboardLight?(value)
        }
    }

    private static func bool(_ fact: NotchSpaceFact) -> Bool? {
        switch fact {
        case .yes: return true
        case .no: return false
        case .unknown: return nil
        }
    }

    private func pointerDisplay() -> CGDirectDisplayID? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: 拦键（LV2）

    /// 这个 macOS 版本核对过没有（版本表，或真机验证用的 defaults 开关）。设置那一行的副标题也用它。
    static func currentVersionVerified() -> Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let trust = UserDefaults.standard.bool(forKey: NotchLevelControl.trustThisOSKey)
        return NotchLevelControl.versionVerified(
            NotchLevelOSVersion(major: os.majorVersion, minor: os.minorVersion), trustThisOS: trust)
    }

    /// 辅助功能的授权变了（系统的通知）：撤销了立刻拆监听、退回只旁听；允许了就装上，不用重开。
    /// 系统状态有时慢半拍，过半秒再对一次（一次性，不循环）。
    func accessibilityMayHaveChanged() {
        reconcileAccessibility()
        accessibilityRecheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.accessibilityRecheck = nil
                self?.reconcileAccessibility()
            }
        }
        accessibilityRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reconcileAccessibility() {
        guard started else { return }
        if tap != nil, !AXIsProcessTrusted() {
            removeTap()
            wlog("notch level: accessibility revoked; listening only")
        } else if tap == nil {
            installTapIfAllowed()
        }
        NotificationCenter.default.post(name: NotchLevelSetting.didChange, object: nil)
    }

    /// 能拦时换成主动监听。辅助功能没允许、版本没核对过就什么都不换（只旁听）。
    /// 允许辅助功能之后可以再调一次（设置那一行的“允许…”那一路，LV5 接）。
    func installTapIfAllowed() {
        guard started, tap == nil else { return }
        versionVerified = Self.currentVersionVerified()
        guard versionVerified, NotchLevelControl.installsTap(accessibilityTrusted: AXIsProcessTrusted(),
                                            versionVerified: versionVerified) else { return }
        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.systemDefined.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        let hid = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: notchLevelTapCallback, userInfo: info)
        guard let port = hid ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                                  eventsOfInterest: mask, callback: notchLevelTapCallback, userInfo: info),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else {
            wlog("notch level: key tap unavailable; listening only")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        systemPort.wantsKeyboardLight = onKeyboardLight != nil
        control.onLevel = { [weak self] kind, reading, result in self?.wrote(kind, reading, edge: result.edge) }
        observeTapFacts()
        refreshTapFacts()
        wlog("notch level: key tap installed (\(hid == nil ? "session" : "hid"))")
    }

    private func removeTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
        for (center, token) in tapObservers { center.removeObserver(token) }
        tapObservers.removeAll()
        lockRecheck?.cancel(); lockRecheck = nil
    }

    /// 系统暂停了监听（回调超时、用户输入）：立刻重开。辅助功能被撤销了就拆掉，回到只旁听。
    fileprivate func tapWasDisabled() {
        guard let tap else { return }
        guard AXIsProcessTrusted() else {
            removeTap()
            wlog("notch level: accessibility revoked; listening only")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// 监听回调：返回 true 吞掉这一下。只解析、查缓存；写值由 NotchLevelControl 排到稍后。
    fileprivate func tapKey(data1: Int, flags: UInt64, marked: Bool) -> Bool {
        guard let event = NotchLevelKeyEvent.parse(subtype: 8, data1: data1,
                                                   modifierFlags: UInt(truncatingIfNeeded: flags)) else { return false }
        let routed = control.route(event, raw: NotchLevelRawKey(data1: data1, flags: flags), marked: marked,
                                   input: tapInput(for: event.key))
        guard routed.verdict == .pass else {
            // 吞掉的键松开了：顶在头上的条弹回。回调里只排一下，画在稍后。
            if !event.isDown {
                DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.onKeyReleased?() } }
            }
            return true
        }
        // 不拦的照旧走旁听画法（补发给系统的那一下也是：这时两个提示都在）。读数值放到回调之后。
        if event.isDown, let key = NotchLevelKey.parse(subtype: 8, data1: data1) {
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.handleKey(key) } }
        }
        return false
    }

    /// 判定表的输入，全部来自缓存或进程内的状态；能不能调由 NotchLevelControl 按它的缓存补。
    private func tapInput(for key: NotchLevelKey) -> NotchLevelSuppression.Input {
        var input = NotchLevelSuppression.Input()
        input.listener = .active
        input.versionVerified = versionVerified
        input.foreignHUDRunning = cachedForeignHUD
        input.locked = cachedLocked
        input.settingEnabled = settingEnabled
        // 全屏桌面、调度中心：走判定表。全屏而且面板在这张桌面上确认过看得见才可能拦；查不到按看不见（不拦）。
        if let spaceGate, let display = pointerDisplay() {
            let fullScreen = Self.bool(spaceGate.fullScreenFact(on: display))
            NotchLevelScreen.apply(
                to: &input, isFullScreen: fullScreen, missionControl: Self.bool(spaceGate.missionControlFact()),
                panelVisibility: fullScreen == true ? (panelVisibility?(display) ?? .notVisible) : .no)
        } else {
            NotchLevelScreen.apply(to: &input, isFullScreen: nil, missionControl: nil, panelVisibility: .notVisible)
        }
        let notch = (NSApp.delegate as? AppDelegate)?.notch
        let panel = notch?.notchPanelForProbe
        input.authorizationRelease = notch?.authentication.isPresenting == true || panel?.isAuthenticating == true
        input.gestureInFlight = panel.map { $0.dropState != .none } ?? false
        if key.kind == .keyboardLight, onKeyboardLight == nil { input.deviceAdjustable = false }
        return input
    }

    /// 写对了：照读回来的值画（静音带斜线喇叭，到头再按带上哪一头），并记成“上一次的值”，免得音量监听再报一次。
    private func wrote(_ kind: NotchLevelKind, _ reading: NotchLevelReading, edge: NotchLevelStep.Edge?) {
        switch kind {
        case .volume:
            lastVolume = Float(reading.value)
            emit(.volume, value: reading.muted ? 0 : reading.value, muted: reading.muted, edge: edge)
        case .brightness:
            lastBrightness = Float(reading.value)
            emit(.brightness, value: reading.value, edge: edge)
        case .keyboardLight:
            emit(.keyboardLight, value: reading.value, edge: edge)
        }
    }

    /// 锁屏、屏保、对方 App 起停、换屏：只在这些通知到来时重读，不轮询。
    private func observeTapFacts() {
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            tapObservers.append((distributed, distributed.addObserver(
                forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cachedLocked = true }
            }))
        }
        for name in ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"] {
            tapObservers.append((distributed, distributed.addObserver(
                forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recheckLock() }
            }))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tapObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cachedForeignHUD = NotchPanel.foreignHUDIsRunning() }
            }))
        }
        tapObservers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.control.refreshCapabilities() }
        }))
    }

    private func refreshTapFacts() {
        cachedLocked = EffectSecurityBoundary.lockState != .unlocked
        cachedForeignHUD = NotchPanel.foreignHUDIsRunning()
        control.refreshCapabilities()
    }

    /// 解锁通知到了再读一次；系统状态还没跟上就过半秒补读一次（一次性，不循环）。
    private func recheckLock() {
        lockRecheck?.cancel(); lockRecheck = nil
        cachedLocked = EffectSecurityBoundary.lockState != .unlocked
        guard cachedLocked else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lockRecheck = nil
                self.cachedLocked = EffectSecurityBoundary.lockState != .unlocked
            }
        }
        lockRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: 数值

    private func refreshDevice() {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultDeviceAddress
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return }
        device = deviceID
        output = NotchLevelOutputReader.read(device: deviceID)
    }

    private func attachVolume() {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        var address = Self.volumeAddress
        AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, onVolumeChange)
    }

    private func detachVolume() {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        var address = Self.volumeAddress
        AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, onVolumeChange)
    }

    private func pollVolume(initial: Bool) {
        guard let value = Self.readVolume(device) else { return }
        if initial || lastVolume < 0 {
            lastVolume = value
            return
        }
        guard abs(value - lastVolume) >= 0.005 else { return }
        lastVolume = value
        guard gate.valueChanged(.volume, at: now, context: context()) == .show else { return }
        emit(.volume, value: Double(value))
    }

    /// until 为 nil：一直读（听不到按键时的老做法）；否则读到那个时刻就停。
    private func startBrightnessPolling(until deadline: TimeInterval?) {
        brightnessTimer?.invalidate()
        let interval = deadline == nil ? 0.2 : 0.05
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.brightnessTick(deadline: deadline) }
        }
        brightnessTimer?.tolerance = interval / 4
        if let brightnessTimer { RunLoop.main.add(brightnessTimer, forMode: .common) }
    }

    private func brightnessTick(deadline: TimeInterval?) {
        if let deadline, now > deadline {
            brightnessTimer?.invalidate()
            brightnessTimer = nil
            return
        }
        pollBrightness(initial: false)
    }

    private func pollBrightness(initial: Bool) {
        guard let value = readBrightness() else { return }
        if initial || lastBrightness < 0 {
            lastBrightness = value
            return
        }
        guard abs(value - lastBrightness) >= 0.008 else { return }
        lastBrightness = value
        guard gate.valueChanged(.brightness, at: now, context: context()) == .show else { return }
        emit(.brightness, value: Double(value))
    }

    private func readBrightness() -> Float? {
        guard let getBrightness else { return nil }
        // 指针所在那块可调亮度的屏；没有就内建屏。
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == CGMainDisplayID() }
            ?? NSScreen.main
        guard let screen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }
        var value: Float = 0
        guard getBrightness(id, &value) == 0 else { return nil }
        return min(1, max(0, value))
    }

    private static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func readVolume(_ device: AudioObjectID) -> Float? {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = volumeAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return min(1, max(0, value))
    }

    /// 输出设备静音了没有；设备没有静音开关就是 nil。
    private static func readMuted(_ device: AudioObjectID) -> Bool? {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}

/// 主动监听的回调（C 函数，挂在主线程的 run loop 上，所以总在主线程被调）。
/// 只取出几个数交给主线程上的观察者；暂停通知立刻重开。
private func notchLevelTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, info: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let observer = Unmanaged<NotchLevelObserver>.fromOpaque(info).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { observer.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
          let parsed = NSEvent(cgEvent: event), parsed.subtype.rawValue == 8
    else { return Unmanaged.passUnretained(event) }
    let data1 = parsed.data1
    let flags = UInt64(parsed.modifierFlags.rawValue)
    let marked = event.getIntegerValueField(.eventSourceUserData) == NotchLevelControl.reissueMark
    let swallow = MainActor.assumeIsolated { observer.tapKey(data1: data1, flags: flags, marked: marked) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
