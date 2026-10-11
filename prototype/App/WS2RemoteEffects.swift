// 遥控器第 0、1 层的效果执行（工作包 M09）。
//
// RemoteMode / ConductorSession 给出的 Effect 先过 Core/RemoteLayerHost（纯状态机，决定“这一下算什么”），
// 这里把它给出的动作接到刘海那一排（M07 的 NotchController.perform，焦点动作不另写一套）、启动台、系统音量、
// 提示音开关和媒体键上。
//
// - 不新开监听、不轮询：本地键盘和指针用 CGEventSource 读“多久没动过”，只在遥控器有输入或一次性定时到点时读一次；
//   指针在不在刘海里、有没有更高的层占着刘海，同样在那时拉一次。
// - 唯一的定时是第 1 层的 10 秒收回：一次性、带容差，离开第 1 层就停。
// - 放行等更高的层来了，这一排被它们的挂起机制收走，让出后原样回来：这里只暂停计时、不重发展开。
import Foundation
#if !WS2_REMOTE_HOST_TESTING
import AudioToolbox
import Cocoa
import CoreAudio
#endif

// MARK: - 可替换的边界

/// 刘海、启动台、系统音量、提示音开关、媒体键、定时和“本地的人在不在”。生产是 WS2RemoteSystemPort；单测用替身。
@MainActor protocol WS2RemoteEffectPort: AnyObject {
    /// 当前系统输出音量（0…1）；读不到返回 nil。iPhone 遥控器的 _mcc 5 用。
    func mediaVolume() -> Double?
    /// 写系统输出音量（0…1 夹住）。iPhone 遥控器的 _mcc 6 用。
    func setMediaVolume(_ value: Double)
    /// 那一排现在展开着。
    var rowVisible: Bool { get }
    /// 遥控焦点现在落在那一排上。
    var focusActive: Bool { get }
    var pointerInNotch: Bool { get }
    /// 放行、配对卡等比“你打开的”更高的层现在占着刘海。
    var higherLayerActive: Bool { get }
    /// 本地键盘和指针（移动、点按、滚动）离现在最近的一次是多少秒以前。
    var secondsSinceLocalInput: Double { get }
    /// 一次性定时：`seconds` 秒后调 `onWake`；nil 取消。重复设置只留最后一个。
    var onWake: (() -> Void)? { get set }
    func armWake(after seconds: Double?)
    /// NotchController.perform：键盘、遥控器、手柄共用的那一排出口。返回有没有处理。
    @discardableResult func perform(_ action: WS2.Action) -> Bool
    func openLaunchpad()
    func setEar(wand: Bool)
    func adjustVolume(step: Int)
    /// 切换提示音开关，返回切换后是否开着。
    func togglePromptSound() -> Bool
    func postPlayPause()
    /// 指挥提示音（R11）。开关关着的判断在播放器里；默认什么都不做。
    func play(cue: ConductorSoundCue)
    /// 焦点一步回到那一排最前面一格，读屏只念一次。返回焦点有没有动。
    func focusFirst() -> Bool
    /// 遥控器连上时开始接收“本地的人动了 / 指针进出刘海”的推送，断开时（nil）停。
    func watchLocal(input: (@MainActor () -> Void)?, pointer: (@MainActor (Bool) -> Void)?)
}

extension WS2RemoteEffectPort {
    func play(cue: ConductorSoundCue) {}
    /// 没有一步到位的出口时，退回连着往左挪（那一排最多 8 格）。
    func focusFirst() -> Bool {
        for _ in 0..<8 { perform(.focusLeft) }
        return true
    }
    func watchLocal(input: (@MainActor () -> Void)?, pointer: (@MainActor (Bool) -> Void)?) {}
}

extension WS2RemoteEffectPort {
    /// 默认：读不到（测试替身与无音频栈的构建）。
    func mediaVolume() -> Double? { nil }
    /// 默认：什么都不做。
    func setMediaVolume(_ value: Double) {}
}

// MARK: - 执行

@MainActor final class WS2RemoteEffects {
    /// 宿主接上的回调：换层、会话的进出、说话、记类别日志。
    struct Hooks {
        var setRemoteLayer: (RemoteMode.Layer) -> Void = { _ in }
        var setFocusOnSession: (Bool) -> Void = { _ in }
        var enterSession: (_ listen: Bool) -> Void = { _ in }
        var leaveSession: () -> Void = {}
        var foldSession: () -> Void = {}
        var announce: (_ text: String, _ symbol: String?) -> Void = { _, _ in }
        var record: (String) -> Void = { _ in }
    }

    enum Copy {
        static let promptSoundOn = "提示音已开"
        static let promptSoundOff = "提示音已关"
    }

    private(set) var layers = RemoteLayerHost()
    var hooks = Hooks()
    private let port: any WS2RemoteEffectPort
    private let clock: any WS2Clock
    private var lastSync: WS2.Instant?
    private var queue: [RemoteLayerHost.Action] = []
    private var draining = false
    /// 这一笔已经敲过几拍（ConductorSoundCue.cues 用）。
    private var beatsSounded = 0

    init(port: any WS2RemoteEffectPort, clock: any WS2Clock) {
        self.port = port; self.clock = clock
        port.onWake = { [weak self] in self?.wake() }
    }

    private var now: WS2.Instant { clock.now() }

    // MARK: 入口（宿主调）

    func connected(sessionsAllowed: Bool = false) {
        let at = now
        layers = RemoteLayerHost()
        lastSync = at
        run(layers.connect(sessionsAllowed: sessionsAllowed, at: at))
        // “Mac 前的人优先”：本地输入和指针进出刘海一发生就推过来，不用等遥控器下一次输入。
        port.watchLocal(input: { [weak self] in self?.localInputNow() },
                        pointer: { [weak self] inside in self?.pointerNow(inside) })
    }

    /// 本地键盘或指针刚动过。遥控模式没连着（状态机没开）什么都不做。
    func localInputNow() {
        guard layers.enabled else { return }
        run(layers.localInput(age: 0, at: now))
    }

    /// 指针进出刘海。
    func pointerNow(_ inside: Bool) {
        guard layers.enabled else { return }
        run(layers.pointer(inside: inside, at: now))
    }

    /// 指挥模式开关变了（宿主的 setEnabled）。
    func setSessionsAllowed(_ value: Bool) {
        run(layers.setSessionsAllowed(value, at: now))
    }

    func disconnected() {
        run(layers.disconnect(at: now))
        lastSync = nil
        port.watchLocal(input: nil, pointer: nil)
        port.armWake(after: nil)
    }

    func receive(remote effects: [RemoteMode.Effect]) {
        guard !effects.isEmpty else { return }
        let at = now
        var actions = pull(at)
        actions += layers.remote(effects, at: at)
        run(actions)
    }

    func receive(conductor effects: [ConductorSession.Effect]) {
        guard !effects.isEmpty else { return }
        for cue in ConductorSoundCue.cues(for: effects, lastBeats: &beatsSounded) { port.play(cue: cue) }
        let at = now
        var actions = pull(at)
        actions += layers.conductor(effects, at: at)
        run(actions)
    }

    /// 焦点换到会话格或窗口格（那一排里有会话格以后由刘海告知）。
    func focusChanged(_ kind: RemoteLayerHost.Focus) {
        run(layers.focusChanged(kind, at: now))
    }

    private func wake() {
        let at = now
        var actions = pull(at)
        actions += layers.tick(at: at)
        run(actions)
    }

    // MARK: 拉一次现状

    /// 遥控器有输入或定时到点时问一次：更高的层、指针、本地键盘指针、那一排还在不在。
    private func pull(_ at: WS2.Instant) -> [RemoteLayerHost.Action] {
        guard layers.enabled else { return [] }
        var out: [RemoteLayerHost.Action] = []
        layers.higherLayer(active: port.higherLayerActive, at: at)
        out += layers.pointer(inside: port.pointerInNotch, at: at)
        let idle = port.secondsSinceLocalInput
        let since = lastSync.map { Double(at.nanoseconds &- min($0.nanoseconds, at.nanoseconds)) / 1_000_000_000 } ?? 0
        // 上次问过之后本地动过：记下“多久以前”，由状态机判断让不让。
        if idle.isFinite, idle >= 0, idle <= since + 0.05 {
            out += layers.localInput(age: UInt64(idle * 1_000_000_000), at: at)
        }
        lastSync = at
        if layers.layer == .row, !layers.rowHidden, !layers.suspended, !port.rowVisible {
            out += layers.rowEnded(at: at)
        }
        return out
    }

    // MARK: 执行动作

    private func run(_ actions: [RemoteLayerHost.Action]) {
        queue += actions
        guard !draining else { return }
        draining = true
        while !queue.isEmpty {
            let action = queue.removeFirst()
            hooks.record("layer \(Self.label(action))")
            execute(action)
        }
        draining = false
        rearm()
    }

    private func execute(_ action: RemoteLayerHost.Action) {
        switch action {
        case .openRow:
            if !port.focusActive, !port.perform(.notchShelf) {
                // 一格都没有，或刘海没开：那一排没出来，不算第 1 层。
                queue += layers.rowEnded(at: now)
            }
        case .focusFirst:
            guard ensureFocus() else { return }
            _ = port.focusFirst()
        case .moveFocus(let action):
            guard ensureFocus() else { return }
            port.perform(action)
        case .activateWindow:
            guard ensureFocus() else { return }
            port.perform(.activateFocused)
        case .closeRow, .hideFocus:
            // 只收起，不放回任何窗口。那一排是指针展开的（没有遥控焦点）就不动它。
            if port.focusActive { port.perform(.back) }
        case .enterSession(let listen):
            hooks.enterSession(listen)
        case .leaveSession:
            hooks.leaveSession()
        case .foldSession:
            hooks.foldSession()
        case .setEar(let ear):
            port.setEar(wand: ear == .wand)
        case .setRemoteLayer(let layer):
            hooks.setRemoteLayer(layer)
        case .setFocusOnSession(let on):
            hooks.setFocusOnSession(on)
        case .openLaunchpad:
            port.openLaunchpad()
        case .adjustVolume(let step):
            port.adjustVolume(step: step)
        case .togglePromptSound:
            let on = port.togglePromptSound()
            hooks.announce(on ? Copy.promptSoundOn : Copy.promptSoundOff, on ? "bell" : "bell.slash")
        case .mediaPlayPause:
            port.postPlayPause()
        }
    }

    /// 焦点不在那一排上（被挂起又回来、刘海刚收过）就接上，那一排已经展开着就不重播展开。
    private func ensureFocus() -> Bool {
        if port.focusActive { return true }
        return port.perform(.notchShelf) && port.focusActive
    }

    private func rearm() {
        guard let wake = layers.nextWake else { port.armWake(after: nil); return }
        let nanos = wake.nanoseconds &- min(wake.nanoseconds, now.nanoseconds)
        port.armWake(after: max(0.05, Double(nanos) / 1_000_000_000))
    }

    /// iPhone 遥控器的音量问答（_mcc 5/6）：走端口；替身拿到默认实现。
    func mediaVolume() -> Double? { port.mediaVolume() }
    func setMediaVolume(_ value: Double) { port.setMediaVolume(value) }

    /// 日志只记动作类别，不带参数。
    static func label(_ action: RemoteLayerHost.Action) -> String {
        String(String(describing: action).prefix { $0 != "(" })
    }
}

// MARK: - App 里的端口

#if !WS2_REMOTE_HOST_TESTING
@MainActor final class WS2RemoteSystemPort: WS2RemoteEffectPort {
    var onWake: (() -> Void)?
    private var wake: Timer?
    private var notch: NotchController? { (NSApp.delegate as? AppDelegate)?.notch }
    private var panel: NotchPanel? { notch?.notchPanelForProbe }

    var rowVisible: Bool { notch?.isExpanded ?? false }
    var focusActive: Bool { panel?.isFocusActive ?? false }
    var pointerInNotch: Bool { panel.map { $0.islandContains(NSEvent.mouseLocation) } ?? false }

    var higherLayerActive: Bool {
        guard let notch else { return false }
        if notch.authentication.isPresenting { return true }
        guard let display = panel?.displayID, let owner = notch.leases.owner(of: display) else { return false }
        return owner.layer < .opened
    }

    var secondsSinceLocalInput: Double {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
    }

    func armWake(after seconds: Double?) {
        wake?.invalidate(); wake = nil
        guard let seconds else { return }
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake = nil; self?.onWake?() }
        }
        timer.tolerance = max(0.1, seconds * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        wake = timer
    }

    @discardableResult func perform(_ action: WS2.Action) -> Bool { notch?.perform(action) ?? false }

    func focusFirst() -> Bool { notch?.focusFirst() ?? false }

    func watchLocal(input: (@MainActor () -> Void)?, pointer: (@MainActor (Bool) -> Void)?) {
        GlobalInputFilter.onLocalInput = input
        GlobalInputFilter.onPointerInNotch = pointer
    }

    func openLaunchpad() {
        guard let app = NSApp.delegate as? AppDelegate, !app.launchpad.isShowing else { return }
        app.launchpad.show()
    }

    func setEar(wand: Bool) {
        notch?.activities.ws2PublishRemote(connected: true, symbol: wand ? "wand.and.rays" : "appletvremote.gen4")
    }

    private lazy var conductorSound = ConductorSoundPlayer(
        isEnabled: { WS2ConductorSettings.flag(WS2ConductorSettings.soundKey, in: UserDefaults.standard) },
        output: ConductorAudioEngineOutput())

    func play(cue: ConductorSoundCue) { conductorSound.play(cue) }

    func togglePromptSound() -> Bool {
        let store = UserDefaults.standard
        let on = !WS2ConductorSettings.flag(WS2ConductorSettings.soundKey, in: store)
        WS2ConductorSettings.setFlag(on, WS2ConductorSettings.soundKey, in: store)
        return on
    }

    /// 播放 / 暂停：系统媒体键，交给正在播放的那个 App（和画中画同一条发键路径）。
    func postPlayPause() {
        let key = 16 // NX_KEYTYPE_PLAY
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// 系统输出音量的一格（和键盘上的音量键一样是 1/16）。读不到默认输出设备、或这个设备不让调就什么都不做。
    func adjustVolume(step: Int) {
        guard let level = Self.stepSystemVolume(step) else { return }
        notch?.presentLevel(.volume, value: Double(level))
    }

    private static func stepSystemVolume(_ step: Int) -> Float? {
        guard let (device, address) = volumeDevice(),
              let value = readVolume(device: device, address: address) else { return nil }
        let next = steppedVolume(from: value, step: step)
        return writeVolume(next, device: device, address: address)
    }

    func mediaVolume() -> Double? {
        guard let (device, address) = Self.volumeDevice(),
              let value = Self.readVolume(device: device, address: address) else { return nil }
        return Double(value)
    }

    func setMediaVolume(_ value: Double) {
        guard value.isFinite, let (device, address) = Self.volumeDevice() else { return }
        let clamped = Float(min(1, max(0, value)))
        guard Self.writeVolume(clamped, device: device, address: address) != nil else { return }
        notch?.presentLevel(.volume, value: Double(clamped))
    }

    private static func volumeDevice() -> (AudioObjectID, AudioObjectPropertyAddress)? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return (device, AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain))
    }

    private static func readVolume(device: AudioObjectID, address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return min(1, max(0, value))
    }

    private static func writeVolume(_ target: Float32, device: AudioObjectID, address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return nil }
        var value = min(1, max(0, target))
        guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr else { return nil }
        return value
    }

    /// 音量按 1/16 一格走：先对齐到最近的一格，再加减；不出 0…1。
    nonisolated static func steppedVolume(from value: Float32, step: Int) -> Float32 {
        let notch = (min(1, max(0, value)) * 16).rounded() + Float32(step)
        return min(1, max(0, notch / 16))
    }
}
#endif
