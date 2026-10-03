import Foundation

/// 一台 Siri 遥控器的 HID 按键归一。不主动查询设备、不改 hidutil。
struct SiriRemoteButtons: Sendable {
    private struct Press: Sendable {
        let id: UInt64
        let began: WS2.Instant
        var halfSent = false
        var oneSent = false
    }
    private var held: [WS2.Button: Press] = [:]
    private var nextID: UInt64 = 0
    private var time = WS2.TimeGate()
    static let half: UInt64 = 500 * WS2.Duration.millisecond
    static let one: UInt64 = WS2.Duration.second

    static func button(page: UInt32, usage: UInt32) -> WS2.Button? {
        switch (page, usage) {
        case (0x0c, 0x42): return .up
        case (0x0c, 0x43): return .down
        case (0x0c, 0x44): return .left
        case (0x0c, 0x45): return .right
        case (0x0c, 0x80): return .select
        case (0x01, 0x86): return .back
        case (0x0c, 0x60): return .tv
        case (0x0c, 0xcd): return .playPause
        case (0x0c, 0xe2): return .mute
        case (0x0c, 0xe9): return .volumeUp
        case (0x0c, 0xea): return .volumeDown
        case (0x0c, 0x04): return .side
        default: return nil  // 没有实测电源 HID 用法；不猜。
        }
    }
    var nextWake: WS2.Instant? {
        held.values.compactMap { p in !p.halfSent ? p.began.adding(Self.half) :
            !p.oneSent ? p.began.adding(Self.one) : nil }.min()
    }
    mutating func report(page: UInt32, usage: UInt32, value: Int, at now: WS2.Instant) -> [WS2.ButtonEvent] {
        guard value == 0 || value == 1, let button = Self.button(page: page, usage: usage), time.accept(now) else { return [] }
        var out = advance(at: now)
        if value == 1 {
            guard held[button] == nil, nextID < UInt64.max else { return out }
            nextID += 1
            let p = Press(id: nextID, began: now); held[button] = p
            out.append(event(button, .down, p, now))
        } else if let p = held.removeValue(forKey: button) {
            out.append(event(button, .up, p, now))
        }
        return out
    }
    mutating func tick(at now: WS2.Instant) -> [WS2.ButtonEvent] {
        guard time.accept(now) else { return [] }
        return advance(at: now)
    }
    /// 断开、锁屏、睡眠、关闭功能时取消；不是伪造 up，因此不能触发短按动作。
    mutating func cancelAll(at now: WS2.Instant) -> [WS2.ButtonEvent] {
        guard time.accept(now) else { return [] }
        let out = WS2.Button.allCases.compactMap { b in held[b].map { event(b, .cancel, $0, now) } }
        held.removeAll(keepingCapacity: true)
        return out
    }
    private mutating func advance(at now: WS2.Instant) -> [WS2.ButtonEvent] {
        var out: [WS2.ButtonEvent] = []
        for b in WS2.Button.allCases {
            guard var p = held[b] else { continue }
            if !p.halfSent && now >= p.began.adding(Self.half) {
                p.halfSent = true; out.append(event(b, .heldHalfSecond, p, now))
            }
            if !p.oneSent && now >= p.began.adding(Self.one) {
                p.oneSent = true; out.append(event(b, .heldOneSecond, p, now))
            }
            held[b] = p
        }
        return out
    }
    private func event(_ button: WS2.Button, _ phase: WS2.ButtonPhase, _ p: Press, _ at: WS2.Instant) -> WS2.ButtonEvent {
        WS2.ButtonEvent(button: button, phase: phase, pressID: p.id, beganAt: p.began, at: at)
    }
}
