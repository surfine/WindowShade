// 合盖效果触发逻辑（Core/LidGesture.swift）：先用造出来的序列钉住规则，
// tests/fixtures/lid-traces/ 里有真实录下的序列时，一并回放（见 docs/lid-effect.md「怎么测」）。
import Foundation

@main
struct LidGestureTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    /// 以 10Hz 喂一段角度（模拟推送），返回发出的指令和时刻。
    static func run(_ gesture: inout LidGesture, _ angles: [Double], from start: Double = 0) -> [(Double, LidGesture.Command)] {
        var out: [(Double, LidGesture.Command)] = []
        for (index, angle) in angles.enumerated() {
            let time = start + Double(index) * 0.1
            if let command = gesture.feed(angle, at: time) { out.append((time, command)) }
        }
        return out
    }
    static func hold(_ angle: Double, seconds: Double) -> [Double] { Array(repeating: angle, count: Int(seconds * 10)) }
    static func ramp(_ from: Double, _ to: Double, seconds: Double) -> [Double] {
        let steps = max(1, Int(seconds * 10))
        return (1...steps).map { (from + (to - from) * Double($0) / Double(steps)).rounded() }
    }

    static func main() {
        do {
            var g = LidGesture()
            let commands = run(&g, hold(104, seconds: 2) + ramp(104, 40, seconds: 3))
            expect(commands.map(\.1) == [.playClose], "a steady close from rest plays the closing animation once")
            expect(g.phase == .closed, "and holds the closed look")
        }
        do {
            var g = LidGesture()
            let commands = run(&g, hold(104, seconds: 2) + ramp(104, 60, seconds: 2) + hold(60, seconds: 3) + ramp(60, 104, seconds: 2))
            expect(commands.map(\.1) == [.playClose, .playOpen], "closing to 60 and back plays close, then open")
            expect(g.phase == .resting, "and ends at rest")
        }
        do {
            var g = LidGesture()
            let commands = run(&g, hold(103, seconds: 2) + ramp(103, 90, seconds: 0.6) + hold(90, seconds: 2)
                                    + ramp(90, 109, seconds: 1) + hold(109, seconds: 2) + ramp(109, 96, seconds: 0.6))
            expect(commands.isEmpty, "adjusting the screen by thirteen degrees (Aaron's recorded habit) triggers nothing")
        }
        do {
            var g = LidGesture()
            let noisy = (0..<200).map { 101.0 + Double([0, 1, 0, -1, 1][$0 % 5]) }
            expect(run(&g, noisy).isEmpty, "a lid resting on the 103 degree line with one degree of noise triggers nothing")
        }
        do {
            var g = LidGesture()
            let commands = run(&g, hold(104, seconds: 2) + ramp(104, 20, seconds: 1.5))
            expect(commands.map(\.1) == [.playClose], "a slow full close plays the closing animation")
            g.displayOff()
            expect(g.feed(0, at: 10) == nil, "while the display is dark nothing plays")
            expect(g.displayOn(at: 20) == .playOpen, "when the display lights again the opening animation plays")
            expect(g.phase == .resting, "and the gesture is back at rest")
        }
        do {
            var g = LidGesture()
            _ = run(&g, hold(104, seconds: 2))
            g.displayOff()  // 一下合到底，合上动画没来得及播
            expect(g.displayOn(at: 5) == .playOpen, "a close too fast for the closing animation still gets the opening one")
        }
        do {
            var g = LidGesture()
            expect(g.displayOn(at: 0) == nil, "the display lighting without having gone dark plays nothing")
        }
        do {
            var g = LidGesture()
            let commands = run(&g, hold(104, seconds: 0.5) + ramp(104, 30, seconds: 2))
            expect(commands.map(\.1) == [.playClose], "a close half a second after launch still triggers")
        }
        do {
            var g = LidGesture()
            expect(g.feed(60, at: 0) == nil, "the very first reading only becomes the rest angle")
        }
        do {
            var g = LidGesture()
            g.displayOff()
            _ = g.displayOn(at: 0)
            let commands = run(&g, hold(104, seconds: 2) + ramp(104, 50, seconds: 2), from: 1)
            expect(commands.map(\.1) == [.playClose], "after waking, a new rest angle is learned and the next close triggers")
        }

        // 真实录下的序列：每个文件只回放推送那一路（App 以后只用它），打出指令供人对照文件名核对。
        let dir = "tests/fixtures/lid-traces"
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".csv") }.sorted()
        for file in files {
            guard let text = try? String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8) else { continue }
            var g = LidGesture()
            var commands: [String] = []
            for line in text.split(separator: "\n").dropFirst() {
                let parts = line.split(separator: ",")
                guard parts.count == 3, parts[1] == "push", let t = Double(parts[0]), let a = Double(parts[2]) else { continue }
                if let command = g.feed(a, at: t) { commands.append(String(format: "%.1fs %@", t, "\(command)")) }
            }
            print("trace \(file): \(commands.isEmpty ? "no commands" : commands.joined(separator: ", "))")
            if file.hasPrefix("adjust") || file.hasPrefix("rest") {
                expect(commands.isEmpty, "trace \(file) must not trigger")
            }
        }

        if failures == 0 { print("PASS: lid gesture plays close and open only for real closes") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
