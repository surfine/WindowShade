// MO-07 帧节奏探针（docs/plans/identity-and-motion-2026-10-09.md §5.4）。开发版启动参数触发：
//   WindowShade --frame-rhythm-probe [--runs N] [--out path.json]
// 平时不加载、不起显示链接：只有 `FrameRhythmProbe.isRequested` 为真时由入口调用 `run`。
// 计算在 `Core/FrameRhythmAnalysis.swift`；这里只负责在屏幕刷新时钟上采样呈现层。
//
// 场景（各 N 次，默认 10）：展开、收起、对勾、倒数换字、展开途中每 50 ms 反向打断。
// 采样对象是探针自己的无边框小窗口里的图层，用的是真实令牌（Motion.spring）和 Motion.Fade / DigitSwap 的时长，
// 量的是"令牌 + 显示链接 + Core Animation"这一层；接进真实刘海面板的那一步见 docs/plans 里 MO-02 的说明。

import Cocoa
import QuartzCore

@MainActor
enum FrameRhythmProbe {
    static var isRequested: Bool { CommandLine.arguments.contains("--frame-rhythm-probe") }

    private static func option(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// 跑完所有场景，打印一行摘要，有 `--out` 时写 JSON；返回退出码（有场景未过线为 1）。
    static func run() async -> Int32 {
        let runs = max(1, Int(option("--runs") ?? "") ?? 10)
        guard let screen = NSScreen.main else { print("frame-rhythm: no screen"); return 2 }
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 420, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 120))
        window.contentView?.wantsLayer = true
        window.orderFrontRegardless()
        guard let root = window.contentView?.layer else { return 2 }

        let shape = CALayer()
        shape.backgroundColor = NSColor.black.cgColor
        shape.anchorPoint = CGPoint(x: 0, y: 0.5)
        shape.position = CGPoint(x: 10, y: 60)
        root.addSublayer(shape)
        let content = CALayer()
        content.backgroundColor = NSColor.white.cgColor
        content.frame = CGRect(x: 30, y: 50, width: 20, height: 20)
        content.opacity = 0
        root.addSublayer(content)

        let small: CGFloat = 40, large: CGFloat = 400
        let sampler = Sampler(screen: screen)
        let period = sampler.refreshPeriod
        var scenarios: [FrameRhythm.ScenarioReport] = []

        func settle(_ seconds: Double = 0.7) async { try? await Task.sleep(for: .seconds(seconds)) }
        func reset(width: CGFloat) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            shape.removeAllAnimations(); content.removeAllAnimations()
            shape.bounds = CGRect(x: 0, y: 0, width: width, height: 28)
            content.opacity = 0; content.transform = CATransform3DIdentity
            CATransaction.commit()
        }
        func progress(_ layer: CALayer, from: CGFloat, to: CGFloat) -> Double {
            let w = (layer.presentation() ?? layer).bounds.width
            return Double((w - from) / (to - from))
        }
        func animateWidth(_ target: CGFloat, token: Motion.Spring) {
            let a = Motion.spring(token, keyPath: "bounds.size.width")
            a.fromValue = (shape.presentation() ?? shape).bounds.width
            a.toValue = target
            shape.bounds.size.width = target
            shape.add(a, forKey: "w")
        }

        // 展开 / 收起：形状走，40% 门由显示链接帧读到后放内容淡入（与 MO-02 的目标做法一致）。
        for (name, from, to, token) in [("expand", small, large, Motion.notchSpring(for: .expanded, reduced: false)),
                                        ("collapse", large, small, Motion.notchSpring(for: .minimum, reduced: false))] {
            var frames: [FrameRhythm.FrameStats] = [], gates: [FrameRhythm.GateResult] = []
            for _ in 0..<runs {
                reset(width: from); await settle(0.1)
                var fired: Int?
                sampler.start { index in
                    let p = progress(shape, from: from, to: to)
                    if fired == nil, p >= Double(Motion.Fade.shapeGate) {
                        fired = index
                        let f = CABasicAnimation(keyPath: "opacity")
                        f.fromValue = 0; f.toValue = 1; f.duration = Motion.Fade.in
                        content.opacity = 1; content.add(f, forKey: "f")
                    }
                    return p
                }
                animateWidth(to, token: token)
                await settle(token.response * 3 + 0.3)
                let s = sampler.stop()
                frames.append(FrameRhythm.frameStats(timestamps: s.timestamps, refreshPeriod: period))
                // 门根本没触发：算没过，不能退回“首个 ≥ 40% 的帧”那条理想值路径（那样永远偏差 ≤ 1 个周期）。
                gates.append(fired == nil
                    ? FrameRhythm.GateResult(frameIndex: nil, progress: nil, deviation: nil, deviationPeriods: nil, withinOnePeriod: false)
                    : FrameRhythm.gateDeviation(progress: s.values, timestamps: s.timestamps,
                                                refreshPeriod: period, firedIndex: fired))
            }
            scenarios.append(FrameRhythm.merge(name: name, frames: frames, gates: gates, continuities: []))
        }

        // 对勾：pop 0.9→1 + 淡入。
        do {
            var frames: [FrameRhythm.FrameStats] = []
            for _ in 0..<runs {
                reset(width: small); await settle(0.1)
                sampler.start { _ in Double((content.presentation() ?? content).opacity) }
                let a = Motion.spring(.pop, keyPath: "transform.scale")
                a.fromValue = 0.9; a.toValue = 1
                let f = CABasicAnimation(keyPath: "opacity")
                f.fromValue = 0; f.toValue = 1; f.duration = Motion.Fade.in
                content.opacity = 1; content.add(a, forKey: "s"); content.add(f, forKey: "f")
                await settle(a.settlingDuration + 0.3)
                let s = sampler.stop()
                frames.append(FrameRhythm.frameStats(timestamps: s.timestamps, refreshPeriod: period))
            }
            scenarios.append(FrameRhythm.merge(name: "check", frames: frames, gates: [], continuities: []))
        }

        // 倒数换字：旧字淡出 + 下移，新字淡入 + pop（一次换字内两段）。
        do {
            var frames: [FrameRhythm.FrameStats] = []
            let plan = Motion.DigitSwap.plan(reduced: false)
            for _ in 0..<runs {
                reset(width: small); content.opacity = 1; await settle(0.1)
                sampler.start { _ in Double((content.presentation() ?? content).opacity) }
                let out = CABasicAnimation(keyPath: "opacity")
                out.fromValue = 1; out.toValue = 0; out.duration = plan.outDuration
                content.add(out, forKey: "out")
                try? await Task.sleep(for: .seconds(plan.outDuration))
                let inn = CABasicAnimation(keyPath: "opacity")
                inn.fromValue = 0; inn.toValue = 1; inn.duration = plan.inDuration
                let pop = Motion.spring(.pop, keyPath: "transform.scale")
                pop.fromValue = plan.popFrom; pop.toValue = 1
                content.add(inn, forKey: "in"); content.add(pop, forKey: "pop")
                await settle(pop.settlingDuration + 0.3)
                let s = sampler.stop()
                frames.append(FrameRhythm.frameStats(timestamps: s.timestamps, refreshPeriod: period))
            }
            scenarios.append(FrameRhythm.merge(name: "countdown", frames: frames, gates: [], continuities: []))
        }

        // 打断：展开途中每 50 ms 反向换目标，读呈现层位置的二阶差分。
        do {
            var frames: [FrameRhythm.FrameStats] = [], conts: [FrameRhythm.ContinuityResult] = []
            let token = Motion.notchSpring(for: .expanded, reduced: false)
            for _ in 0..<runs {
                reset(width: small); await settle(0.1)
                sampler.start { _ in Double((shape.presentation() ?? shape).bounds.width) }
                var retargets: [Double] = []
                var target = large
                for _ in 0..<8 {
                    animateWidth(target, token: token)
                    retargets.append(CACurrentMediaTime())
                    target = target == large ? small : large
                    try? await Task.sleep(for: .milliseconds(50))
                }
                await settle(token.response * 3 + 0.3)
                let s = sampler.stop()
                frames.append(FrameRhythm.frameStats(timestamps: s.timestamps, refreshPeriod: period))
                conts.append(FrameRhythm.interruptContinuity(positions: s.values, timestamps: s.timestamps,
                                                             retargetTimes: retargets, refreshPeriod: period))
            }
            scenarios.append(FrameRhythm.merge(name: "interrupt", frames: frames, gates: [], continuities: conts))
        }

        window.orderOut(nil)
        let report = FrameRhythm.Report(refreshHz: (1 / period).rounded(), source: "token-layer", scenarios: scenarios)
        if let path = option("--out") {
            try? FrameRhythm.json(report).write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            print(FrameRhythm.json(report))
        }
        print(FrameRhythm.summaryLine(report))
        return scenarios.allSatisfy(FrameRhythm.passes) ? 0 : 1
    }

    /// 屏幕刷新时钟采样器：只在 `start`..`stop` 之间存在，停了就失效，不留空转。
    @MainActor
    final class Sampler: NSObject {
        private let screen: NSScreen
        private var link: CADisplayLink?
        private var read: ((Int) -> Double)?
        private var timestamps: [Double] = []
        private var values: [Double] = []

        init(screen: NSScreen) { self.screen = screen }

        var refreshPeriod: Double {
            let hz = screen.maximumFramesPerSecond
            return 1 / Double(max(hz, 60))
        }

        func start(_ read: @escaping (Int) -> Double) {
            stopLink()
            self.read = read
            timestamps.removeAll(keepingCapacity: true)
            values.removeAll(keepingCapacity: true)
            let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func stop() -> (timestamps: [Double], values: [Double]) {
            stopLink()
            read = nil
            return (timestamps, values)
        }

        private func stopLink() { link?.invalidate(); link = nil }

        @objc private func tick(_ l: CADisplayLink) {
            guard let read else { return }
            timestamps.append(l.timestamp)
            values.append(read(timestamps.count - 1))
        }
    }
}
