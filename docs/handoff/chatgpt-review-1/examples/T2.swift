// WindowShade 2 审查包：原创边界骨架，非完整功能。
import AppKit
import QuartzCore
@MainActor
func animateFocusRing(_ layer: CAShapeLayer, from: CGFloat,
                      remaining: TimeInterval, reducedMotion: Bool) {
    layer.removeAnimation(forKey: "focus.progress")
    let start = min(1, max(0, from))
    CATransaction.begin(); CATransaction.setDisableActions(true)
    layer.strokeEnd = reducedMotion ? start : 1
    CATransaction.commit()
    guard !reducedMotion, remaining.isFinite, remaining > 0 else { return }
    let animation = CABasicAnimation(keyPath: "strokeEnd")
    animation.fromValue = start; animation.toValue = 1
    animation.duration = remaining
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    layer.add(animation, forKey: "focus.progress")
}
