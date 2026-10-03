import Foundation

/// 中键手势只输出意图。原始 down/drag/up 的所有权由 I4 负责；本类型不补发按键。
struct MiddleDrag: Sendable {
    enum Region: Sendable { case titlebar, other, unknown }
    enum Event: Sendable { case down(WS2.Point, Region), move(WS2.Point), up(WS2.Point), cancel }
    enum Effect: Equatable, Sendable {
        case passThrough
        case clickTitlebar
        case preview(WS2.Action, Double)
        case commit(WS2.Action)
        case cancelled
        case fault(WS2.Fault)
    }
    private struct Contact: Sendable {
        let origin: WS2.Point
        let region: Region
        var axis: Axis?
        var exceededThreshold = false
        var lastAction: WS2.Action?
        var progress = 0.0
    }
    private enum Axis: Sendable { case horizontal, vertical }
    private var contact: Contact?
    private var time = WS2.TimeGate()
    static let threshold = 10.0
    static let dominance = 1.25
    static let fullTravel = 180.0
    static let commitProgress = 0.6
    var isTracking: Bool { contact != nil }

    mutating func handle(_ event: Event, at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        switch event {
        case .down(let point, let region):
            guard point.isFinite else { return [.fault(.malformedInput)] }
            let interrupted = contact != nil
            contact = region == .unknown ? nil : Contact(origin: point, region: region)
            return interrupted ? [.cancelled, .passThrough] : [.passThrough]
        case .move(let point): return update(point)
        case .up(let point):
            guard point.isFinite else { contact = nil; return [.cancelled, .fault(.malformedInput)] }
            guard contact != nil else { return [.passThrough] }
            let preview = update(point)
            guard let final = contact else { return preview }
            contact = nil
            if !final.exceededThreshold { return final.region == .titlebar ? [.clickTitlebar] : [.passThrough] }
            if let action = final.lastAction, final.progress >= Self.commitProgress { return [.commit(action)] }
            return [.cancelled]
        case .cancel:
            guard contact != nil else { return [] }
            contact = nil; return [.cancelled]
        }
    }
    private mutating func update(_ point: WS2.Point) -> [Effect] {
        guard point.isFinite else { contact = nil; return [.cancelled, .fault(.malformedInput)] }
        guard var c = contact else { return [.passThrough] }
        let dx = point.x - c.origin.x, dy = point.y - c.origin.y
        guard dx.isFinite, dy.isFinite else { contact = nil; return [.cancelled, .fault(.malformedInput)] }
        let distance = hypot(dx, dy)
        if distance > Self.threshold { c.exceededThreshold = true }
        if c.axis == nil && distance > Self.threshold {
            if abs(dx) > Self.dominance * abs(dy) { c.axis = .horizontal }
            else if abs(dy) > Self.dominance * abs(dx) { c.axis = .vertical }
        }
        guard let axis = c.axis else { contact = c; return [.passThrough] }
        let signed = axis == .horizontal ? dx : dy
        c.progress = min(1, max(0, (abs(signed) - Self.threshold) / (Self.fullTravel - Self.threshold)))
        let action: WS2.Action
        if c.region == .titlebar {
            action = axis == .horizontal ? (signed >= 0 ? .titlebarRight : .titlebarLeft)
                : (signed >= 0 ? .titlebarUp : .titlebarDown)
        } else {
            action = axis == .horizontal ? (signed >= 0 ? .spaceRight : .spaceLeft)
                : (signed >= 0 ? .missionControl : .appWindows)
        }
        c.lastAction = action; contact = c
        return [.preview(action, c.progress)]
    }
}
