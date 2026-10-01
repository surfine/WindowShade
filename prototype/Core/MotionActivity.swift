// 机器在不在动。只服务一件事：决定盖角传感器要不要降频。
//
// 铰链角度是一次同步 HID feature 读取，实测 0.914ms（Mac17,4 / macOS 27.0，100 次平均，最大 1.71ms）。
// 空闲时按 12Hz 问，就是常驻约 1.1% 单核——效果开着时多出来的那部分 CPU 基本就是它。
// 而 Accelerometer 是驱动**推**上来的（62 份/秒，回调几乎不花钱），拿它当“有人在动盖子”的信号：
// 机器静止时铰链降到 4Hz，一动起来立刻回到 12Hz，合盖途中照旧 60Hz。
//
// 纯逻辑，不碰硬件：`feed` 喂原始加速度向量（g），回滞靠 `hold` 秒的住留时间。

import Foundation

struct MotionActivityDetector: Equatable {
    /// 相邻两份读数差多少算「动了一下」，单位 g。手扶、挪动、合盖都远大于这个数；桌面震动不会。
    var threshold: Double = 0.02
    /// 最后一次运动之后还保持「在动」这么久（秒）。
    var hold: Double = 0.6

    private var previous: SIMD3<Double>?
    private var lastMotionAt: Double = -.infinity

    /// 喂一份原始读数（时间用单调秒），返回此刻算不算「在动」。
    mutating func feed(_ sample: SIMD3<Double>, at now: Double) -> Bool {
        defer { previous = sample }
        guard let previous else { return isMoving(at: now) }
        let delta = max(abs(sample.x - previous.x),
                        max(abs(sample.y - previous.y), abs(sample.z - previous.z)))
        if delta >= threshold { lastMotionAt = now }
        return isMoving(at: now)
    }

    func isMoving(at now: Double) -> Bool { now - lastMotionAt <= hold }

    mutating func reset() {
        previous = nil
        lastMotionAt = -.infinity
    }
}

/// 盖角传感器的轮询间隔（秒）：合盖途中 60Hz 跟手；机器在动 12Hz（原来的空闲速率）；
/// 确实是静止 4Hz。放在 Core 里是为了能单独测——它决定了那 1.1% CPU 到底省不省得下来。
enum LidPollInterval {
    static func seconds(engaged: Bool, moving: Bool) -> Double {
        if engaged { return 1.0 / 60 }
        return moving ? 1.0 / 12 : 1.0 / 4
    }
}

/// 铰链自己看到的「有人在掰盖子」：角度变化超过阈值，就把「在动」续到 `hold` 秒之后。
/// 兜底「慢慢合盖、底座几乎不动、加速度计看不出来」的情况——最多晚一个 4Hz 周期（250ms）
/// 就靠下一份读数把采样率拉回 12Hz，合盖动画不会一直慢半拍。
struct HingeMoveGate {
    /// 两份读数差多少度算「在掰」。0.3° 远大于读数噪声。
    var threshold: Double = 0.3
    /// 看到变化之后保持「在动」多久（秒）。
    var hold: Double = 3

    private var lastAngle: Double?
    private var movedUntil: Double = -.infinity

    mutating func feed(_ angle: Double, at now: Double) -> Bool {
        defer { lastAngle = angle }
        guard let lastAngle else { return isMoving(at: now) }
        if abs(angle - lastAngle) >= threshold { movedUntil = now + hold }
        return isMoving(at: now)
    }

    func isMoving(at now: Double) -> Bool { now < movedUntil }

    mutating func reset() {
        lastAngle = nil
        movedUntil = -.infinity
    }
}
