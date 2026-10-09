// 音量、亮度、键盘灯：拦下来的键由这里照系统的步长写回（《音量与亮度》稿工作包 LV2）。
//
// - 拦不拦由 Core/NotchLevelSuppression 的判定表定；这里只把“拦”落成两件事：按下和对应的松开都吞，
//   写值派到主线程稍后做（监听回调里只解析、查缓存，不碰 Core Audio）。
// - 写完读回核对；不对就把这一下带记号补发给系统（按下 + 松开一对），这一类键本次开机不再拦。
// - 能不能调先探好放进缓存（音量按设备记），回调只读缓存。
// - 版本核对表：真机连按 20 次、系统提示 0 次的 macOS 版本才列进来；现在是空的，所以默认只旁听、两个都在。
//   Aaron 真机验证时用 defaults 开关 Notch.levelSuppression.trustThisOS 强制当作已核对（默认 false）。
// - 不向 OSDUIHelper 或任何系统进程发信号，不 killall，不 launchctl；只拦键、写三种系统数值。
//
// 写入端口可替换：生产是 NotchLevelSystemPort（Core Audio、DisplayServices、CoreBrightness 的键盘灯客户端），
// 单测用替身（tests/NotchLevelControlTests.swift，编译时带 -D NOTCH_LEVEL_HOST_TESTING）。

import Foundation
#if !NOTCH_LEVEL_HOST_TESTING
import AudioToolbox
import Cocoa
import CoreAudio
import Darwin
#endif

/// 一下系统按键的原样（data1 与修饰键原位），补发时照它重建。
struct NotchLevelRawKey: Equatable, Sendable {
    var data1: Int
    var flags: UInt64
}

/// 读到的一类数值。只有音量有静音。
struct NotchLevelReading: Equatable, Sendable {
    var value: Double
    var muted: Bool = false
}

/// 这一刻能调什么。探一次放进缓存，监听回调只读这里。
struct NotchLevelCapabilities: Equatable, Sendable {
    var volume = false
    var mute = false
    var brightness = false
    var keyboardLight = false

    func allows(_ key: NotchLevelKey) -> Bool {
        switch key {
        case .volumeUp, .volumeDown: return volume
        case .mute: return mute
        case .brightnessUp, .brightnessDown: return brightness
        case .keyboardLightUp, .keyboardLightDown: return keyboardLight
        }
    }
}

/// 已核对的 macOS 版本（主、次版本号）。
struct NotchLevelOSVersion: Hashable, Sendable {
    var major: Int
    var minor: Int
}

/// 写入端：读、写、补发、反馈声。生产走系统，单测用替身。
@MainActor protocol NotchLevelWritePort: AnyObject {
    /// 现探一遍能调什么（会碰 Core Audio 与私有桥；只在启动、换设备、换屏时调）。
    func probeCapabilities() -> NotchLevelCapabilities
    func read(_ kind: NotchLevelKind) -> NotchLevelReading?
    /// 写数值；返回写这一步本身有没有报错。
    func write(_ kind: NotchLevelKind, value: Double) -> Bool
    func setMuted(_ muted: Bool) -> Bool
    /// 把原键带记号补发给系统（按下 + 松开一对）；监听认出记号放行。
    func reissue(_ raw: NotchLevelRawKey)
    /// 系统“调音量时播放反馈”开着时放一声；关着什么都不做。
    func playVolumeFeedback()
}

@MainActor
final class NotchLevelControl {
    /// 一下按键的去向：吞掉，还是原样交给系统。
    enum Verdict: Equatable, Sendable { case swallow, pass }

    /// 补发的键带的记号（CGEvent 的 eventSourceUserData）。监听见到它一律放行。
    nonisolated static let reissueMark: Int64 = 0x5753_4C56  // "WSLV"

    /// 真机按 20 次、系统提示 0 次出现的版本才加进来。现在还没有这份证据。
    nonisolated static let verifiedOSVersions: Set<NotchLevelOSVersion> = []

    /// defaults 开关：真机验证时把这台 Mac 的版本当作已核对（默认 false）。
    nonisolated static let trustThisOSKey = "Notch.levelSuppression.trustThisOS"

    nonisolated static func versionVerified(_ os: NotchLevelOSVersion, trustThisOS: Bool,
                                            table: Set<NotchLevelOSVersion> = verifiedOSVersions) -> Bool {
        trustThisOS || table.contains(os)
    }

    /// 装不装主动监听：要辅助功能，也要版本核对过。没核对的版本连监听都不换，保持现在的旁听。
    nonisolated static func installsTap(accessibilityTrusted: Bool, versionVerified: Bool) -> Bool {
        accessibilityTrusted && versionVerified
    }

    /// 读回和写进去的差多少以内算对上了。Core Audio 的音量标量会被设备量化，留半格余量。
    nonisolated static let readbackTolerance = NotchLevelStep.fine / 2

    let port: NotchLevelWritePort
    private(set) var suppression = NotchLevelSuppression()
    private(set) var capabilities = NotchLevelCapabilities()
    /// 按下被吞了的键：它的松开也吞。按下放行了就把它划掉，松开跟着最近的那次按下走。
    private var swallowedDowns: Set<NotchLevelKey> = []
    /// 写完、核对过之后：哪一类、读回来是多少、这一步的结果（到头了没有）。
    var onLevel: ((NotchLevelKind, NotchLevelReading, NotchLevelStep.Result) -> Void)?
    /// 把写值派到稍后做。生产是主队列的下一轮；单测可以改成手动执行。
    var schedule: (@escaping @MainActor () -> Void) -> Void = { work in
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }

    init(port: NotchLevelWritePort) { self.port = port }

    /// 重探能调什么。启动、默认输出设备变了、屏幕变了、写失败之后调。
    func refreshCapabilities() {
        capabilities = port.probeCapabilities()
    }

    /// 监听回调里调：只看参数和缓存，不碰系统。返回吞还是放；吞下的按下已经排好写值。
    /// input.deviceAdjustable 由这里按缓存补上（调用方不用管）；marked 是自己补发的那一下。
    func route(_ event: NotchLevelKeyEvent, raw: NotchLevelRawKey, marked: Bool,
               input: NotchLevelSuppression.Input) -> (verdict: Verdict, decision: NotchLevelSuppression.Decision?) {
        if marked { return (.pass, nil) }
        let key = event.key
        guard event.isDown else {
            guard swallowedDowns.remove(key) != nil else { return (.pass, nil) }
            if key == .volumeUp || key == .volumeDown {
                // 系统在松开时放调音量的反馈声；吞了松开就由我们放。写失败补发过的，系统自己会放，不重复。
                schedule { [weak self] in
                    guard let self, !self.suppression.failedKinds.contains(.volume) else { return }
                    self.port.playVolumeFeedback()
                }
            }
            return (.swallow, nil)
        }
        var input = input
        input.modifiers = event.modifiers
        input.deviceAdjustable = input.deviceAdjustable && capabilities.allows(key)
        let decision = suppression.decide(key.kind, input)
        guard decision.intercepts else {
            swallowedDowns.remove(key)
            return (.pass, decision)
        }
        swallowedDowns.insert(key)
        schedule { [weak self] in self?.apply(event, raw: raw) }
        return (.swallow, decision)
    }

    /// 写值、读回核对；不对就补发并记下这一类本次开机不再拦。
    func apply(_ event: NotchLevelKeyEvent, raw: NotchLevelRawKey) {
        let kind = event.key.kind
        guard let before = port.read(kind) else {
            fail(kind, raw: raw)
            return
        }
        var target = before
        var result = NotchLevelStep.Result(value: before.value, edge: nil, unmutes: false, changed: false)
        var wroteOK = true
        switch event.key {
        case .mute:
            target.muted = !before.muted
            wroteOK = port.setMuted(target.muted)
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown, .keyboardLightUp, .keyboardLightDown:
            let up = event.key == .volumeUp || event.key == .brightnessUp || event.key == .keyboardLightUp
            result = NotchLevelStep.step(from: before.value, direction: up ? .up : .down,
                                         modifiers: event.modifiers, muted: kind == .volume && before.muted)
            target.value = result.value
            if result.changed { wroteOK = port.write(kind, value: result.value) }
            if wroteOK, result.unmutes {
                target.muted = false
                wroteOK = port.setMuted(false)
            }
        }
        guard wroteOK, let after = port.read(kind), Self.matches(after, target) else {
            fail(kind, raw: raw)
            return
        }
        _ = suppression.wrote(kind, .matched)
        onLevel?(kind, after, result)
    }

    private func fail(_ kind: NotchLevelKind, raw: NotchLevelRawKey) {
        if suppression.wrote(kind, .mismatched) == .reissueToSystem { port.reissue(raw) }
        refreshCapabilities()
    }

    nonisolated static func matches(_ read: NotchLevelReading, _ target: NotchLevelReading) -> Bool {
        read.muted == target.muted && abs(read.value - target.value) <= readbackTolerance
    }
}

#if !NOTCH_LEVEL_HOST_TESTING

// MARK: - 系统的写入端

/// 音量走 Core Audio（和遥控器调音量 WS2RemoteSystemPort 同一条写法：默认输出设备的 VirtualMainVolume，
/// 设备说能设才写；静音是输出域的 Mute）；亮度走 DisplayServices 的设亮度接口（dlsym，拿不到当不能写），
/// 只写内建屏；键盘灯走 CoreBrightness 的键盘灯客户端（读不到当不能写）。
@MainActor final class NotchLevelSystemPort: NotchLevelWritePort {
    private typealias BrightnessGet = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias BrightnessSet = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias KeyboardGet = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KeyboardSet = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private let getBrightness: BrightnessGet?
    private let setBrightness: BrightnessSet?
    /// 每个输出设备能不能调音量、静音，探过一次就记住（换回来不再探）。
    private var deviceCache: [AudioObjectID: (volume: Bool, mute: Bool)] = [:]
    private var keyboard: (client: NSObject, id: UInt64)?
    private var keyboardProbed = false
    /// 只在有画面接键盘灯时才去探它（LV3 之前没有，不碰那个私有桥）。
    var wantsKeyboardLight = false

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let get = dlsym(handle, "DisplayServicesGetBrightness"),
           let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getBrightness = unsafeBitCast(get, to: BrightnessGet.self)
            setBrightness = unsafeBitCast(set, to: BrightnessSet.self)
        } else {
            getBrightness = nil
            setBrightness = nil
        }
    }

    func probeCapabilities() -> NotchLevelCapabilities {
        var caps = NotchLevelCapabilities()
        if let device = Self.defaultOutputDevice() {
            if let cached = deviceCache[device] {
                caps.volume = cached.volume
                caps.mute = cached.mute
            } else {
                var volume = Self.volumeAddress
                var mute = Self.muteAddress
                let entry = (volume: Self.settable(device, &volume), mute: Self.settable(device, &mute))
                deviceCache[device] = entry
                caps.volume = entry.volume
                caps.mute = entry.mute
            }
        }
        if setBrightness != nil, let display = Self.builtInDisplay(), readBrightness(display) != nil {
            caps.brightness = true
        }
        if wantsKeyboardLight { caps.keyboardLight = keyboardClient().flatMap { readKeyboard($0) } != nil }
        return caps
    }

    func read(_ kind: NotchLevelKind) -> NotchLevelReading? {
        switch kind {
        case .volume:
            guard let device = Self.defaultOutputDevice() else { return nil }
            var address = Self.volumeAddress
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return NotchLevelReading(value: Double(min(1, max(0, value))), muted: Self.readMuted(device) ?? false)
        case .brightness:
            guard let display = Self.builtInDisplay(), let value = readBrightness(display) else { return nil }
            return NotchLevelReading(value: value)
        case .keyboardLight:
            guard let keyboard = keyboardClient(), let value = readKeyboard(keyboard) else { return nil }
            return NotchLevelReading(value: value)
        }
    }

    func write(_ kind: NotchLevelKind, value: Double) -> Bool {
        let next = Float32(min(1, max(0, value)))
        switch kind {
        case .volume:
            guard let device = Self.defaultOutputDevice() else { return false }
            var address = Self.volumeAddress
            var level = next
            return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
        case .brightness:
            guard let setBrightness, let display = Self.builtInDisplay() else { return false }
            return setBrightness(display, next) == 0
        case .keyboardLight:
            guard let keyboard = keyboardClient() else { return false }
            let selector = NSSelectorFromString("setBrightness:forKeyboard:")
            guard keyboard.client.responds(to: selector) else { return false }
            let call = unsafeBitCast(keyboard.client.method(for: selector), to: KeyboardSet.self)
            return call(keyboard.client, selector, next, keyboard.id)
        }
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        var address = Self.muteAddress
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    func reissue(_ raw: NotchLevelRawKey) {
        let code = (raw.data1 & 0xFFFF_0000) >> 16
        let modifiers = UInt(truncatingIfNeeded: raw.flags) & 0xFFFF_0000
        for down in [true, false] {
            let data1 = (code << 16) | ((down ? 0xA : 0xB) << 8)
            let flags = NSEvent.ModifierFlags(rawValue: modifiers | (down ? 0xA00 : 0xB00))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: NotchLevelControl.reissueMark)
            event.post(tap: .cghidEventTap)
        }
    }

    func playVolumeFeedback() {
        // 系统设置“调音量时播放反馈”：全局域里那一项，1 是开。
        guard UserDefaults.standard.integer(forKey: "com.apple.sound.beep.feedback") == 1 else { return }
        let path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }

    // MARK: 读

    private func readBrightness(_ display: CGDirectDisplayID) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return Double(min(1, max(0, value)))
    }

    private func keyboardClient() -> (client: NSObject, id: UInt64)? {
        if keyboardProbed { return keyboard }
        keyboardProbed = true
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = type.init()
        let copyIDs = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: copyIDs),
              let ids = client.perform(copyIDs)?.takeRetainedValue() as? [NSNumber],
              let id = ids.first?.uint64Value else { return nil }
        keyboard = (client, id)
        return keyboard
    }

    private func readKeyboard(_ keyboard: (client: NSObject, id: UInt64)) -> Double? {
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard keyboard.client.responds(to: selector) else { return nil }
        let call = unsafeBitCast(keyboard.client.method(for: selector), to: KeyboardGet.self)
        let value = call(keyboard.client, selector, keyboard.id)
        guard value.isFinite else { return nil }
        return Double(min(1, max(0, value)))
    }

    /// 正在用的内建屏；合盖只用外接屏时没有，亮度键就交给系统。
    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func settable(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func readMuted(_ device: AudioObjectID) -> Bool? {
        var address = muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
}

// MARK: - 输出设备是什么

/// 默认输出设备的传输方式、型号名、耳机口数据源，翻成两耳左边的设备符号（分类规则在 Core/NotchLevelOutput）。
/// 只在启动和默认输出设备变了时读一次，缓存着用，不轮询；读不到的项当没有，最后落到扬声器。
enum NotchLevelOutputReader {
    static func read(device: AudioObjectID) -> NotchLevelEars.Output {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return .speaker }
        return NotchLevelEars.Output.classify(
            name: name(device),
            transport: NotchLevelTransport(code: uint32(device, kAudioDevicePropertyTransportType,
                                                         scope: kAudioObjectPropertyScopeGlobal)),
            dataSource: uint32(device, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput))
    }

    private static func uint32(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func name(_ device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
#endif
