// 合盖效果的进度（Core/LidGesture.swift）：先用造出来的序列钉住规则，
// 再回放 tests/fixtures/lid-traces/ 里 Aaron 真实录下的序列（见 docs/lid-effect.md「怎么测」）。
import Foundation

@main
struct LidGestureTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    /// 以 10Hz 喂一段角度（模拟推送），返回每一步之后的进度。
    @discardableResult
    static func run(_ g: inout LidGesture, _ angles: [Double], from start: Double = 0) -> [Double] {
        angles.enumerated().map { index, angle in
            g.feed(angle, at: start + Double(index) * 0.1)
            return g.progress
        }
    }
    static func hold(_ angle: Double, seconds: Double) -> [Double] { Array(repeating: angle, count: Int(seconds * 10)) }
    static func ramp(_ from: Double, _ to: Double, seconds: Double) -> [Double] {
        let steps = max(1, Int(seconds * 10))
        return (1...steps).map { (from + (to - from) * Double($0) / Double(steps)).rounded() }
    }
    /// 画面不跳：进度只随角度变，每一步的变化不超过角度变化 × 最陡斜率（最短一段 20°，smoothstep 最陡 1.5 倍）。
    /// 快速开合时推送一步就走十几度，进度跟着大步走是对的（画面上靠弹簧抹平）；没跟角度走的变化才是跳。
    static let steepest = 1.5 / LidGesture.closeSpan
    static func follows(_ angles: [Double], _ progress: [Double]) -> Bool {
        zip(zip(angles, angles.dropFirst()), zip(progress, progress.dropFirst())).allSatisfy { a, p in
            abs(p.1 - p.0) <= abs(a.1 - a.0) * steepest + 0.001
        }
    }

    static func main() {
        do {
            var g = LidGesture()
            let p = run(&g, hold(104, seconds: 2) + ramp(104, 89, seconds: 0.5))
            expect(g.phase == .following, "dropping fifteen degrees below rest starts following the lid")
            expect(p.last! < 0.05, "and the progress starts from the desktop, not with a jump")
        }
        do {
            var g = LidGesture()
            let angles = hold(104, seconds: 2) + ramp(104, 35, seconds: 3)
            let p = run(&g, angles)
            expect(abs(p.last! - 1) < 0.001, "closing to 35 degrees reaches the closed look")
            expect(follows(angles, p), "and the progress follows the lid without jumping")
        }
        do {
            var g = LidGesture()
            run(&g, hold(104, seconds: 2) + ramp(104, 60, seconds: 2))
            let held = g.progress
            run(&g, hold(60, seconds: 5), from: 10)
            expect(abs(g.progress - held) < 0.001, "a lid stopped half way holds its progress, however long")
            let up = ramp(60, 104, seconds: 2)
            let p = run(&g, up, from: 20)
            expect(g.progress == 0 && g.phase == .resting, "opening back to the old resting angle returns to the desktop")
            expect(follows([60] + up, [held] + p), "and the opening follows the lid without jumping")
        }
        do {
            var g = LidGesture()
            run(&g, hold(104, seconds: 2) + ramp(104, 50, seconds: 2))
            let before = g.progress
            let up = run(&g, ramp(50, 70, seconds: 1), from: 10)
            let down = run(&g, ramp(70, 45, seconds: 1), from: 20)
            expect(follows([50] + ramp(50, 70, seconds: 1) + ramp(70, 45, seconds: 1), [before] + up + down), "changing direction mid way picks up where the lid is, no jump")
            expect(g.progress > before, "and closing further after a partial opening closes further")
        }
        do {
            var g = LidGesture()
            run(&g, hold(104, seconds: 2) + ramp(104, 20, seconds: 1.5))
            run(&g, ramp(20, 98, seconds: 2), from: 10)
            expect(g.phase == .resting && g.progress == 0,
                   "opening to a few degrees short of the old rest angle still ends once the fold is no longer visible")
        }
        do {
            var g = LidGesture()
            let noisy = (0..<200).map { 101.0 + Double([0, 1, 0, -1, 1][$0 % 5]) }
            run(&g, noisy)
            expect(g.phase == .resting && g.progress == 0, "a lid resting with one degree of noise never starts")
        }
        do {
            var g = LidGesture()
            run(&g, hold(103, seconds: 2) + ramp(103, 90, seconds: 0.6) + hold(90, seconds: 2)
                    + ramp(90, 109, seconds: 1) + hold(109, seconds: 2) + ramp(109, 96, seconds: 0.6))
            expect(g.phase == .resting && g.progress == 0, "adjusting the screen by thirteen degrees (Aaron's habit) never starts")
        }
        do {
            var g = LidGesture()
            run(&g, hold(104, seconds: 2) + ramp(104, 20, seconds: 1.5))
            g.displayOff()
            expect(g.phase == .dark && g.progress == 1, "a dark display holds the closed look")
            run(&g, [1, 3, 7], from: 10)
            expect(g.displayOn(at: 11), "when the display lights again the opening begins")
            expect(g.progress == 1, "from the closed look")
            let up = ramp(7, 104, seconds: 2)
            let p = run(&g, up, from: 12)
            expect(g.phase == .resting && g.progress == 0, "and follows the lid back to where it rested before the close")
            expect(follows([7] + up, [1] + p), "without jumping")
        }
        do {
            var g = LidGesture()
            run(&g, hold(98, seconds: 2))
            g.displayOff()  // 一下合到底，还没来得及开始跟手
            run(&g, [0, 0, 2], from: 3)  // 屏熄时盖子在 0° 附近，读数照样来
            expect(g.displayOn(at: 5), "a close too fast to follow still gets the opening")
            expect(g.restBeforeClose == 98, "towards the angle the lid rested at")
        }
        do {
            var g = LidGesture()
            expect(!g.displayOn(at: 0), "the display lighting without having gone dark does nothing")
        }
        do {
            var g = LidGesture()
            run(&g, hold(104, seconds: 0.5) + ramp(104, 60, seconds: 1))
            expect(g.phase == .following, "a close half a second after launch still starts")
        }
        do {
            var g = LidGesture()
            run(&g, hold(60, seconds: 2) + ramp(60, 10, seconds: 2))
            expect(abs(g.progress - 1) < 0.001, "a lid that rests low still has a full twenty degree close")
        }

        // 真实录下的序列：只回放推送那一路（App 只用它）。打出进度走过的点供人对照文件名核对。
        let dir = "tests/fixtures/lid-traces"
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".csv") }.sorted()
        for file in files {
            guard let text = try? String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8) else { continue }
            var g = LidGesture()
            var progress: [Double] = []
            var angles: [Double] = []
            var peak = 0.0
            for line in text.split(separator: "\n").dropFirst() {
                let parts = line.split(separator: ",")
                guard parts.count == 3, parts[1] == "push", let t = Double(parts[0]), let a = Double(parts[2]) else { continue }
                g.feed(a, at: t)
                angles.append(a)
                progress.append(g.progress)
                peak = max(peak, g.progress)
            }
            print(String(format: "trace %@: peak %.2f, ends %.2f (%@)", file, peak, progress.last ?? 0, "\(g.phase)"))
            if file.hasPrefix("adjust") || file.hasPrefix("rest") {
                expect(peak == 0, "trace \(file) never starts")
            } else {
                expect(peak > 0.5, "trace \(file) closes")
                expect(g.phase == .resting && progress.last == 0, "trace \(file) ends back on the desktop")
                expect(follows(angles, progress), "trace \(file) only moves with the lid, never jumps")
            }
        }

        if failures == 0 { print("PASS: lid gesture follows the lid both ways and only for real closes") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
