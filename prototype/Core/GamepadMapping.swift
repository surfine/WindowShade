// WindowShade 2 · 原创映射。只计算意图，不发送系统输入。
import Foundation
struct GamepadMapping: Sendable {
    struct Vector: Equatable, Sendable { var x: Double; var y: Double; static let zero = Vector(x: 0, y: 0) }
    enum Effect: Equatable, Sendable { case pointer(Vector), scroll(Vector), desktop(Int), releaseTriggers }
    static let deadZone = 0.15
    static let maximumPointerSpeed = 1000.0
    static let maximumScrollSpeed = 800.0
    static let triggerThreshold = 0.6
    static let triggerReset = 0.2
    private(set) var enabled = false
    private var leftArmed = true
    private var rightArmed = true
    private var lastTime: Double?
    mutating func configure(enabled: Bool, gameInFront: Bool) -> [Effect] {
        let next = enabled && !gameInFront
        if next != self.enabled { lastTime = nil; leftArmed = true; rightArmed = true }
        let had = self.enabled; self.enabled = next
        return had && !next ? [.releaseTriggers] : []
    }
    static func axis(_ v: Vector) -> Vector {
        guard v.x.isFinite, v.y.isFinite else { return .zero }
        let x = min(1,max(-1,v.x)), y = min(1,max(-1,v.y))
        let length = hypot(x,y)
        guard length > deadZone else { return .zero }
        let magnitude = pow((min(1,length)-deadZone)/(1-deadZone),2)
        return Vector(x:x/length*magnitude,y:y/length*magnitude)
    }
    mutating func sample(left: Vector, right: Vector, at now: Double) -> [Effect] {
        guard enabled, now.isFinite, now >= 0 else { return [] }
        if let lastTime, now < lastTime { return [] }
        defer { lastTime = now }
        guard let previous = lastTime else { return [] }
        // 唤醒或卡帧不补发整段运动；最大推进 50ms。所有档位是本轮推荐值。
        let dt = min(0.05,now-previous), p = Self.axis(left), s = Self.axis(right)
        var effects: [Effect] = []
        if p != .zero { effects.append(.pointer(Vector(x:p.x*Self.maximumPointerSpeed*dt,y:p.y*Self.maximumPointerSpeed*dt))) }
        if s != .zero { effects.append(.scroll(Vector(x:s.x*Self.maximumScrollSpeed*dt,y:s.y*Self.maximumScrollSpeed*dt))) }
        return dt > 0 ? effects : []
    }
    mutating func trigger(left: Bool, value: Double, desktopEnabled: Bool) -> [Effect] {
        guard enabled, desktopEnabled, value.isFinite, (0...1).contains(value) else { return [] }
        if value <= Self.triggerReset {
            if left { leftArmed = true } else { rightArmed = true }; return []
        }
        let armed = left ? leftArmed : rightArmed
        guard armed, value >= Self.triggerThreshold else { return [] }
        if left { leftArmed = false } else { rightArmed = false }
        return [.desktop(left ? -1 : 1)]
    }
    mutating func disconnect() -> [Effect] { configure(enabled:false,gameInFront:false) }
}
