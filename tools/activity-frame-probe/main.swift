import Cocoa
import QuartzCore

@MainActor final class FrameProbe: NSObject {
    let view = NotchActivityView(frame: NSRect(x: 0, y: 0, width: 420, height: 142))
    var panel: NSPanel!
    var link: CADisplayLink?
    var began = 0.0, last = 0.0
    var intervals: [Double] = []
    var handlers: [Double] = []
    var frames = 0
    let fixtures = [
        NotchActivity(id: "music", kind: .music, title: "音乐播放（测试数据）", subtitle: "动画检查", symbol: "music.note", startedAt: 1, progress: 0.4),
        NotchActivity(id: "drop", kind: .airDrop, title: "隔空投送（测试数据）", subtitle: "2 个文件", symbol: "airdrop", startedAt: 1),
        NotchActivity(id: "route", kind: .route, title: "路线（测试数据）", subtitle: "预计 12 分钟", symbol: "car.fill", startedAt: 1)
    ]
    func start() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        panel = NSPanel(contentRect: NSRect(x: screen.maxX - 456, y: screen.minY + 28, width: 420, height: 168),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.backgroundColor = .black
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 168))
        panel.contentView = host; host.addSubview(view)
        let caption = NSTextField(labelWithString: "实时活动动画检查 · 测试数据 · 6 秒后关闭")
        caption.frame = NSRect(x: 12, y: 145, width: 396, height: 18); caption.textColor = .white
        caption.font = .systemFont(ofSize: 11); host.addSubview(caption)
        view.onSelect = { [weak self] id in guard let self else { return }; self.view.update(self.fixtures, selected: id, expanded: true) }
        view.update(fixtures, selected: "music", expanded: true)
        panel.orderFrontRegardless()
        link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.finish() }
    }
    @objc func tick(_ sender: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        if began == 0 { began = now }
        if last != 0 { intervals.append((now - last) * 1000) }
        last = now; frames += 1
        let phase = (now - began).truncatingRemainder(dividingBy: 1.2)
        let start = ProcessInfo.processInfo.systemUptime
        if phase < 0.8 { _ = view.swipe(-260 * CGFloat(sin(phase * .pi / 0.8)), touching: true, velocity: 0) }
        else if view.isDraggingActivity { _ = view.swipe(0, touching: false, velocity: 0, cancelled: true) }
        handlers.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        if now - began >= 6 { finish() }
    }
    func finish() {
        guard link != nil else { return }
        link?.invalidate(); link = nil; panel.orderOut(nil)
        guard !intervals.isEmpty else { print("UNAVAILABLE display-link callbacks"); NSApp.terminate(nil); return }
        let sorted = intervals.sorted(), cpu = handlers.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let stalls = intervals.filter { $0 > median * 1.8 }.count
        print(String(format: "RENDER CHECK: %d callbacks; interval median %.2f ms p95 %.2f ms max %.2f ms; gaps>1.8×median %d; gesture-handler p95 %.3f ms", frames, median, p95, sorted.last!, stalls, cpu[Int(Double(cpu.count - 1) * 0.95)]))
        print("Display-link delivery measures main-loop responsiveness during visible native compositing; it is not a GPU presentation/fps guarantee.")
        NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let probe = FrameProbe()
    probe.start()
    app.run()
    withExtendedLifetime(probe) {}
}
