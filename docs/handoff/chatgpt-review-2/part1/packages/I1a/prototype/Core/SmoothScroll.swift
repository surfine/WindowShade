// WindowShade 2 · I1a。原创临界阻尼解析解，不拷第三方滚动代码。
import Foundation

/// 一维滚动核；水平和垂直各建一个实例。不合成输入事件。
struct SmoothScroll: Sendable {
    enum Preset: Sendable {
        case light, medium, trackpadLike
        var pointsPerNotch: Double {
            switch self { case .light: return 24; case .medium: return 36; case .trackpadLike: return 48 }
        }
        var omega: Double {
            switch self { case .light: return 32; case .medium: return 24; case .trackpadLike: return 18 }
        }
    }
    struct Frame: Equatable, Sendable {
        let delta: Double
        let finished: Bool
    }
    private(set) var position = 0.0
    private(set) var target = 0.0
    private(set) var velocity = 0.0
    /// 反向时明确撤销尚未发送的旧方向残量。输入 = 已输出 + 待输出 + 撤销量。
    private(set) var cancelledResidual = 0.0
    private(set) var totalInput = 0.0
    private var time = WS2.TimeGate()
    let preset: Preset
    init(preset: Preset = .medium) { self.preset = preset }
    var isFinished: Bool { position == target && velocity == 0 }
    var pending: Double { target - position }

    /// 同向先推进再累加；反向取消尚未发出的旧方向残量，不补发最后一小段旧方向。
    mutating func add(notches: Double, at now: WS2.Instant) -> Frame? {
        guard notches.isFinite, abs(notches) <= 120 else { return nil }
        let delta = notches * preset.pointsPerNotch
        let reversing = delta != 0 && ((pending != 0 && pending.sign != delta.sign) ||
            (velocity != 0 && velocity.sign != delta.sign))
        let proposedBase = reversing ? position : target
        guard (proposedBase + delta).isFinite, abs(proposedBase + delta) <= 1e12,
              (totalInput + delta).isFinite else { return nil }
        let frame: Frame
        if reversing {
            guard time.accept(now) else { return nil }
            cancelledResidual += pending; target = position; velocity = 0
            frame = Frame(delta: 0, finished: true)
        } else {
            guard let advanced = step(at: now) else { return nil }
            frame = advanced
        }
        target += delta; totalInput += delta
        return Frame(delta: frame.delta, finished: isFinished)
    }
    /// 解析推进，因此长帧与高刷新率积分相同。时间倒流返回 nil，不改变状态。
    mutating func step(at now: WS2.Instant) -> Frame? {
        let previous = time.last
        guard time.accept(now) else { return nil }
        guard let previous, !isFinished else { return Frame(delta: 0, finished: isFinished) }
        let dt = Double(now.elapsed(since: previous)) / 1e9
        guard dt > 0 else { return Frame(delta: 0, finished: isFinished) }
        let old = position
        let omega = preset.omega
        let displacement = position - target
        let c = velocity + omega * displacement
        let decay = exp(-omega * dt)
        position = target + (displacement + c * dt) * decay
        velocity = (velocity - omega * c * dt) * decay
        // 原目标不可越过。收敛的最后一帧补齐余量，总积分不因停机阈值改变。
        if (old < target && position > target) || (old > target && position < target) ||
            (abs(position - target) < 0.00001 && abs(velocity) < 0.00001) {
            position = target; velocity = 0
        }
        return Frame(delta: position - old, finished: isFinished)
    }
    /// 功能关闭/设备丢失时不继续发输入；返回取消的残量供测试与只含数字的诊断使用。
    @discardableResult mutating func cancel() -> Double {
        let residual = pending; cancelledResidual += residual
        target = position; velocity = 0
        return residual
    }
}
