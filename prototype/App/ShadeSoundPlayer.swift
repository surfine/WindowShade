// 收起 / 展开的音效。
//
// 为什么单独一个播放器：音频设备闲下来之后，`NSSound.play()` 会在**调用线程上**同步把设备拉起来，
// 实测 250–500ms（2026-10-01：冷启动 496ms，设备热着 0ms）。以前它直接在主线里播，
// 每次「收起 / 展开」都冻结主线程半秒——日志里那几段 `CoreAudio AudioDeviceStart` 的
// 主线程卡顿就是它（`.build/closeout/` 里也能看到对应的 stall 采样）。
//
// 现在：固定在这条串行队列上播（主线程立即返回），并在折叠/展开动作开始前用一次静音播放
// 把设备叫醒。设备是进程级共享的，所以预热一次，后面的音效就是 0ms 起播。

import AppKit

/// 不是 `@MainActor`：状态全部只在这条串行队列上访问（`@unchecked Sendable` 的依据），
/// 所以主线程、手势队列都能直接 fire-and-forget 地叫它，不会有人等在半路上。
final class ShadeSoundPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.windowshade.sounds", qos: .userInitiated)
    private var cache: [String: NSSound] = [:]
    private let lock = NSLock()
    private var plays = 0
    private var lastMilliseconds = 0

    /// 播放音量。默认 1；测试把它设成 0，走同一条路径但不出声。
    var volume: Float = 1

    /// 诊断 / 测试用：后台真正播了几次、最后一次在队列上花了多久。
    var stats: (plays: Int, lastMilliseconds: Int) {
        lock.lock(); defer { lock.unlock() }
        return (plays, lastMilliseconds)
    }

    /// 真正要听到的那一次：排队播，不在主线程等设备起来。
    func play(_ name: String) {
        queue.async { [self] in
            guard let sound = sound(name) else { return }
            sound.stop()
            sound.volume = volume
            let started = CFAbsoluteTimeGetCurrent()
            sound.play()
            // 设备冷启动的那一下会在这里花掉 250–500ms——记一行，证明它花在后台队列上而不是主线程。
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            lock.lock(); plays += 1; lastMilliseconds = elapsedMilliseconds; lock.unlock()
            if elapsedMilliseconds >= 50 {
                wlog("perf: sound \(name) play \(elapsedMilliseconds)ms on the sound queue (audio device cold start)")
            }
        }
    }

    /// 静音播一次，把音频设备预热。用的是另一个实例，不会动到要听到的那份音量。
    func prewarm(_ name: String) {
        queue.async {
            guard let warm = NSSound(named: NSSound.Name(name)) else { return }
            warm.volume = 0
            warm.play()
        }
    }

    /// 系统提示音。`NSSound.beep()` 和播放一样会在调用线程上拉设备，所以也放到这条队列上。
    func beep() {
        queue.async { NSSound.beep() }
    }

    private func sound(_ name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let made = NSSound(named: NSSound.Name(name)) else { return nil }
        cache[name] = made
        return made
    }
}

/// 全局一份：音效队列和缓存共用（主线程、手势队列都直接叫它）。
let shadeSounds = ShadeSoundPlayer()
