// WindowShade · TMR-2。计时器的宿主：把 Core/CountdownTimer 接上时钟、唤醒、响一声和“记住上次的分钟数”。
// 这个文件只依赖 Foundation 和 CoreAudio（读系统静音），不碰 AppKit，所以不开窗口也能单测。
// 画面在 CountdownTimerCard.swift，刘海里的耳朵由 NotchActivityController 发布。
import Foundation
import CoreAudio
import AudioToolbox

/// 计时器上用户看得见的字（词汇照 docs/copy-guide.md“计时器”一行）。
enum CountdownTimerText {
    /// 右耳：多于 60 秒写“9 分”（向上取整），最后 60 秒写“0:42”。
    static func ear(remaining: UInt64) -> String {
        let seconds = ceilingSeconds(remaining)
        if seconds <= 60 { return clock(seconds) }
        return WSL10n.text("timer.minutesShort", zh: "%@ 分", String((seconds + 59) / 60))
    }

    /// 大卡上的大字：m:ss，向上取整。
    static func big(remaining: UInt64) -> String { clock(ceilingSeconds(remaining)) }

    /// 超时：不到 1 分钟写“+0:42”，之后写“+3 分”（向下取整）。
    static func overtime(_ elapsed: UInt64) -> String {
        let seconds = elapsed / WS2.Duration.second
        if seconds < 60 { return "+" + clock(seconds) }
        return WSL10n.text("timer.plusMinutes", zh: "+%@ 分", String(seconds / 60))
    }

    /// 按状态选右耳的字：运行和暂停写剩余，超时写超时。空闲没有字。
    static func ear(for timer: CountdownTimer, at now: WS2.Instant) -> String {
        switch timer.state {
        case .idle: return ""
        case .running, .paused: return ear(remaining: timer.remaining(at: now))
        case .done: return overtime(timer.overtime(at: now))
        }
    }

    /// “10 分钟计时器”：时间到的次句，也是大卡上的标题。
    static func minutesLine(_ minutes: Int) -> String { WSL10n.text("timer.minutesLine", zh: "%@ 分钟计时器", String(minutes)) }

    /// 展开卡片的次句。
    static func subtitle(for timer: CountdownTimer) -> String {
        switch timer.state {
        case .idle: return ""
        case .running: return minutesLine(timer.totalMinutes)
        case .paused: return WSL10n.text("say.paused", zh: "已暂停") + " · " + minutesLine(timer.totalMinutes)
        case .done: return WSL10n.text("timer.timeUp", zh: "时间到") + " · " + minutesLine(timer.totalMinutes)
        }
    }

    /// 读屏念的话：紧凑读作“计时器，还剩 9 分钟”。
    static func spoken(for timer: CountdownTimer, at now: WS2.Instant) -> String {
        switch timer.state {
        case .idle: return WSL10n.text("notch.kind.timer", zh: "计时器")
        case .running, .paused:
            let seconds = ceilingSeconds(timer.remaining(at: now))
            let left = seconds <= 60 ? WSL10n.text("timer.seconds", zh: "%@ 秒", String(seconds))
                                       : WSL10n.text("timer.minutesLong", zh: "%@ 分钟", String((seconds + 59) / 60))
            return WSL10n.text("timer.spoken", zh: "计时器，%@还剩 %@",
                               timer.state == .paused ? WSL10n.text("say.paused", zh: "已暂停") + WSL10n.text("notch.join", zh: "，") : "",
                               left)
        case .done:
            return WSL10n.text("timer.spokenOvertime", zh: "计时器，时间到，已超时 %@",
                                   String(overtime(timer.overtime(at: now)).dropFirst()))
        }
    }

    private static func ceilingSeconds(_ nanoseconds: UInt64) -> UInt64 {
        (nanoseconds + WS2.Duration.second - 1) / WS2.Duration.second
    }
    private static func clock(_ seconds: UInt64) -> String { "\(seconds / 60):\(String(format: "%02llu", seconds % 60))" }
}

/// 计时器的橙色（稿里的 #ff9f0a，和 problem 的系统橙是同一种，但这里是环、那里是边线）。
enum CountdownTimerStyle {
    static let orangeRGB: (Double, Double, Double) = (1.0, 0x9F / 255, 0x0A / 255)
    /// 暂停时环和数字降到这个透明度。
    static let pausedAlpha: Double = 0.5
}

/// ⌃⌥T 长出的选分钟：1 / 3 / 5 / 10 / 15 / 30，或用 ↑ ↓ 一分钟一分钟调。
enum CountdownTimerPicker {
    static let presets = [1, 3, 5, 10, 15, 30]
    static let range = 1...120

    /// 上一次用的分钟数；没有或越界就是 10。
    static func initial(last: Int) -> Int { range.contains(last) ? last : CountdownTimer.defaultMinutes }
    /// ↑ 加一分钟，↓ 减一分钟，停在边上。
    static func step(_ minutes: Int, by delta: Int) -> Int { min(range.upperBound, max(range.lowerBound, minutes + delta)) }
    /// 按键：↑ ↓ 调，回车开始，Esc 取消。
    enum Key: Equatable { case up, down, start, cancel }
    static func key(forKeyCode code: UInt16) -> Key? {
        switch code {
        case 126: return .up
        case 125: return .down
        case 36, 76: return .start
        case 53: return .cancel
        default: return nil
        }
    }
}

/// 计时器自己的两项设置：到时间响一声（默认开，稿里唯一默认会响的声音）、上次选的分钟数。
/// 读写点集中在这里，隐私登记（tools/privacy/registry.json）只登记这几行。
enum CountdownTimerSettings {
    static let chimeKey = "Timer.chimeEnabled"
    static let lastMinutesKey = "Timer.lastMinutes"
    /// 只有单线程的测试会在使用前换掉它再换回；App 里从不赋值。
    nonisolated(unsafe) static var store: UserDefaults = .standard

    static var chimeEnabled: Bool {
        get { store.object(forKey: chimeKey) as? Bool ?? true }
        set { store.set(newValue, forKey: chimeKey) }
    }
    static var lastMinutes: Int {
        get { CountdownTimerPicker.initial(last: store.integer(forKey: lastMinutesKey)) }
        set { store.set(newValue, forKey: lastMinutesKey) }
    }
}

/// 系统现在是不是静音：默认输出设备的静音开关开着，或音量为 0。读不到就当没静音（让系统自己决定出不出声）。
enum CountdownTimerSystemAudio {
    static func isMuted() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultOutput = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil, &size, &device) == noErr,
              device != AudioObjectID(kAudioObjectUnknown) else { return false }
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &mute) {
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &mute, 0, nil, &valueSize, &value) == noErr, value != 0 { return true }
        }
        var volume = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                mScope: kAudioDevicePropertyScopeOutput,
                                                mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &volume) {
            var level: Float32 = 1
            var levelSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &volume, 0, nil, &levelSize, &level) == noErr, level <= 0 { return true }
        }
        return false
    }
}

/// 计时器宿主。唯一的一只计时器；钟、响声、静音、开关都由外面注入，测试不需要真的等，也不出声。
@MainActor
final class CountdownTimerHost {
    private(set) var model: CountdownTimer
    private let clock: any WS2Clock
    private let chime: () -> Void
    private let isMuted: () -> Bool
    private let chimeEnabled: () -> Bool
    private let remember: (Int) -> Void
    private var wake: Task<Void, Never>?
    private var revision: UInt64 = 0
    /// 状态变了（含每次右耳的字要换）：刘海发布活动、卡片重画都挂在这里。
    var onChange: ((CountdownTimer, WS2.Instant) -> Void)?
    /// 到点了，而且是刚到（60 秒内发现）：鼓“时间到”。睡过头醒来只显示超时，不会调用。
    var onTimeUp: (() -> Void)?
    /// 计时器回到空闲（手动结束，或超时满 10 分钟）。
    var onFinished: (() -> Void)?
    /// 大卡开着时要每秒换一次字（紧凑两耳不需要）。
    var wantsSecondTicks = false { didSet { if wantsSecondTicks != oldValue { schedule(at: clock.now()) } } }
    /// 响过几次（测试和诊断用）。
    private(set) var chimeCount = 0

    init(clock: any WS2Clock = WS2ContinuousClock(),
         lastMinutes: Int = CountdownTimer.defaultMinutes,
         chime: @escaping () -> Void,
         isMuted: @escaping () -> Bool = { CountdownTimerSystemAudio.isMuted() },
         chimeEnabled: @escaping () -> Bool = { CountdownTimerSettings.chimeEnabled },
         remember: @escaping (Int) -> Void = { CountdownTimerSettings.lastMinutes = $0 }) {
        self.clock = clock
        self.model = CountdownTimer(lastMinutes: lastMinutes)
        self.chime = chime
        self.isMuted = isMuted
        self.chimeEnabled = chimeEnabled
        self.remember = remember
    }

    var now: WS2.Instant { clock.now() }
    var isActive: Bool { model.isActive }

    func start(minutes: Int) { handle(.start(minutes: minutes)) }
    func pause() { handle(.pause) }
    func resume() { handle(.resume) }
    func togglePause() { handle(model.state == .paused ? .resume : .pause) }
    func end() { handle(.end) }
    /// “再来一个”：同样的分钟数再开一个（正在超时的先结束）。
    func again() {
        let minutes = model.totalMinutes > 0 ? model.totalMinutes : model.lastMinutes
        if model.state != .idle { handle(.end) }
        handle(.start(minutes: minutes))
    }
    /// 醒来、解锁、点开卡片时对一下时间。
    func tick() { handle(.tick) }

    func handle(_ event: CountdownTimer.Event) {
        let now = clock.now()
        let wasIdle = model.state == .idle
        let effects = model.handle(event, at: now)
        if wasIdle, model.state == .running { remember(model.lastMinutes) }
        for effect in effects {
            switch effect {
            case .chime:
                // 响一声只给一次（模型保证）；静音或关了开关就不响，但“时间到”照鼓。
                if chimeEnabled(), !isMuted() { chime(); chimeCount += 1 }
                onTimeUp?()
            case .finished:
                onFinished?()
            }
        }
        onChange?(model, now)
        schedule(at: now)
    }

    func stop() { cancelWake(); onChange = nil; onTimeUp = nil; onFinished = nil }

    // MARK: - 唤醒：一次性，只排下一次需要换字或换状态的时刻；暂停和空闲不排

    /// 下一次右耳的字会变的时刻：剩余向上取整，每分钟换一次，最后 60 秒每秒换一次；
    /// 超时前 60 秒每秒换，之后每分钟换。到点和结束线也算。
    func nextWake(at now: WS2.Instant) -> WS2.Instant? {
        guard let hard = model.nextWake() else { return nil }
        switch model.state {
        case .running:
            let left = model.remaining(at: now)
            if left == 0 { return now }
            let quantum = left <= WS2.Duration.minute || wantsSecondTicks ? WS2.Duration.second : WS2.Duration.minute
            let remainder = left % quantum
            return min(hard, now.adding(remainder == 0 ? quantum : remainder))
        case .done:
            let spent = model.overtime(at: now)
            let quantum = spent < WS2.Duration.minute || wantsSecondTicks ? WS2.Duration.second : WS2.Duration.minute
            return min(hard, now.adding(quantum - spent % quantum))
        case .idle, .paused:
            return nil
        }
    }

    private func schedule(at now: WS2.Instant) {
        cancelWake()
        guard revision < .max, let target = nextWake(at: now) else { return }
        let delay = max(1, target.elapsed(since: now)), generation = revision
        wake = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, !Task.isCancelled, self.revision == generation else { return }
            self.handle(.tick)
        }
    }

    private func cancelWake() {
        wake?.cancel(); wake = nil
        if revision < .max { revision += 1 }
    }

    deinit { wake?.cancel() }
}
