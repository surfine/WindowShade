// 运动判定与盖角轮询间隔：静止时能不能安全降频，靠这两条纯逻辑守着。
// 背景：铰链角度一次读取 0.914ms（Mac17,4 / macOS 27.0 实测），12Hz 空闲轮询≈1.1% 单核；
// 加速度计是驱动推上来的，拿它判断「在动」，静止就降到 4Hz。
import Foundation
import simd

@main
struct MotionActivityTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 1. 第一份读数还看不出动不动；连续静止就一直不动。
        var detector = MotionActivityDetector()
        _ = detector.feed(SIMD3(0, 0, 1), at: 0)
        expect(!detector.isMoving(at: 0.1), "the first sample alone is not motion")
        for step in 1...20 { _ = detector.feed(SIMD3(0, 0, 1), at: Double(step) * 0.016) }
        expect(!detector.isMoving(at: 0.34), "a still machine stays still")

        // 2. 桌面上的小抖动（远小于阈值）不算动。
        for step in 21...40 {
            let nudge = Double(step % 2) * 0.005
            _ = detector.feed(SIMD3(nudge, 0, 1), at: Double(step) * 0.016)
        }
        expect(!detector.isMoving(at: 0.65), "jitter below the threshold is not motion")

        // 3. 一次明显移动：立刻算「在动」，并保持 hold 秒。
        expect(detector.feed(SIMD3(0.2, 0, 1), at: 1.0), "a real movement counts right away")
        expect(detector.isMoving(at: 1.5), "and it still counts during the hold window")
        expect(!detector.isMoving(at: 1.0 + detector.hold + 0.01), "then it settles back to still")

        // 4. reset 之后不残留「在动」。
        var reset = MotionActivityDetector()
        _ = reset.feed(SIMD3(0, 0, 1), at: 0)
        _ = reset.feed(SIMD3(1, 0, 0), at: 0.1)
        expect(reset.isMoving(at: 0.2), "moving before reset")
        reset.reset()
        expect(!reset.isMoving(at: 0.3), "reset forgets the motion")

        // 5. 轮询间隔：合盖 60Hz / 在动 12Hz / 静止 4Hz。
        expect(abs(LidPollInterval.seconds(engaged: true, moving: false) - 1.0 / 60) < 1e-9,
               "while folding in, the hinge is polled at 60Hz")
        expect(abs(LidPollInterval.seconds(engaged: false, moving: true) - 1.0 / 12) < 1e-9,
               "while the machine is being moved: 12Hz (the old idle rate)")
        expect(abs(LidPollInterval.seconds(engaged: false, moving: false) - 1.0 / 4) < 1e-9,
               "while it is genuinely still: 4Hz, which is the ~0.8% CPU this saves")
        expect(LidPollInterval.seconds(engaged: false, moving: false) > LidPollInterval.seconds(engaged: false, moving: true),
               "the still rate is slower than the moving rate")

        // 6. 自愈：慢慢合盖（底座几乎不动、加速度计看不出来）时，铰链自己看到角度变化就把采样率拉回来。
        var gate = HingeMoveGate()
        _ = gate.feed(112.0, at: 0)
        expect(!gate.isMoving(at: 0.1), "a first angle reading alone is not a move")
        _ = gate.feed(112.1, at: 0.25)   // 噪声级别，不算
        expect(!gate.isMoving(at: 0.3), "0.1 degree of noise is not a move")
        _ = gate.feed(111.0, at: 0.5)    // 真在掰
        expect(gate.isMoving(at: 0.6), "a degree of change counts as moving")
        expect(gate.isMoving(at: 0.5 + gate.hold - 0.1), "and it holds for a while")
        expect(!gate.isMoving(at: 0.5 + gate.hold + 0.1), "then it lets go again")
        gate.reset()
        expect(!gate.isMoving(at: 100), "reset forgets the hinge motion")

        if failures == 0 { print("PASS: motion gating only slows the hinge poll when nothing is moving") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
