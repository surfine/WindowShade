// 跟手后的短动画用的帧时钟：有屏就挂那块屏的 CADisplayLink，按显示器真实刷新率走（60Hz 屏不再被 120Hz 定时器多叫醒一倍）；
// 拿不到屏才退回原来的 120Hz 定时器。动画曲线都是按 CACurrentMediaTime 解析算的，换时钟不改曲线。
// 约定与 Timer 一样：主线程创建，回调在主线程，invalidate 之后不再回调。

import AppKit

@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private var timer: Timer?
    private let onTick: @MainActor (FrameTicker) -> Void

    init(screen: NSScreen?, fallbackInterval: TimeInterval = 1.0 / 120,
         onTick: @escaping @MainActor (FrameTicker) -> Void) {
        self.onTick = onTick
        super.init()
        if let screen {
            let link = screen.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let fallback = Timer(timeInterval: fallbackInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let self { self.onTick(self) } }
            }
            RunLoop.main.add(fallback, forMode: .common)
            timer = fallback
        }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
    }

    @objc nonisolated private func step(_ link: CADisplayLink) {
        MainActor.assumeIsolated { onTick(self) }
    }
}
