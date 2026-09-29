// 侧拉的直接操作：位置连续、速度有方向，取消不提交。
import Foundation
import CoreGraphics

enum SlideOverMotion {
    static func position(start: CGFloat, inward: CGFloat, open: CGFloat, parked: CGFloat) -> CGFloat {
        let sign: CGFloat = parked > open ? 1 : -1
        let travel = abs(parked - open)
        let outward = (start - open) * sign - inward
        let bounded: CGFloat
        if outward < 0 {
            bounded = -CGFloat(FluidMotion.rubberBand(Double(-outward), limit: 40))
        } else if outward > travel {
            bounded = travel + CGFloat(FluidMotion.rubberBand(Double(outward - travel), limit: 24))
        } else { bounded = outward }
        return open + bounded * sign
    }

    static func willHide(position: CGFloat, velocity: CGFloat, open: CGFloat, parked: CGFloat) -> Bool {
        let sign: CGFloat = parked > open ? 1 : -1
        let projected = (position - open) * sign + CGFloat(FluidMotion.projection(velocity: Double(velocity * sign)))
        return projected > abs(parked - open) / 2
    }
}

/// 指针事件只覆盖最新目标，慢窗口不会积累一长串过时位置。结束回调在最后一次写入停止之后。
typealias SlideOverDragWriter = LatestValueWriter<CGPoint>

/// 同上，写什么都行：拖动写位置，拖把手改大小时写外框。
final class LatestValueWriter<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "WindowShade.slide-over-drag", qos: .userInteractive)
    private var pending: Value?
    private var scheduled = false
    private var stopped = false
    private let apply: (Value) -> Void

    init(prepare: @escaping () -> Void = {}, apply: @escaping (Value) -> Void) {
        self.apply = apply
        queue.async(execute: DispatchWorkItem(block: prepare))
    }

    func submit(_ point: Value) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        pending = point
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !stopped, let point = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            apply(point)
        }
    }

    func stop(_ completion: @escaping () -> Void = {}) {
        lock.lock(); stopped = true; pending = nil; lock.unlock()
        queue.async(execute: DispatchWorkItem(block: completion))
    }

    func stopAndWait() {
        lock.lock(); stopped = true; pending = nil; lock.unlock()
        queue.sync {}
    }
}
