import Foundation

/// 1-1：音量、亮度提示只认按键，不认数值变化；到头了按键也开口；锁屏、全屏、调度中心让开；
/// 听不到按键时退回“数值一变就开口”。
@main struct NotchLevelGateTests {
    static func main() {
        parsing()
        keyThenValue()
        valueWithoutKey()
        boundaryPress()
        yields()
        fallback()
        print("PASS: notch level gate follows key presses, not value changes")
    }

    static func data1(_ code: Int, down: Bool, repeating: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeating ? 1 : 0)
    }

    static func parsing() {
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(0, down: true)) == .volumeUp)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(1, down: true)) == .volumeDown)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(2, down: true)) == .brightnessUp)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(3, down: true)) == .brightnessDown)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(7, down: true)) == .mute)
        // 按住连发也算按下。
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(0, down: true, repeating: true)) == .volumeUp)
        // 松开、别的媒体键（播放 16）、别的 subtype 都不算。
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(0, down: false)) == nil)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(16, down: true)) == nil)
        precondition(NotchLevelKey.parse(subtype: 7, data1: data1(0, down: true)) == nil)
    }

    static func keyThenValue() {
        var gate = NotchLevelGate(keysAvailable: true)
        let free = NotchLevelGate.Context()
        precondition(gate.keyPressed(.volumeUp, at: 10, context: free) == .show)
        precondition(gate.valueChanged(.volume, at: 10.05, context: free) == .show, "这一下按出来的变化")
        precondition(gate.valueChanged(.volume, at: 10.6, context: free) == .show, "窗口边上还算")
        precondition(gate.valueChanged(.volume, at: 10.7, context: free) == .ignore(.noKey), "过了窗口不算")
        // 按的是音量键，亮度自己变了不算。
        precondition(gate.valueChanged(.brightness, at: 10.05, context: free) == .ignore(.noKey))
        precondition(gate.recentlyPressed(.volume, at: 10.3) && !gate.recentlyPressed(.brightness, at: 10.3))
    }

    static func valueWithoutKey() {
        let gate = NotchLevelGate(keysAvailable: true)
        // AirPods 个性化音量、某个 App 改音量、自动亮度：没人按键，不开口。
        precondition(gate.valueChanged(.volume, at: 5, context: .init()) == .ignore(.noKey))
        precondition(gate.valueChanged(.brightness, at: 5, context: .init()) == .ignore(.noKey))
    }

    static func boundaryPress() {
        // 已经 100% 再按音量加：数值不会变，按键本身就开口。
        var gate = NotchLevelGate(keysAvailable: true)
        precondition(gate.keyPressed(.volumeUp, at: 1, context: .init()) == .show)
        precondition(gate.keyPressed(.brightnessDown, at: 2, context: .init()) == .show)
        precondition(gate.keyPressed(.mute, at: 3, context: .init()) == .show)
    }

    static func yields() {
        var gate = NotchLevelGate(keysAvailable: true)
        var locked = NotchLevelGate.Context(); locked.locked = true
        var full = NotchLevelGate.Context(); full.fullScreen = true
        var mc = NotchLevelGate.Context(); mc.missionControl = true
        precondition(gate.keyPressed(.volumeUp, at: 1, context: locked) == .ignore(.locked), "锁屏让系统自己的提示")
        precondition(gate.valueChanged(.volume, at: 1.1, context: locked) == .ignore(.locked))
        precondition(gate.keyPressed(.volumeUp, at: 2, context: full) == .ignore(.fullScreen))
        precondition(gate.keyPressed(.brightnessUp, at: 3, context: mc) == .ignore(.missionControl))
        // 让开过之后，同一窗口里回到正常桌面仍然算这一下。
        precondition(gate.valueChanged(.volume, at: 2.1, context: .init()) == .show)
    }

    static func fallback() {
        let gate = NotchLevelGate(keysAvailable: false)
        precondition(gate.valueChanged(.volume, at: 1, context: .init()) == .show, "听不到按键：数值一变就开口")
        var full = NotchLevelGate.Context(); full.fullScreen = true
        precondition(gate.valueChanged(.volume, at: 1, context: full) == .ignore(.fullScreen))
    }
}
