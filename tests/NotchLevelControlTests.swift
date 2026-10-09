import Foundation

/// LV2：拦键与写回。用可替换的写入端口和手写的按键事件，不碰真机：
/// 能写才吞、写失败补发、未核对版本只旁听、松开跟着按下吞，再加静音、到头、补发的那一下放行。
@main struct NotchLevelControlTests {
    @MainActor static func main() {
        swallowsOnlyWhenWritable()
        writeFailureReissues()
        readbackMismatchReissues()
        unverifiedVersionListensOnly()
        releaseFollowsPress()
        markedEventPasses()
        muteTogglesAndUnmutesOnStep()
        edgeDoesNotWrite()
        foreignHUDAndLockPass()
        feedbackOnlyForSwallowedVolumeRelease()
        print("PASS: notch level control (intercept, write-back, reissue)")
    }

    // MARK: 替身

    @MainActor final class FakePort: NotchLevelWritePort {
        var caps = NotchLevelCapabilities(volume: true, mute: true, brightness: true, keyboardLight: true)
        var values: [NotchLevelKind: NotchLevelReading] = [
            .volume: NotchLevelReading(value: 0.5), .brightness: NotchLevelReading(value: 0.5),
            .keyboardLight: NotchLevelReading(value: 0.5),
        ]
        var writeSucceeds = true
        /// 写进去了但读回来不是那个数（设备自己改了、或量化到别处）。
        var readbackDrift = 0.0
        var writes: [(NotchLevelKind, Double)] = []
        var mutes: [Bool] = []
        var reissued: [NotchLevelRawKey] = []
        var feedbacks = 0

        func probeCapabilities() -> NotchLevelCapabilities { caps }
        func read(_ kind: NotchLevelKind) -> NotchLevelReading? { values[kind] }
        func write(_ kind: NotchLevelKind, value: Double) -> Bool {
            writes.append((kind, value))
            guard writeSucceeds else { return false }
            values[kind]?.value = value + readbackDrift
            return true
        }
        func setMuted(_ muted: Bool) -> Bool {
            mutes.append(muted)
            guard writeSucceeds else { return false }
            values[.volume]?.muted = muted
            return true
        }
        func reissue(_ raw: NotchLevelRawKey) { reissued.append(raw) }
        func playVolumeFeedback() { feedbacks += 1 }
    }

    /// 写值排进这里，测试手动跑，看得清“回调里只吞不写”。
    @MainActor final class Queue {
        var work: [@MainActor () -> Void] = []
        func drain() { while !work.isEmpty { work.removeFirst()() } }
    }

    @MainActor static func make(_ port: FakePort = FakePort()) -> (NotchLevelControl, FakePort, Queue) {
        let control = NotchLevelControl(port: port)
        let queue = Queue()
        control.schedule = { queue.work.append($0) }
        control.refreshCapabilities()
        return (control, port, queue)
    }

    static func data1(_ code: Int, down: Bool, repeating: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeating ? 1 : 0)
    }

    static let codes: [NotchLevelKey: Int] = [
        .volumeUp: 0, .volumeDown: 1, .brightnessUp: 2, .brightnessDown: 3, .mute: 7,
        .keyboardLightUp: 21, .keyboardLightDown: 22,
    ]

    /// 照真的系统事件拼出来再解析，顺带核对解析和补发用的原样。
    static func press(_ key: NotchLevelKey, down: Bool = true, flags: UInt = 0)
        -> (NotchLevelKeyEvent, NotchLevelRawKey) {
        let raw = NotchLevelRawKey(data1: data1(codes[key]!, down: down), flags: UInt64(flags))
        let event = NotchLevelKeyEvent.parse(subtype: 8, data1: raw.data1, modifierFlags: flags)!
        return (event, raw)
    }

    static func ready() -> NotchLevelSuppression.Input { NotchLevelSuppression.Input() }

    @MainActor @discardableResult
    static func route(_ control: NotchLevelControl, _ key: NotchLevelKey, down: Bool = true, flags: UInt = 0,
                      marked: Bool = false, input: NotchLevelSuppression.Input = ready()) -> NotchLevelControl.Verdict {
        let (event, raw) = press(key, down: down, flags: flags)
        return control.route(event, raw: raw, marked: marked, input: input).verdict
    }

    // MARK: 用例

    /// 能调就吞，写值排到回调之后；不能调（HDMI 输出）放行，什么都不写。
    @MainActor static func swallowsOnlyWhenWritable() {
        let (control, port, queue) = make()
        precondition(route(control, .volumeUp) == .swallow, "能调的音量键该吞")
        precondition(port.writes.isEmpty, "回调里不写，写值排到后面")
        queue.drain()
        precondition(port.writes.count == 1 && abs(port.writes[0].1 - 0.5625) < 1e-9, "照 1/16 走一格")

        let hdmi = FakePort()
        hdmi.caps.volume = false
        hdmi.caps.mute = false
        let (other, otherPort, otherQueue) = make(hdmi)
        precondition(route(other, .volumeUp) == .pass, "输出不能调：放行")
        precondition(route(other, .mute) == .pass, "静音不能设：放行")
        otherQueue.drain()
        precondition(otherPort.writes.isEmpty && otherPort.mutes.isEmpty, "放行的不写")

        // 只有静音不能设时，音量键照拦，静音键放行。
        let partial = FakePort()
        partial.caps.mute = false
        let (third, _, _) = make(partial)
        precondition(route(third, .volumeDown) == .swallow && route(third, .mute) == .pass, "按键对应的那一项才算")

        // 调用方说不能调（比如键盘灯没接画面）也放行。
        var input = ready()
        input.deviceAdjustable = false
        precondition(route(control, .keyboardLightUp, input: input) == .pass, "调用方说不能调：放行")
    }

    /// 写这一步报错：原键补发给系统，这一类本次开机不再拦，别的类照拦。
    @MainActor static func writeFailureReissues() {
        let (control, port, queue) = make()
        port.writeSucceeds = false
        precondition(route(control, .brightnessUp) == .swallow, "第一下照拦")
        queue.drain()
        precondition(port.reissued.count == 1, "写失败：补发一次")
        precondition(port.reissued[0].data1 == data1(2, down: true), "补发的是原键")
        precondition(control.suppression.failedKinds == [.brightness], "记下这一类")
        precondition(route(control, .brightnessUp, down: false) == .swallow, "补发过一对，原来的松开照吞")
        precondition(route(control, .brightnessDown) == .pass, "这一类不再拦")
        port.writeSucceeds = true
        precondition(route(control, .volumeUp) == .swallow, "别的类照拦")
    }

    /// 写进去没报错，读回来不对：一样补发。
    @MainActor static func readbackMismatchReissues() {
        let (control, port, queue) = make()
        port.readbackDrift = 0.1
        var levels = 0
        control.onLevel = { _, _, _ in levels += 1 }
        route(control, .volumeUp)
        queue.drain()
        precondition(port.reissued.count == 1, "读回不对：补发")
        precondition(levels == 0, "不对的值不画")
        precondition(route(control, .volumeUp) == .pass, "本次开机不再拦音量")

        // 量化在半格（1/128）以内算对上。
        let (ok, okPort, okQueue) = make()
        okPort.readbackDrift = 0.005
        ok.onLevel = { _, _, _ in levels += 1 }
        route(ok, .volumeUp)
        okQueue.drain()
        precondition(okPort.reissued.isEmpty && levels == 1, "量化误差内算写对了")
    }

    /// 版本表空着：默认不装主动监听；装了也只旁听、两个都在。开关打开才当已核对。
    @MainActor static func unverifiedVersionListensOnly() {
        let os = NotchLevelOSVersion(major: 27, minor: 0)
        precondition(NotchLevelControl.verifiedOSVersions.isEmpty, "还没有真机证据，表是空的")
        precondition(!NotchLevelControl.versionVerified(os, trustThisOS: false), "没核对过")
        precondition(NotchLevelControl.versionVerified(os, trustThisOS: true), "开关强制当已核对")
        precondition(NotchLevelControl.versionVerified(os, trustThisOS: false, table: [os]), "表里有就算")
        precondition(!NotchLevelControl.versionVerified(NotchLevelOSVersion(major: 27, minor: 1), trustThisOS: false,
                                                        table: [os]), "按主次版本号对")
        precondition(!NotchLevelControl.installsTap(accessibilityTrusted: true, versionVerified: false), "没核对不换监听")
        precondition(!NotchLevelControl.installsTap(accessibilityTrusted: false, versionVerified: true), "没辅助功能不换")
        precondition(NotchLevelControl.installsTap(accessibilityTrusted: true, versionVerified: true), "两样都有才换")

        let (control, port, queue) = make()
        var input = ready()
        input.versionVerified = false
        let (event, raw) = press(.volumeUp)
        let routed = control.route(event, raw: raw, marked: false, input: input)
        precondition(routed.verdict == .pass, "没核对：放行")
        precondition(routed.decision?.visible == .both && routed.decision?.reason == .versionNotVerified, "两个都在")
        input.versionVerified = true
        input.listener = .listenOnly
        precondition(route(control, .volumeUp, input: input) == .pass, "只旁听：放行")
        queue.drain()
        precondition(port.writes.isEmpty, "旁听不写")
    }

    /// 松开跟着最近那次按下：按下吞了松开也吞；按下放了松开也放；没见过按下的松开放行。
    @MainActor static func releaseFollowsPress() {
        let (control, _, queue) = make()
        precondition(route(control, .volumeDown, down: false) == .pass, "没见过按下：放行")
        route(control, .volumeDown)
        precondition(route(control, .volumeDown, down: false) == .swallow, "按下吞了，松开也吞")
        precondition(route(control, .volumeDown, down: false) == .pass, "只吞一次")

        // 按住连发中途被放行（比如按上了 ⌘），松开跟着放行。
        route(control, .volumeUp)
        precondition(route(control, .volumeUp, flags: 1 << 20) == .pass, "按着 ⌘：放行")
        precondition(route(control, .volumeUp, down: false) == .pass, "最近那次按下放了，松开也放")

        // 不同的键各记各的。
        route(control, .brightnessUp)
        route(control, .volumeUp)
        precondition(route(control, .brightnessUp, down: false) == .swallow, "亮度松开吞")
        precondition(route(control, .volumeUp, down: false) == .swallow, "音量松开吞")
        queue.drain()
    }

    /// 自己补发的那一下（带记号）一律放行，不进判定、不写。
    @MainActor static func markedEventPasses() {
        let (control, port, queue) = make()
        precondition(route(control, .volumeUp, marked: true) == .pass, "带记号：放行")
        precondition(route(control, .volumeUp, down: false, marked: true) == .pass, "带记号的松开：放行")
        queue.drain()
        precondition(port.writes.isEmpty, "不写")
    }

    /// 静音键切换静音；静音时按 + 先取消静音再走一格；⌥⇧ 走 1/64。
    @MainActor static func muteTogglesAndUnmutesOnStep() {
        let (control, port, queue) = make()
        var last: NotchLevelReading?
        control.onLevel = { _, reading, _ in last = reading }
        route(control, .mute)
        queue.drain()
        precondition(port.mutes == [true] && last?.muted == true, "静音键：静音")
        route(control, .volumeUp)
        queue.drain()
        precondition(port.mutes == [true, false], "静音时按 +：先取消静音")
        precondition(last == NotchLevelReading(value: 0.5625, muted: false), "再走一格")
        route(control, .volumeUp, flags: (1 << 17) | (1 << 19))
        queue.drain()
        precondition(abs((last?.value ?? 0) - (0.5625 + 1.0 / 64.0)) < 1e-9, "⌥⇧ 细调 1/64")
    }

    /// 已经到头再按：不写，照样画（带着“到头了”），不补发。
    @MainActor static func edgeDoesNotWrite() {
        let port = FakePort()
        port.values[.brightness] = NotchLevelReading(value: 1)
        let (control, _, queue) = make(port)
        var edge: NotchLevelStep.Edge?
        control.onLevel = { _, _, result in edge = result.edge }
        precondition(route(control, .brightnessUp) == .swallow, "到头了也拦")
        queue.drain()
        precondition(port.writes.isEmpty && port.reissued.isEmpty, "数值不变，不写不补发")
        precondition(edge == .upper, "画“到头了”")
    }

    /// 对方 App 在管、锁着：放行，交给它们。
    @MainActor static func foreignHUDAndLockPass() {
        let (control, port, queue) = make()
        var input = ready()
        input.foreignHUDRunning = true
        precondition(route(control, .volumeUp, input: input) == .pass, "对方在管：放行")
        input = ready()
        input.locked = true
        precondition(route(control, .brightnessUp, input: input) == .pass, "锁着：放行")
        queue.drain()
        precondition(port.writes.isEmpty, "不写")
    }

    /// 吞了音量键的松开，才由我们放反馈声；亮度、静音不放。
    @MainActor static func feedbackOnlyForSwallowedVolumeRelease() {
        let (control, port, queue) = make()
        route(control, .volumeUp)
        route(control, .volumeUp, down: false)
        route(control, .brightnessUp)
        route(control, .brightnessUp, down: false)
        route(control, .mute)
        route(control, .mute, down: false)
        queue.drain()
        precondition(port.feedbacks == 1, "只有音量 +/− 的松开放一声")
    }
}
