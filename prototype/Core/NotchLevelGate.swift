// 音量、亮度提示什么时候开口（借 Atoll 的 MediaKeyInterceptor 与 Alcove 1.6.x 更新说明的做法，只借思路）。
//
// - 看的是按键，不是数值：真的按了音量、亮度键才开口；没人按键的数值变化（AirPods 个性化音量、
//   某个 App 自己改音量、自动亮度）不开口。
// - 已经到 0% 或 100% 再按，数值不变也要开口：人按了键，就该看到“到头了”。
// - 锁屏时让系统自己的提示显示；全屏 App、调度中心里刘海不出来。
// - 听不到按键（监听没装上）时退回原来的做法：数值一变就开口。
//
// 纯逻辑，不碰 AppKit、Core Audio；按键解析也在这里，方便单测。

import Foundation

enum NotchLevelKind: Equatable, Hashable, Sendable { case volume, brightness, keyboardLight }

enum NotchLevelKey: Equatable, Sendable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, keyboardLightUp, keyboardLightDown

    var kind: NotchLevelKind {
        switch self {
        case .volumeUp, .volumeDown, .mute: return .volume
        case .brightnessUp, .brightnessDown: return .brightness
        case .keyboardLightUp, .keyboardLightDown: return .keyboardLight
        }
    }

    /// 系统媒体键事件（NSEvent.systemDefined，subtype 8）里的 data1：高 16 位是键，
    /// 次高 8 位 0x0A 按下、0x0B 松开。只认按下（含按住连发）；别的键返回 nil。
    /// 只认音量、静音、亮度五个键，键盘灯键（21、22）不在这里：现有的旁听只关心这五个，
    /// 要键盘灯、连发位、松开、修饰键走下面的 NotchLevelKeyEvent.parse。
    static func parse(subtype: Int, data1: Int) -> NotchLevelKey? {
        guard subtype == 8 else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard state == 0x0A else { return nil }
        switch code {
        case 0: return .volumeUp        // NX_KEYTYPE_SOUND_UP
        case 1: return .volumeDown      // NX_KEYTYPE_SOUND_DOWN
        case 2: return .brightnessUp    // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: return .brightnessDown  // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 7: return .mute            // NX_KEYTYPE_MUTE
        default: return nil
        }
    }
}

/// 按键时按着的修饰键，分三档。只有 ⌥⇧ 细调由我们接；按着别的修饰键，系统另有用处，原样放行。
enum NotchLevelModifiers: Equatable, Sendable {
    case none, optionShift, other

    // NSEvent.ModifierFlags 的原始位（这里不引 AppKit）。
    private static let shift: UInt = 1 << 17
    private static let control: UInt = 1 << 18
    private static let option: UInt = 1 << 19
    private static let command: UInt = 1 << 20

    /// 只看 ⇧⌃⌥⌘ 四个；大写锁定、fn、数字键盘位不算（媒体键本来就常带 fn）。
    static func classify(rawFlags: UInt) -> NotchLevelModifiers {
        let held = rawFlags & (shift | control | option | command)
        if held == 0 { return .none }
        if held == (shift | option) { return .optionShift }
        return .other
    }
}

/// 一次系统媒体键事件的完整解析：哪个键、按下还是松开、是不是按住连发、按着什么修饰键。
/// 比 NotchLevelKey.parse 多认键盘灯键（21、22），也把松开交出来（按住时松手才弹回）。
struct NotchLevelKeyEvent: Equatable, Sendable {
    var key: NotchLevelKey
    var isDown: Bool
    var isRepeat: Bool
    var modifiers: NotchLevelModifiers

    static func parse(subtype: Int, data1: Int, modifierFlags: UInt) -> NotchLevelKeyEvent? {
        guard subtype == 8 else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }
        let key: NotchLevelKey
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 7: key = .mute
        case 21: key = .keyboardLightUp      // NX_KEYTYPE_ILLUMINATION_UP
        case 22: key = .keyboardLightDown    // NX_KEYTYPE_ILLUMINATION_DOWN
        default: return nil
        }
        return NotchLevelKeyEvent(
            key: key,
            isDown: state == 0x0A,
            isRepeat: data1 & 0x1 != 0,          // keyFlags 的低位：按住连发
            modifiers: NotchLevelModifiers.classify(rawFlags: modifierFlags))
    }
}

struct NotchLevelGate: Sendable {
    /// 按键之后多久内的数值变化算“这一下按出来的”。系统改音量通常几十毫秒内到，留足余量。
    static let window: TimeInterval = 0.6

    struct Context: Equatable, Sendable {
        var locked = false
        var fullScreen = false
        var missionControl = false
    }

    enum Decision: Equatable, Sendable {
        case show
        case ignore(Reason)
    }

    enum Reason: Equatable, Sendable { case noKey, locked, fullScreen, missionControl }

    /// 监听装上了没有。没装上就退回“数值一变就开口”。
    var keysAvailable: Bool
    private var lastPress: [NotchLevelKind: TimeInterval] = [:]

    init(keysAvailable: Bool) { self.keysAvailable = keysAvailable }

    /// 按了键：马上开口（到头了数值不会变，也要让人看到）。
    mutating func keyPressed(_ key: NotchLevelKey, at time: TimeInterval, context: Context) -> Decision {
        lastPress[key.kind] = time
        return Self.blocked(context).map(Decision.ignore) ?? .show
    }

    /// 数值变了：只有刚按过同一类键才开口。
    func valueChanged(_ kind: NotchLevelKind, at time: TimeInterval, context: Context) -> Decision {
        if let reason = Self.blocked(context) { return .ignore(reason) }
        guard keysAvailable else { return .show }
        guard let pressed = lastPress[kind], time >= pressed, time - pressed <= Self.window else {
            return .ignore(.noKey)
        }
        return .show
    }

    /// 刚按过这一类键（亮度只在这段时间里去读，平时不轮询）。
    func recentlyPressed(_ kind: NotchLevelKind, at time: TimeInterval) -> Bool {
        guard let pressed = lastPress[kind] else { return false }
        return time >= pressed && time - pressed <= Self.window
    }

    private static func blocked(_ context: Context) -> Reason? {
        if context.locked { return .locked }
        if context.missionControl { return .missionControl }
        if context.fullScreen { return .fullScreen }
        return nil
    }
}
